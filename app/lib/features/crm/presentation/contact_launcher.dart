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
  /// نفس قواعد السيرفر: موبايل مصري 11 رقمًا يبدأ بـ 010/011/012/015، أو أرضي
  /// مصري بكود المحافظة، أو رقم دولي كامل. يعيد سبب الرفض أو null إن كان صحيحًا.
  static String? phoneError(String input) {
    if (input.trim().isEmpty) return 'رقم الهاتف مطلوب';
    final e164 = toE164(input);
    if (e164 == null) return 'رقم الهاتف غير صحيح';
    if (!e164.startsWith('+20')) return null;
    if (RegExp(r'^\+201[0125]\d{8}$').hasMatch(e164) ||
        RegExp(r'^\+20[2-9]\d{7,8}$').hasMatch(e164)) {
      return null;
    }
    return e164.startsWith('+201')
        ? 'رقم الموبايل المصري 11 رقمًا ويبدأ بـ 010 أو 011 أو 012 أو 015'
        : 'رقم الهاتف غير صحيح';
  }

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
