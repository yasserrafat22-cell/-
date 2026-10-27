import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_waves.dart';
import '../../../core/widgets/qadisiyah_logo.dart';

/// تظهر أثناء استعادة الجلسة عند فتح التطبيق — مرجع الشعار ص2.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: BrandWavesBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QadisiyahLogo(height: 220),
              SizedBox(height: 32),
              SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
