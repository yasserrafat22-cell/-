import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/password_rules.dart';

void main() {
  Map<PasswordRule, bool?> eval(String current, String next, String confirm) =>
      PasswordRule.evaluate(
        current: current,
        newPassword: next,
        confirmation: confirm,
      );

  test('nothing typed leaves every rule pending', () {
    expect(eval('', '', '').values, everyElement(isNull));
  });

  test('mirrors the server policy cases', () {
    // نفس حالات PasswordPolicyTests في السيرفر.
    const cases = {
      'short1': false,
      'onlyletters': false,
      '12345678': false,
      'Valid2026': true,
      'كلمةمرور2026': true,
    };
    for (final MapEntry(key: password, value: valid) in cases.entries) {
      final rules = eval('Temp1234', password, password);
      final policyOk =
          rules[PasswordRule.minLength]! &&
          rules[PasswordRule.lettersAndDigits]!;
      expect(policyOk, valid, reason: password);
    }
  });

  test('Arabic-Indic digits count as digits like on the server', () {
    final rules = eval('Temp1234', 'كلمةمرور٢٠٢٦', 'كلمةمرور٢٠٢٦');
    expect(rules[PasswordRule.lettersAndDigits], isTrue);
  });

  test('new password must differ from current and match confirmation', () {
    final same = eval('Same2026x', 'Same2026x', 'Same2026x');
    expect(same[PasswordRule.differsFromCurrent], isFalse);
    expect(PasswordRule.allSatisfied(same), isFalse);

    final mismatch = eval('Temp1234', 'Valid2026', 'Valid2027');
    expect(mismatch[PasswordRule.matchesConfirmation], isFalse);

    final ok = eval('Temp1234', 'Valid2026', 'Valid2026');
    expect(PasswordRule.allSatisfied(ok), isTrue);
  });
}
