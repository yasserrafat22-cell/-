import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_store.dart';
import 'app_config.dart';

/// العنوان المحفوظ عند فتح التطبيق؛ يُقرأ في `main` قبل تشغيل الواجهة.
final initialServerUrlProvider = Provider<String>(
  (ref) => AppConfig.apiBaseUrl,
);

/// يُستبدل في `main` بالتخزين الآمن الفعلي.
final serverAddressStoreProvider = Provider<SecureStore>(
  (ref) => InMemorySecureStore(),
);

final serverAddressProvider = NotifierProvider<ServerAddress, String>(
  ServerAddress.new,
);

/// عنوان السيرفر الحالي. في نسخة الإصدار ثابت من إعدادات البناء،
/// وفي نسخة التجربة يمكن تغييره من شاشة الدخول.
class ServerAddress extends Notifier<String> {
  static const storageKey = 'server_url';

  @override
  String build() {
    final initial = ref.watch(initialServerUrlProvider);
    if (AppConfig.validateServerUrl(initial) != null) {
      throw StateError('عنوان السيرفر غير مسموح في هذه النسخة: $initial');
    }
    return initial;
  }

  /// يعيد سبب الرفض، أو `null` بعد الحفظ.
  Future<String?> set(String value) async {
    if (!AppConfig.isTrialBuild) return 'لا يمكن تغيير السيرفر في نسخة الإصدار';
    final error = AppConfig.validateServerUrl(value);
    if (error != null) return error;
    final url = AppConfig.normalizeServerUrl(value);
    await ref.read(serverAddressStoreProvider).write(storageKey, url);
    state = url;
    return null;
  }

  static Future<String> load(SecureStore store) async {
    if (!AppConfig.isTrialBuild) return AppConfig.apiBaseUrl;
    final saved = await store.read(storageKey);
    return saved != null && AppConfig.validateServerUrl(saved) == null
        ? saved
        : AppConfig.apiBaseUrl;
  }
}
