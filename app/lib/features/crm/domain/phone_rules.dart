/// قواعد الهاتف المصري المشتركة بين التسجيل وبيانات الموظفين والمشاركة.
/// نفس قاعدة السيرفر: موبايل مصري 11 رقمًا بالضبط يبدأ بـ 010 أو 011 أو 012 أو 015.
library;

/// موبايل مصري: 11 رقمًا يبدأ بـ 010 أو 011 أو 012 أو 015.
final egyptianMobile = RegExp(r'^01[0125]\d{8}$');

/// الرقم كما كُتب بعد حذف المسافات والشرطات (الصفر الأول يبقى كما هو).
String phoneDigits(String input) => input.replaceAll(RegExp(r'[\s-]'), '');

/// الصيغة المحلية لرقم محفوظ: «+201001234567» تصبح «01001234567».
String localMobile(String input) {
  final d = phoneDigits(input);
  if (d.startsWith('+20')) return '0${d.substring(3)}';
  if (d.startsWith('0020')) return '0${d.substring(4)}';
  return d;
}

/// موبايل مصري صحيح كامل (المحلي أو المحفوظ بصيغة +20).
bool isEgyptianMobile(String input) =>
    egyptianMobile.hasMatch(localMobile(input));

/// رقم موظف العميل: فارغ مسموح (الحقل اختياري)، وغير الفارغ يجب أن يكون صحيحًا كاملًا.
String? employeeMobileError(String input) {
  if (input.trim().isEmpty) return null;
  final d = phoneDigits(input);
  if (!RegExp(r'^\+?\d+$').hasMatch(d)) return 'أرقام فقط';
  return isEgyptianMobile(d)
      ? null
      : 'رقم الموبايل المصري 11 رقمًا ويبدأ بـ 010 أو 011 أو 012 أو 015';
}
