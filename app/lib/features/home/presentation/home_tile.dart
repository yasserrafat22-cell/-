import 'package:flutter/material.dart';

/// ألوان بطاقة واحدة في الشاشة الرئيسية: خلفية متدرجة فاتحة وموجة سفلية ملونة.
class HomeTileStyle {
  const HomeTileStyle({
    required this.background,
    required this.swoosh,
    required this.titleColor,
  });

  final List<Color> background;
  final List<Color> swoosh;
  final Color titleColor;
}

/// بطاقة من بطاقات الشاشة الرئيسية (ص4).
class HomeTile extends StatelessWidget {
  const HomeTile({
    super.key,
    required this.title,
    required this.icon,
    required this.style,
    required this.onTap,
    this.subtitle,
    this.titleSize = 22,
  });

  final String title;
  final String? subtitle;
  final Widget icon;
  final HomeTileStyle style;
  final VoidCallback onTap;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title، $subtitle',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F0B3C78),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: Colors.white, width: 1.5),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: style.background,
                ),
              ),
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _SwooshPainter(style.swoosh)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 22),
                      child: Column(
                        children: [
                          Expanded(child: FittedBox(child: icon)),
                          const SizedBox(height: 8),
                          // ارتفاع ثابت يتسع لسطرين بنفس حجم الخط في كل البطاقات،
                          // ويُصغَّر العنوان فقط إذا لم يتسع العرض حتى لا يُقتطع.
                          SizedBox(
                            height: titleSize * (subtitle == null ? 2.7 : 2.25),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: titleSize,
                                        height: 1.3,
                                        fontWeight: FontWeight.w800,
                                        color: style.titleColor,
                                      ),
                                    ),
                                    if (subtitle != null)
                                      Text(
                                        subtitle!,
                                        textAlign: TextAlign.center,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontSize: titleSize * 0.62,
                                          fontWeight: FontWeight.w600,
                                          color: style.titleColor,
                                        ),
                                      ),
                                  ],
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
        ),
      ),
    );
  }
}

/// الموجة الملونة أسفل البطاقة: رفيعة من جهة وتزداد سماكة نحو الركن.
class _SwooshPainter extends CustomPainter {
  const _SwooshPainter(this.colors);

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.30, h)
      ..cubicTo(w * 0.58, h - 5, w * 0.84, h - 14, w, h - 30)
      ..lineTo(w, h)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(colors: colors)
          .createShader(Rect.fromLTWH(0, h - 30, w, 30));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SwooshPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
