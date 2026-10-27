import 'package:flutter/material.dart';

/// ألوان الهوية المأخوذة من الشعار والتصميمات المعتمدة (ص2–ص5).
abstract final class AppColors {
  // الأزرق
  static const navy = Color(0xFF0B3C78);
  static const primary = Color(0xFF0A5CB8);
  static const primaryBright = Color(0xFF1E9EEB);
  static const sky = Color(0xFF39B6E8);

  // الأخضر
  static const green = Color(0xFF5DB233);
  static const greenDark = Color(0xFF237A2B);
  static const greenLight = Color(0xFF8FD14F);

  // ألوان بطاقات الرئيسية
  static const reportsAccent = Color(0xFFF5A517);
  static const quickEntryAccent = Color(0xFF6A47C8);
  static const spreadsheetGreen = Color(0xFF1F7A45);

  // الأسطح والنصوص
  static const background = Color(0xFFF7FAFE);
  static const surface = Colors.white;
  static const fieldFill = Color(0xFFEEF3FA);
  static const fieldBorder = Color(0xFFD5DFEC);
  static const textPrimary = Color(0xFF0E2A4D);
  static const textSecondary = Color(0xFF5E6E85);
  static const hint = Color(0xFF7D8BA0);
  static const error = Color(0xFFC62828);
}
