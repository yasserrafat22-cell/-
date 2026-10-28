import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/config/server_address.dart';
import 'package:qadisiyah/core/device/device_identity.dart';
import 'package:qadisiyah/core/storage/secure_store.dart';
import 'package:qadisiyah/features/auth/data/remote_auth_repository.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';

/// عقد التوافق بين الإصدارات: التحديث فوق نسخة مثبتة يجب أن يقرأ نفس المفاتيح
/// المحفوظة على الهاتف (الجلسة، معرف الجهاز، عنوان السيرفر). تغيير أي مفتاح
/// هنا يُفقد المستخدم بياناته بعد التحديث، فيحتاج ترحيلًا صريحًا للبيانات.
void main() {
  test('data written by the previous version is still read', () async {
    final store = InMemorySecureStore()
      ..values.addAll({
        'device_id': '0192f0c0-aaaa-7000-8000-000000000001',
        'server_url': 'http://192.168.1.12:5080',
        'auth_tokens':
            '{"accessToken":"a","accessTokenExpiresAt":"2026-10-27T12:15:00.000Z",'
            '"refreshToken":"r","refreshTokenExpiresAt":"2099-01-01T00:00:00.000Z"}',
        'auth_user':
            '{"id":"u1","username":"admin","displayName":"مدير النظام",'
            '"roles":["system_admin"],"permissions":[],"mustChangePassword":false}',
      });

    expect(
      await DeviceIdentity(store).id(),
      '0192f0c0-aaaa-7000-8000-000000000001',
    );
    expect(await ServerAddress.load(store), 'http://192.168.1.12:5080');

    // السيرفر غير متاح: الجلسة المحفوظة تُستعاد دون اتصال، أي أنها قُرئت.
    final repo = RemoteAuthRepository(
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9')),
      store: store,
      device: DeviceIdentity(store),
    );
    final restored = await repo.restoreSession();
    expect(restored, isA<ActiveSession>());
    expect((restored as ActiveSession).user.username, 'admin');
  });
}
