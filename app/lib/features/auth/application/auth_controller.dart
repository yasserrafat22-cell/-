import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/device/device_identity.dart';
import '../../../core/storage/secure_store.dart';
import '../data/remote_auth_repository.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';

sealed class AuthState {
  const AuthState();
}

/// جارٍ استعادة الجلسة عند فتح التطبيق.
class AuthRestoring extends AuthState {
  const AuthRestoring();
}

class Unauthenticated extends AuthState {
  const Unauthenticated([this.reason]);

  final AuthFailure? reason;
}

class Authenticated extends AuthState {
  const Authenticated(this.user, {this.offline = false});

  final AuthUser user;
  final bool offline;
}

final secureStoreProvider = Provider<SecureStore>(
  (ref) => const FlutterSecureStore(),
);

final dioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
    ),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => RemoteAuthRepository(
    dio: ref.watch(dioProvider),
    store: ref.watch(secureStoreProvider),
    device: DeviceIdentity(ref.watch(secureStoreProvider)),
  ),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthRestoring();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<void> _restore() async {
    final restored = await _repository.restoreSession();
    state = switch (restored) {
      ActiveSession(:final user, :final offline) => Authenticated(
        user,
        offline: offline,
      ),
      NoSession(:final reason) => Unauthenticated(reason),
    };
  }

  /// يعيد سبب الفشل، أو `null` عند نجاح الدخول.
  Future<AuthFailure?> login(String username, String password) async {
    try {
      final session = await _repository.login(
        username: username,
        password: password,
      );
      state = Authenticated(session.user);
      return null;
    } on AuthException catch (e) {
      return e.failure;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const Unauthenticated();
  }
}
