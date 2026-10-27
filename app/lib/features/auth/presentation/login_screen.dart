import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/brand_waves.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/qadisiyah_logo.dart';
import '../application/auth_controller.dart';

/// شاشة تسجيل الدخول — مرجع التصميم ص5.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialMessage});

  /// رسالة تُعرض عند الوصول للشاشة بعد إنهاء جلسة (مثل إلغاء الجهاز).
  final String? initialMessage;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialMessage;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .login(_username.text, _password.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = failure?.message;
    });
  }

  void _showForgotPassword() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة الوصول'),
        content: const Text(
          'لإعادة تعيين كلمة المرور تواصل مع مدير النظام. '
          'سيصلك منه كلمة مرور مؤقتة، وسيُطلب منك تغييرها عند أول دخول.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandWavesBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        QadisiyahLogo(
                          height: (constraints.maxHeight * 0.30).clamp(
                            150.0,
                            250.0,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildCard(),
                        const SizedBox(
                          height: BrandWavesBackground.bottomInset - 24,
                        ),
                      ],
                    ),
                  ),
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تسجيل الدخول',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              const _TitleUnderline(),
              const SizedBox(height: 24),
              AppTextField(
                fieldKey: const Key('login.username'),
                controller: _username,
                hint: 'اسم المستخدم',
                icon: Icons.person_rounded,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                enabled: !_submitting,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'أدخل اسم المستخدم'
                    : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                fieldKey: const Key('login.password'),
                controller: _password,
                hint: 'كلمة المرور',
                icon: Icons.lock_rounded,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                enabled: !_submitting,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                trailing: IconButton(
                  key: const Key('login.togglePassword'),
                  tooltip: _obscure ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.hint,
                    size: 26,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 22),
              GradientButton(
                key: const Key('login.submit'),
                label: 'تسجيل الدخول',
                isLoading: _submitting,
                onPressed: _submit,
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: _showForgotPassword,
                  child: const Text(
                    'نسيت كلمة المرور؟',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primaryBright,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleUnderline extends StatelessWidget {
  const _TitleUnderline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 5,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
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
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
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
      ),
    );
  }
}
