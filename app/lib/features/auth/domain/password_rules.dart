/// شروط كلمة المرور الجديدة كما يفرضها السيرفر (`PasswordPolicy`)، مع شرطي
/// الاختلاف عن الحالية والتطابق مع التأكيد. السيرفر يبقى المرجع النهائي.
enum PasswordRule {
  minLength('8 أحرف على الأقل'),
  lettersAndDigits('تحتوي على حروف وأرقام'),
  differsFromCurrent('تختلف عن كلمة المرور الحالية'),
  matchesConfirmation('مطابقة لحقل التأكيد');

  const PasswordRule(this.label);

  final String label;

  static const minLengthValue = 8;

  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _digit = RegExp(r'\p{Nd}', unicode: true);

  /// حالة كل شرط: `null` لم يُكتب بعد، `true` متحقق، `false` غير متحقق.
  static Map<PasswordRule, bool?> evaluate({
    required String current,
    required String newPassword,
    required String confirmation,
  }) {
    final hasNew = newPassword.isNotEmpty;
    return {
      minLength: hasNew ? newPassword.length >= minLengthValue : null,
      lettersAndDigits: hasNew
          ? _letter.hasMatch(newPassword) && _digit.hasMatch(newPassword)
          : null,
      differsFromCurrent: hasNew && current.isNotEmpty
          ? newPassword != current
          : null,
      matchesConfirmation: confirmation.isNotEmpty
          ? confirmation == newPassword
          : null,
    };
  }

  static bool allSatisfied(Map<PasswordRule, bool?> state) =>
      state.values.every((ok) => ok == true);
}
