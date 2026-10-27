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
}
