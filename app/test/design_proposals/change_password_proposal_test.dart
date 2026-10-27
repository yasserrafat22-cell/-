@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/theme/app_colors.dart';
import 'package:qadisiyah/core/widgets/brand_waves.dart';
import 'package:qadisiyah/core/widgets/gradient_button.dart';
import 'package:qadisiyah/core/widgets/qadisiyah_logo.dart';

import '../helpers/test_app.dart';

/// مقترح تصميم «تغيير كلمة المرور الإجباري» — للمراجعة فقط.
/// ليس جزءًا من التطبيق؛ يُنقل إلى lib بعد اعتماد التصميم.
class ChangePasswordProposal extends StatelessWidget {
  const ChangePasswordProposal({
    super.key,
    required this.rules,
    this.error,
    this.filled = false,
  });

  /// حالة كل شرط: null لم يُكتب بعد، true متحقق، false غير متحقق.
  final List<(String, bool?)> rules;
  final String? error;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandWavesBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 90),
            child: Column(
              children: [
                const QadisiyahLogo(height: 92),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFE6EDF6)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.navy.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'تغيير كلمة المرور',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 96,
                          height: 5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: const LinearGradient(
                              stops: [0, 0.6, 0.6, 1],
                              colors: [
                                AppColors.primary,
                                AppColors.primaryBright,
                                Color(0xFFB9CCE6),
                                Color(0xFFB9CCE6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _InfoBanner(),
                      const SizedBox(height: 14),
                      _Field(
                        hint: 'كلمة المرور الحالية (المؤقتة)',
                        icon: Icons.lock_clock_rounded,
                        filled: filled,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        hint: 'كلمة المرور الجديدة',
                        icon: Icons.lock_rounded,
                        filled: filled,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        hint: 'تأكيد كلمة المرور الجديدة',
                        icon: Icons.lock_reset_rounded,
                        filled: filled,
                      ),
                      const SizedBox(height: 12),
                      _Rules(rules: rules),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        _ErrorBanner(message: error!),
                      ],
                      const SizedBox(height: 16),
                      GradientButton(
                        label: 'حفظ كلمة المرور',
                        icon: Icons.save_rounded,
                        onPressed: () {},
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: AppColors.textSecondary,
                          ),
                          label: const Text(
                            'تسجيل الخروج',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC7DFF5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_rounded, color: AppColors.primary, size: 30),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'لأمان حسابك يجب تعيين كلمة مرور جديدة خاصة بك قبل استخدام التطبيق.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.hint, required this.icon, required this.filled});

  final String hint;
  final IconData icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
          child: Text(
            hint,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
        TextField(
          controller: TextEditingController(text: filled ? '••••••••••' : ''),
          readOnly: true,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 16, color: AppColors.hint),
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
              child: Icon(icon, color: AppColors.primary, size: 28),
            ),
            suffixIcon: const Icon(
              Icons.visibility_off_outlined,
              color: AppColors.hint,
            ),
          ),
        ),
      ],
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.rules});

  final List<(String, bool?)> rules;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, ok) in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    switch (ok) {
                      true => Icons.check_circle_rounded,
                      false => Icons.cancel_rounded,
                      null => Icons.radio_button_unchecked_rounded,
                    },
                    size: 20,
                    color: switch (ok) {
                      true => AppColors.greenDark,
                      false => AppColors.error,
                      null => AppColors.hint,
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: switch (ok) {
                        true => AppColors.greenDark,
                        false => AppColors.error,
                        null => AppColors.textSecondary,
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5C2C2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _labels = [
  '8 أحرف على الأقل',
  'تحتوي على حروف وأرقام',
  'تختلف عن كلمة المرور الحالية',
  'مطابقة لحقل التأكيد',
];

/// الحالات المعروضة للمراجعة: فارغة، أثناء الكتابة، وخطأ من السيرفر.
final proposalStates = <String, ChangePasswordProposal>{
  'empty': ChangePasswordProposal(rules: [for (final l in _labels) (l, null)]),
  'validating': ChangePasswordProposal(
    filled: true,
    rules: [for (final (i, l) in _labels.indexed) (l, i < 3)],
  ),
  'error': ChangePasswordProposal(
    filled: true,
    rules: [for (final l in _labels) (l, true)],
    error: 'كلمة المرور الحالية غير صحيحة',
  ),
};

void main() {
  for (final MapEntry(key: name, value: screen) in proposalStates.entries) {
    testWidgets('proposal: $name', (tester) async {
      debugDisableShadows = false;
      try {
        await pumpScreen(tester, screen);
        await expectLater(
          find.byType(ChangePasswordProposal),
          matchesGoldenFile('goldens/change_password_$name.png'),
        );
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
