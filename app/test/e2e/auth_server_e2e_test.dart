import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/device/device_identity.dart';
import 'package:qadisiyah/core/storage/secure_store.dart';
import 'package:qadisiyah/features/auth/data/remote_auth_repository.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';

/// يختبر كود الاتصال في التطبيق مقابل سيرفر حقيقي على قاعدة بيانات جديدة.
///
/// التشغيل:
/// `QADISIYAH_E2E_URL=http://127.0.0.1:5080 QADISIYAH_E2E_ADMIN_PASSWORD=... flutter test test/e2e`
void main() {
  final url = Platform.environment['QADISIYAH_E2E_URL'];
  final bootstrapPassword =
      Platform.environment['QADISIYAH_E2E_ADMIN_PASSWORD'];
  final skip = url == null || bootstrapPassword == null
      ? 'يحتاج سيرفرًا يعمل: QADISIYAH_E2E_URL وQADISIYAH_E2E_ADMIN_PASSWORD'
      : null;

  test('forced password change against the real server', skip: skip, () async {
    final store = InMemorySecureStore();
    RemoteAuthRepository repo() => RemoteAuthRepository(
      dio: Dio(BaseOptions(baseUrl: url!)),
      store: store,
      device: DeviceIdentity(store),
    );

    final session = await repo().login(
      username: 'admin',
      password: bootstrapPassword!,
    );
    expect(session.user.mustChangePassword, isTrue);

    await expectLater(
      repo().changePassword(
        currentPassword: 'Wrong12345',
        newPassword: 'NewAdmin2026',
      ),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.wrongCurrentPassword,
        ),
      ),
    );

    await expectLater(
      repo().changePassword(
        currentPassword: bootstrapPassword,
        newPassword: 'short',
      ),
      throwsA(
        isA<AuthException>().having((e) => e.message, 'message', contains('8')),
      ),
    );

    final changed = await repo().changePassword(
      currentPassword: bootstrapPassword,
      newPassword: 'NewAdmin2026',
    );
    expect(changed.user.mustChangePassword, isFalse);

    final restored = await repo().restoreSession();
    expect(restored, isA<ActiveSession>());
    expect((restored as ActiveSession).user.mustChangePassword, isFalse);

    await expectLater(
      repo().login(username: 'admin', password: bootstrapPassword),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.invalidCredentials,
        ),
      ),
    );
    final relogin = await repo().login(
      username: 'admin',
      password: 'NewAdmin2026',
    );
    expect(relogin.user.mustChangePassword, isFalse);

    await repo().logout();
    expect(await repo().restoreSession(), isA<NoSession>());
  });
}
