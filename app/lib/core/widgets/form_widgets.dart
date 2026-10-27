import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// الخط المتدرج أسفل عناوين البطاقات (ص5).
class TitleUnderline extends StatelessWidget {
  const TitleUnderline({super.key});

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

/// رسالة خطأ حمراء تُقرأ تلقائيًا لقارئ الشاشة.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

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
