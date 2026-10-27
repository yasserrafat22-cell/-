import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// حقل الإدخال بخلفية زرقاء فاتحة وأيقونة في بداية السطر كما في ص5.
/// [label] اختياري يظهر فوق الحقل بأسلوب نماذج التسجيل (ص7).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.trailing,
    this.obscureText = false,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.fieldKey,
    this.label,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Widget? trailing;
  final bool obscureText;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final Key? fieldKey;
  final String? label;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final field = _buildField();
    final label = this.label;
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
        field,
      ],
    );
  }

  Widget _buildField() {
    return TextFormField(
      onChanged: onChanged,
      key: fieldKey,
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autofillHints: autofillHints,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: !obscureText,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 17, color: AppColors.hint),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
          child: Icon(icon, color: AppColors.primary, size: 28),
        ),
        suffixIcon: trailing,
      ),
    );
  }
}
