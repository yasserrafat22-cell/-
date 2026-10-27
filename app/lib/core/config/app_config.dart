import 'package:flutter/foundation.dart';

/// إعدادات البناء تُمرَّر عبر `--dart-define` ولا تُكتب في الكود.
///
/// مثال: `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5080`
abstract final class AppConfig {
  /// العنوان الافتراضي يشير إلى السيرفر المحلي من محاكي Android.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5080',
  );

  static const connectTimeout = Duration(seconds: 10);
  static const receiveTimeout = Duration(seconds: 20);

  /// نسخة التجربة (Debug) فقط تسمح بتغيير عنوان السيرفر من شاشة الدخول
  /// وبالاتصال عبر HTTP داخل الشبكة المحلية.
  static const isTrialBuild = !kReleaseMode;

  /// يتحقق من صيغة العنوان؛ ونسخ الإصدار لا تقبل إلا HTTPS.
  /// يعيد سبب الرفض بالعربية، أو `null` إذا كان العنوان مقبولًا.
  static String? validateServerUrl(String value, {bool trial = isTrialBuild}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery) {
      return 'العنوان غير صحيح. مثال: http://192.168.1.50:5080';
    }
    if (!trial && uri.scheme != 'https') {
      return 'نسخة الإصدار تتطلب اتصالًا مشفرًا (HTTPS)';
    }
    return null;
  }

  static String normalizeServerUrl(String value) {
    final trimmed = value.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
