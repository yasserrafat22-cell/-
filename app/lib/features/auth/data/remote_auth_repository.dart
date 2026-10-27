import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/device/device_identity.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';

/// تنفيذ [AuthRepository] عبر واجهة السيرفر `/api/v1/auth`.
///
/// الرموز وبيانات المستخدم تُحفظ في [SecureStore] لاستعادة الجلسة
/// دون اتصال حتى انتهاء صلاحية رمز التحديث.
class RemoteAuthRepository implements AuthRepository {
  RemoteAuthRepository({
    required this._dio,
    required this._store,
    required this._device,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Dio _dio;
  final SecureStore _store;
  final DeviceIdentity _device;
  final DateTime Function() _clock;

  static const _tokensKey = 'auth_tokens';
  static const _userKey = 'auth_user';

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final response = await _post('/api/v1/auth/login', {
      'username': username.trim(),
      'password': password,
      'deviceId': await _device.id(),
      'deviceName': defaultTargetPlatform.name,
    });
    final session = AuthSession.fromJson(response);
    await _save(session);
    return session;
  }

  @override
  Future<RestoredSession> restoreSession() async {
    final tokensJson = await _store.read(_tokensKey);
    final userJson = await _store.read(_userKey);
    if (tokensJson == null || userJson == null) return const NoSession();

    final tokens = AuthTokens.fromJson(
      jsonDecode(tokensJson) as Map<String, dynamic>,
    );
    if (!tokens.refreshTokenExpiresAt.isAfter(_clock())) {
      await _clear();
      return const NoSession(AuthFailure.sessionExpired);
    }

    try {
      final response = await _post('/api/v1/auth/refresh', {
        'refreshToken': tokens.refreshToken,
        'deviceId': await _device.id(),
      });
      final session = AuthSession.fromJson(response);
      await _save(session);
      return ActiveSession(session.user, offline: false);
    } on AuthException catch (e) {
      if (e.failure == AuthFailure.network) {
        final user = AuthUser.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>,
        );
        return ActiveSession(user, offline: true);
      }
      await _clear();
      return NoSession(e.failure);
    }
  }

  @override
  Future<void> logout() async {
    final tokensJson = await _store.read(_tokensKey);
    await _clear();
    if (tokensJson == null) return;
    final tokens = AuthTokens.fromJson(
      jsonDecode(tokensJson) as Map<String, dynamic>,
    );
    try {
      await _post('/api/v1/auth/logout', {'refreshToken': tokens.refreshToken});
    } on AuthException {
      // الجلسة أُزيلت محليًا بالفعل؛ رمز التحديث سينتهي أو يُلغى من السيرفر.
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      return response.data ?? const {};
    } on DioException catch (e) {
      throw AuthException(_mapError(e));
    }
  }

  static AuthFailure _mapError(DioException e) {
    final response = e.response;
    if (response == null) return AuthFailure.network;
    final data = response.data;
    final code = data is Map ? data['code'] as String? : null;
    return switch (code) {
      'auth.invalid_credentials' => AuthFailure.invalidCredentials,
      'auth.locked' => AuthFailure.accountLocked,
      'auth.disabled' => AuthFailure.accountDisabled,
      'auth.device_revoked' => AuthFailure.deviceRevoked,
      'auth.invalid_refresh_token' => AuthFailure.sessionExpired,
      _ when response.statusCode == 401 => AuthFailure.sessionExpired,
      _ => AuthFailure.server,
    };
  }

  Future<void> _save(AuthSession session) async {
    await _store.write(_tokensKey, jsonEncode(session.tokens.toJson()));
    await _store.write(_userKey, jsonEncode(session.user.toJson()));
  }

  Future<void> _clear() async {
    await _store.delete(_tokensKey);
    await _store.delete(_userKey);
  }
}
