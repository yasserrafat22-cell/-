import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// خلفية الموجات الزرقاء والخضراء أعلى وأسفل الشاشة كما في ص4 وص5.
///
/// المحتوى يُرسم فوق الموجات، ويُترك له هامش علوي وسفلي عبر [topInset]
/// و[bottomInset] حتى لا يتداخل مع الموجات.
class BrandWavesBackground extends StatelessWidget {
  const BrandWavesBackground({super.key, required this.child});

  final Widget child;

  static const double topInset = 96;
  static const double bottomInset = 84;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 130,
            child: CustomPaint(painter: _TopWavesPainter()),
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 110,
            child: CustomPaint(painter: _BottomWavesPainter()),
          ),
          child,
        ],
      ),
    );
  }
}

Paint _gradientPaint(
  Rect rect,
  List<Color> colors, {
  Alignment begin = Alignment.centerLeft,
  Alignment end = Alignment.centerRight,
}) {
  return Paint()
    ..isAntiAlias = true
    ..shader = LinearGradient(
      begin: begin,
      end: end,
      colors: colors,
    ).createShader(rect);
}

class _TopWavesPainter extends CustomPainter {
  const _TopWavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // الشريط الأخضر الرفيع أسفل الموجة الزرقاء على اليسار.
    final greenRibbon = Path()
      ..moveTo(0, h * 0.62)
      ..cubicTo(w * 0.18, h * 0.40, w * 0.32, h * 0.20, w * 0.52, 0)
      ..lineTo(w * 0.58, 0)
      ..cubicTo(w * 0.36, h * 0.26, w * 0.20, h * 0.52, 0, h * 0.86)
      ..close();
    canvas.drawPath(
      greenRibbon,
      _gradientPaint(rect, const [AppColors.green, AppColors.greenLight]),
    );

    // الموجة الزرقاء الفاتحة.
    final skyWave = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.62, 0)
      ..cubicTo(w * 0.40, h * 0.18, w * 0.22, h * 0.40, 0, h * 0.70)
      ..close();
    canvas.drawPath(
      skyWave,
      _gradientPaint(rect, const [AppColors.primaryBright, AppColors.sky]),
    );

    // الموجة الزرقاء الداكنة الرئيسية.
    final navyWave = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.55, 0)
      ..cubicTo(w * 0.34, h * 0.14, w * 0.18, h * 0.30, 0, h * 0.56)
      ..close();
    canvas.drawPath(
      navyWave,
      _gradientPaint(rect, const [AppColors.navy, AppColors.primary]),
    );

    // الموجة الخضراء أعلى اليمين ثم الزرقاء أسفلها.
    final rightBlue = Path()
      ..moveTo(w, 0)
      ..lineTo(w * 0.70, 0)
      ..cubicTo(w * 0.80, h * 0.22, w * 0.90, h * 0.40, w, h * 0.46)
      ..close();
    canvas.drawPath(
      rightBlue,
      _gradientPaint(rect, const [AppColors.primaryBright, AppColors.primary]),
    );

    final rightGreen = Path()
      ..moveTo(w, 0)
      ..lineTo(w * 0.74, 0)
      ..cubicTo(w * 0.83, h * 0.14, w * 0.92, h * 0.26, w, h * 0.30)
      ..close();
    canvas.drawPath(
      rightGreen,
      _gradientPaint(rect, const [AppColors.greenLight, AppColors.green]),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BottomWavesPainter extends CustomPainter {
  const _BottomWavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // الشريط الأخضر أعلى الموجة السفلية جهة اليمين.
    final greenStripe = Path()
      ..moveTo(w * 0.30, h)
      ..cubicTo(w * 0.55, h * 0.62, w * 0.78, h * 0.30, w, h * 0.12)
      ..lineTo(w, h * 0.32)
      ..cubicTo(w * 0.80, h * 0.50, w * 0.58, h * 0.78, w * 0.40, h)
      ..close();
    canvas.drawPath(
      greenStripe,
      _gradientPaint(rect, const [AppColors.greenLight, AppColors.green]),
    );

    // الموجة الزرقاء الفاتحة.
    final skyWave = Path()
      ..moveTo(0, h * 0.50)
      ..cubicTo(w * 0.30, h * 0.80, w * 0.62, h * 0.66, w, h * 0.34)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      skyWave,
      _gradientPaint(rect, const [AppColors.sky, AppColors.primaryBright]),
    );

    // الموجة الزرقاء الداكنة.
    final navyWave = Path()
      ..moveTo(0, h * 0.70)
      ..cubicTo(w * 0.34, h * 0.98, w * 0.66, h * 0.82, w, h * 0.56)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      navyWave,
      _gradientPaint(rect, const [AppColors.primary, AppColors.navy]),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
