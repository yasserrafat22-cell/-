import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/brand_waves.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/qadisiyah_logo.dart';
import '../application/auth_controller.dart';
import '../domain/password_rules.dart';

/// تغيير كلمة المرور الإجباري — التصميم المعتمد في
/// `docs/04-proposal-change-password.md`.
///
/// يظهر بعد الدخول بكلمة مرور مؤقتة ولا يمكن تجاوزه؛ السيرفر يمنع أي عملية
/// محمية حتى يتم التغيير.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  final _obscure = <TextEditingController, bool>{};
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Map<PasswordRule, bool?> get _rules => PasswordRule.evaluate(
    current: _current.text,
    newPassword: _new.text,
    confirmation: _confirm.text,
  );

  Future<void> _submit() async {
    if (_submitting) return;
    if (_current.text.isEmpty || _new.text.isEmpty || _confirm.text.isEmpty) {
      setState(() => _error = 'أكمل جميع الحقول');
      return;
    }
    if (!PasswordRule.allSatisfied(_rules)) {
      setState(() => _error = 'كلمة المرور الجديدة لا تحقق كل الشروط');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await ref
        .read(authControllerProvider.notifier)
        .changePassword(_current.text, _new.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error?.message;
    });
  }

  Widget _field({
    required String keyName,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Iterable<String> autofill,
    TextInputAction action = TextInputAction.next,
  }) {
    final obscure = _obscure[controller] ?? true;
    return AppTextField(
      fieldKey: Key('changePassword.$keyName'),
      controller: controller,
      label: label,
      hint: label,
      icon: icon,
      obscureText: obscure,
      enabled: !_submitting,
      textInputAction: action,
      autofillHints: autofill,
      onChanged: (_) => setState(() {}),
      onFieldSubmitted: action == TextInputAction.done
          ? (_) => _submit()
          : null,
      trailing: IconButton(
        key: Key('changePassword.$keyName.toggle'),
        tooltip: obscure ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
        onPressed: () => setState(() => _obscure[controller] = !obscure),
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: AppColors.hint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandWavesBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 90),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    const QadisiyahLogo(height: 92),
                    const SizedBox(height: 14),
                    _buildCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
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
      child: AutofillGroup(
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
            const TitleUnderline(),
            const SizedBox(height: 14),
            const _InfoBanner(),
            const SizedBox(height: 14),
            _field(
              keyName: 'current',
              controller: _current,
              label: 'كلمة المرور الحالية (المؤقتة)',
              icon: Icons.lock_clock_rounded,
              autofill: const [AutofillHints.password],
            ),
            const SizedBox(height: 10),
            _field(
              keyName: 'new',
              controller: _new,
              label: 'كلمة المرور الجديدة',
              icon: Icons.lock_rounded,
              autofill: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 10),
            _field(
              keyName: 'confirm',
              controller: _confirm,
              label: 'تأكيد كلمة المرور الجديدة',
              icon: Icons.lock_reset_rounded,
              autofill: const [AutofillHints.newPassword],
              action: TextInputAction.done,
            ),
            const SizedBox(height: 12),
            _RulesList(rules: _rules),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 16),
            GradientButton(
              key: const Key('changePassword.submit'),
              label: 'حفظ كلمة المرور',
              icon: Icons.save_rounded,
              isLoading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                key: const Key('changePassword.logout'),
                onPressed: _submitting
                    ? null
                    : () => ref.read(authControllerProvider.notifier).logout(),
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

class _RulesList extends StatelessWidget {
  const _RulesList({required this.rules});

  final Map<PasswordRule, bool?> rules;

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
          for (final MapEntry(key: rule, value: ok) in rules.entries)
            Semantics(
              key: Key('changePassword.rule.${rule.name}.${ok ?? 'pending'}'),
              label:
                  '${rule.label}: ${switch (ok) {
                    true => 'متحقق',
                    false => 'غير متحقق',
                    null => 'لم يُكتب بعد',
                  }}',
              excludeSemantics: true,
              child: Padding(
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
                      color: _color(ok),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rule.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _color(ok),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Color _color(bool? ok) => switch (ok) {
    true => AppColors.greenDark,
    false => AppColors.error,
    null => AppColors.textSecondary,
  };
}
