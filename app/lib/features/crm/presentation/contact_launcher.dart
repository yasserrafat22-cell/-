import 'package:url_launcher/url_launcher.dart';

/// فتح تطبيق الاتصال أو واتساب. فتحهما لا يُسجل تواصلًا؛ النتيجة تُسجل في
/// شاشة «تسجيل تواصل» بعدها.
abstract final class ContactLauncher {
  static Future<bool> call(String e164) =>
      launchUrl(Uri(scheme: 'tel', path: e164));

  static Future<bool> whatsApp(String e164) => launchUrl(
    Uri.parse('https://wa.me/${e164.replaceAll('+', '')}'),
    mode: LaunchMode.externalApplication,
  );

  /// يقبل الرقم كما يكتبه المستخدم (01xxxxxxxxx أو +20...) لأزرار نموذج
  /// التسجيل قبل الحفظ، ويعيد null إذا لم يكن رقمًا صالحًا بعد.
  static String? toE164(String input) {
    var digits = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
    if (!digits.startsWith('+')) {
      digits = digits.startsWith('0')
          ? '+20${digits.substring(1)}'
          : '+20$digits';
    }
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(digits) ? digits : null;
  }
}
