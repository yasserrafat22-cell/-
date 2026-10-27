import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static const fontFamily = 'Cairo';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.green,
      error: AppColors.error,
      surface: AppColors.surface,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.fieldBorder),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(color: AppColors.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFill,
        hintStyle: const TextStyle(
          color: AppColors.hint,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontFamily: fontFamily),
      ),
    );
  }
}
