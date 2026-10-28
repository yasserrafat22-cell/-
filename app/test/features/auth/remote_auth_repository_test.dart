import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/device/device_identity.dart';
import 'package:qadisiyah/core/storage/secure_store.dart';
import 'package:qadisiyah/features/auth/data/remote_auth_repository.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';

/// يحاكي السيرفر على مستوى HTTP ويسجل الطلبات المرسلة.
class FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Map<String, ResponseBody Function(RequestOptions)> routes = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = routes[options.path];
    if (handler == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object> sessionJson({
  String refresh = 'refresh-1',
  String access = 'access',
  bool mustChange = false,
}) => {
  'accessToken': access,
  'accessTokenExpiresAt': '2026-10-27T12:15:00Z',
  'refreshToken': refresh,
  'refreshTokenExpiresAt': '2026-11-26T12:00:00Z',
  'user': {
    'id': '0192f0c0-0000-7000-8000-000000000001',
    'username': 'admin',
    'displayName': 'مدير النظام',
    'roles': ['system_admin'],
    'permissions': ['users.manage'],
    'mustChangePassword': mustChange,
  },
};

void main() {
  late FakeAdapter adapter;
  late InMemorySecureStore store;
  late DateTime now;

  RemoteAuthRepository repository() => RemoteAuthRepository(
    dio: Dio(BaseOptions(baseUrl: 'http://server'))
      ..httpClientAdapter = adapter,
    store: store,
    device: DeviceIdentity(store),
    clock: () => now,
  );

  setUp(() {
    adapter = FakeAdapter();
    store = InMemorySecureStore();
    now = DateTime.utc(2026, 10, 27, 12);
  });

  test('login sends trimmed username and a stable device id', () async {
    adapter.routes['/api/v1/auth/login'] = (_) => json(200, sessionJson());
    final repo = repository();

    final session = await repo.login(username: '  admin ', password: 'p');
    await repo.login(username: 'admin', password: 'p');

    expect(session.user.displayName, 'مدير النظام');
    final first = adapter.requests[0].data as Map;
    final second = adapter.requests[1].data as Map;
    expect(first['username'], 'admin');
    expect(first['deviceId'], isNotEmpty);
    expect(second['deviceId'], first['deviceId']);
    expect(store.values['auth_tokens'], contains('refresh-1'));
  });

  test('server error codes map to user-facing failures', () async {
    const cases = {
      'auth.invalid_credentials': AuthFailure.invalidCredentials,
      'auth.locked': AuthFailure.accountLocked,
      'auth.disabled': AuthFailure.accountDisabled,
      'auth.device_revoked': AuthFailure.deviceRevoked,
    };
    for (final MapEntry(key: code, value: failure) in cases.entries) {
      adapter.routes['/api/v1/auth/login'] = (_) =>
          json(code == 'auth.locked' ? 423 : 401, {'code': code});
      await expectLater(
        repository().login(username: 'a', password: 'b'),
        throwsA(
          isA<AuthException>().having((e) => e.failure, 'failure', failure),
        ),
      );
    }
  });

  test('no connection maps to network failure', () async {
    await expectLater(
      repository().login(username: 'a', password: 'b'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.network,
        ),
      ),
    );
  });

  test('restore refreshes and rotates the stored refresh token', () async {
    adapter.routes['/api/v1/auth/login'] = (_) => json(200, sessionJson());
    adapter.routes['/api/v1/auth/refresh'] = (_) =>
        json(200, sessionJson(refresh: 'refresh-2'));
    final repo = repository();
    await repo.login(username: 'admin', password: 'p');

    final restored = await repo.restoreSession();

    expect(restored, isA<ActiveSession>());
    expect((restored as ActiveSession).offline, isFalse);
    expect((adapter.requests.last.data as Map)['refreshToken'], 'refresh-1');
    expect(store.values['auth_tokens'], contains('refresh-2'));
  });

  test('restore without connection keeps an offline session', () async {
    adapter.routes['/api/v1/auth/login'] = (_) => json(200, sessionJson());
    final repo = repository();
    await repo.login(username: 'admin', password: 'p');

    final restored = await repo.restoreSession();

    expect(restored, isA<ActiveSession>());
    expect((restored as ActiveSession).offline, isTrue);
    expect(restored.user.username, 'admin');
  });

  test('restore after refresh expiry clears the session', () async {
    adapter.routes['/api/v1/auth/login'] = (_) => json(200, sessionJson());
    final repo = repository();
    await repo.login(username: 'admin', password: 'p');
    now = DateTime.utc(2026, 12, 1);

    final restored = await repo.restoreSession();

    expect(restored, isA<NoSession>());
    expect((restored as NoSession).reason, AuthFailure.sessionExpired);
    expect(store.values.containsKey('auth_tokens'), isFalse);
  });

  test('restore on a revoked device clears the session', () async {
    adapter.routes['/api/v1/auth/login'] = (_) => json(200, sessionJson());
    adapter.routes['/api/v1/auth/refresh'] = (_) =>
        json(401, {'code': 'auth.device_revoked'});
    final repo = repository();
    await repo.login(username: 'admin', password: 'p');

    final restored = await repo.restoreSession();

    expect((restored as NoSession).reason, AuthFailure.deviceRevoked);
    expect(store.values.containsKey('auth_user'), isFalse);
  });

  test('logout clears locally even when the server is unreachable', () async {
    adapter.routes['/api/v1/auth/login'] = (_) => json(200, sessionJson());
    final repo = repository();
    await repo.login(username: 'admin', password: 'p');
    adapter.routes.clear();

    await repo.logout();

    expect(store.values.containsKey('auth_tokens'), isFalse);
    expect(await repo.restoreSession(), isA<NoSession>());
  });

  group('changePassword', () {
    setUp(() {
      adapter.routes['/api/v1/auth/login'] = (_) =>
          json(200, sessionJson(mustChange: true, access: 'temp-access'));
    });

    test('sends the access token and stores the new session', () async {
      adapter.routes['/api/v1/auth/change-password'] = (_) =>
          json(200, sessionJson(refresh: 'after-change'));
      final repo = repository();
      await repo.login(username: 'admin', password: 'Temp1234');

      final session = await repo.changePassword(
        currentPassword: 'Temp1234',
        newPassword: 'Valid2026',
      );

      final request = adapter.requests.last;
      expect(request.headers['Authorization'], 'Bearer temp-access');
      expect(request.data, {
        'currentPassword': 'Temp1234',
        'newPassword': 'Valid2026',
      });
      expect(session.user.mustChangePassword, isFalse);
      expect(store.values['auth_tokens'], contains('after-change'));
      expect(store.values['auth_user'], contains('"mustChangePassword":false'));
    });

    test('refreshes an expired access token first', () async {
      adapter.routes['/api/v1/auth/refresh'] = (_) =>
          json(200, sessionJson(access: 'refreshed-access'));
      adapter.routes['/api/v1/auth/change-password'] = (_) =>
          json(200, sessionJson());
      final repo = repository();
      await repo.login(username: 'admin', password: 'Temp1234');
      now = DateTime.utc(2026, 10, 27, 13);

      await repo.changePassword(
        currentPassword: 'Temp1234',
        newPassword: 'Valid2026',
      );

      expect(
        adapter.requests.map((r) => r.path),
        contains('/api/v1/auth/refresh'),
      );
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer refreshed-access',
      );
    });

    test('maps wrong current and weak password with server detail', () async {
      final repo = repository();
      await repo.login(username: 'admin', password: 'Temp1234');

      adapter.routes['/api/v1/auth/change-password'] = (_) =>
          json(400, {'code': 'auth.wrong_current_password', 'detail': 'x'});
      await expectLater(
        repo.changePassword(currentPassword: 'a', newPassword: 'Valid2026'),
        throwsA(
          isA<AuthException>()
              .having(
                (e) => e.failure,
                'failure',
                AuthFailure.wrongCurrentPassword,
              )
              .having((e) => e.detail, 'detail', isNull),
        ),
      );

      adapter.routes['/api/v1/auth/change-password'] = (_) => json(400, {
        'code': 'auth.weak_password',
        'detail': 'كلمة المرور يجب ألا تقل عن 8 أحرف',
      });
      await expectLater(
        repo.changePassword(currentPassword: 'a', newPassword: 'b'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'كلمة المرور يجب ألا تقل عن 8 أحرف',
          ),
        ),
      );
      // الأخطاء القابلة للتصحيح لا تُنهي الجلسة.
      expect(store.values.containsKey('auth_tokens'), isTrue);
    });

    test('a revoked session is cleared', () async {
      adapter.routes['/api/v1/auth/change-password'] = (_) =>
          json(401, {'code': 'auth.device_revoked'});
      final repo = repository();
      await repo.login(username: 'admin', password: 'Temp1234');

      await expectLater(
        repo.changePassword(currentPassword: 'a', newPassword: 'Valid2026'),
        throwsA(isA<AuthException>()),
      );
      expect(store.values.containsKey('auth_tokens'), isFalse);
    });
  });

  test('concurrent token requests share a single refresh', () async {
    adapter.routes['/api/v1/auth/login'] = (_) => json(200, sessionJson());
    adapter.routes['/api/v1/auth/refresh'] = (_) =>
        json(200, sessionJson(refresh: 'refresh-2', access: 'new-access'));
    final repo = repository();
    await repo.login(username: 'admin', password: 'p');
    now = DateTime.utc(2026, 10, 27, 13);

    final tokens = await Future.wait([
      repo.accessToken(),
      repo.accessToken(),
      repo.accessToken(),
    ]);

    expect(tokens, everyElement('new-access'));
    expect(
      adapter.requests.where((r) => r.path == '/api/v1/auth/refresh'),
      hasLength(1),
    );
  });
}
