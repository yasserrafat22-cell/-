import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// أيقونات البطاقات مركبة من أيقونات Material لتقارب رسومات ص4.
/// تُرسم دائمًا من اليسار لليمين حتى لا تنعكس في واجهة RTL.

class SuppliersIcon extends StatelessWidget {
  const SuppliersIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 120,
        height: 84,
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              child: Icon(
                Icons.local_shipping_rounded,
                size: 92,
                color: AppColors.primary,
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Icon(
                Icons.inventory_2_outlined,
                size: 44,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomersIcon extends StatelessWidget {
  const CustomersIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.groups_rounded,
      size: 100,
      color: AppColors.primary,
    );
  }
}

class SearchIcon extends StatelessWidget {
  const SearchIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.search_rounded, size: 96, color: AppColors.navy);
  }
}

class ReportsIcon extends StatelessWidget {
  const ReportsIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 96,
        height: 90,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Icon(
                Icons.insert_chart_outlined_rounded,
                size: 84,
                color: AppColors.navy,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: _Badge(
                color: AppColors.primary,
                icon: Icons.arrow_downward_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// جدول بيانات + سهم رفع + ترس إعدادات (استيراد Excel والإعدادات).
/// لا يُستخدم شعار Excel التجاري.
class QuickEntryIcon extends StatelessWidget {
  const QuickEntryIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 150,
        height: 80,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Icon(
                Icons.table_chart_rounded,
                size: 76,
                color: AppColors.spreadsheetGreen,
              ),
            ),
            Positioned(
              left: 52,
              bottom: 0,
              child: _Badge(
                color: AppColors.quickEntryAccent,
                icon: Icons.arrow_upward_rounded,
              ),
            ),
            Positioned(
              right: 0,
              top: 10,
              child: Icon(
                Icons.settings_rounded,
                size: 58,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
