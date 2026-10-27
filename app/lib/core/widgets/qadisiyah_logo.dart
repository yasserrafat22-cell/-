import 'package:flutter/material.dart';

/// الشعار الأصلي كما هو دون أي تعديل في الرسم أو الألوان.
///
/// `logo_trimmed.png` هو نفس ملف الشعار الأصلي بعد قص الهوامش الشفافة فقط
/// حتى يمكن ضبط حجمه داخل التخطيط بدقة.
class QadisiyahLogo extends StatelessWidget {
  const QadisiyahLogo({super.key, required this.height});

  final double height;

  static const assetPath = 'assets/brand/logo_trimmed.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'القادسية لتجارة مواد خام البلاستيك',
    );
  }
}
