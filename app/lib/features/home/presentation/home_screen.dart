import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_waves.dart';
import '../../../core/widgets/qadisiyah_logo.dart';

import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../../crm/application/sync_controller.dart';
import '../../crm/presentation/crm_routes.dart';
import '../../crm/presentation/insights_screens.dart';
import '../../crm/presentation/sync_screen.dart';
import 'home_icons.dart';
import 'home_tile.dart';

/// الأقسام الخمسة في الشاشة الرئيسية.
enum HomeSection { customers, suppliers, search, reports, quickEntry }

/// الشاشة الرئيسية — مرجع التصميم ص4 (خمس وظائف).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _suppliersStyle = HomeTileStyle(
    background: [Color(0xFFF3F9FE), Color(0xFFDCEBFA)],
    swoosh: [AppColors.primary, AppColors.sky],
    titleColor: AppColors.navy,
  );
  static const _customersStyle = HomeTileStyle(
    background: [Color(0xFFF5FBEF), Color(0xFFE0F2CF)],
    swoosh: [Color(0xFF3E9B23), AppColors.greenLight],
    titleColor: AppColors.greenDark,
  );
  static const _searchStyle = HomeTileStyle(
    background: [Color(0xFFF3F9FE), Color(0xFFDCEBFA)],
    swoosh: [AppColors.navy, AppColors.primary],
    titleColor: AppColors.navy,
  );
  static const _reportsStyle = HomeTileStyle(
    background: [Color(0xFFFFFAF1), Color(0xFFFCEED3)],
    swoosh: [AppColors.reportsAccent, Color(0xFFFFCD55)],
    titleColor: AppColors.navy,
  );
  static const _quickEntryStyle = HomeTileStyle(
    background: [Color(0xFFF7F5FE), Color(0xFFE6E1FA)],
    swoosh: [Color(0xFF5B3CC0), Color(0xFF9479E6)],
    titleColor: AppColors.navy,
  );

  void _open(BuildContext context, WidgetRef ref, HomeSection section) {
    final auth = ref.read(authControllerProvider);
    final user = auth is Authenticated ? auth.user : null;
    switch (section) {
      case HomeSection.customers:
        context.push(CrmRoutes.newCustomer);
        return;
      case HomeSection.suppliers:
        context.push(CrmRoutes.newSupplier);
        return;
      // «السجل» الدائم: كل العملاء والموردين والبحث والمفضلة.
      case HomeSection.search:
        context.push(CrmRoutes.search);
        return;
      // الإدخال السريع: نوع خامة، استيراد Excel، القوالب، والسجلات الناقصة.
      case HomeSection.quickEntry:
        context.push(CrmRoutes.quickEntry);
        return;
      case HomeSection.reports when user?.can('reports.view') ?? false:
        context.push(CrmRoutes.reports);
        return;
      case HomeSection.reports:
        break;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('هذا القسم قيد التنفيذ في المرحلة التالية'),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final offline = auth is Authenticated && auth.offline;

    return Scaffold(
      body: BrandWavesBackground(
        child: SafeArea(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth.clamp(0.0, 520.0) - 32;
                  const gap = 14.0;
                  final tileWidth = (width - gap) / 2;
                  final tileHeight = tileWidth * 0.94;
                  final titleSize = (tileWidth * 0.125).clamp(15.0, 26.0);

                  Widget tile(
                    HomeSection section,
                    String title,
                    Widget icon,
                    HomeTileStyle style, {
                    String? subtitle,
                  }) {
                    return HomeTile(
                      key: Key('home.${section.name}'),
                      title: title,
                      subtitle: subtitle,
                      icon: icon,
                      style: style,
                      titleSize: titleSize,
                      onTap: () => _open(context, ref, section),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 28,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: width,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QadisiyahLogo(
                                height: (constraints.maxHeight * 0.27).clamp(
                                  130.0,
                                  230.0,
                                ),
                              ),
                              if (offline) ...[
                                const SizedBox(height: 8),
                                const _OfflineChip(),
                              ],
                              const SizedBox(height: 8),
                              const SyncBar(),
                              const SizedBox(height: 22),
                              SizedBox(
                                height: tileHeight,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: tile(
                                        HomeSection.customers,
                                        'تسجيل عملاء',
                                        const CustomersIcon(),
                                        _customersStyle,
                                      ),
                                    ),
                                    const SizedBox(width: gap),
                                    Expanded(
                                      child: tile(
                                        HomeSection.suppliers,
                                        'تسجيل موردين',
                                        const SuppliersIcon(),
                                        _suppliersStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: gap),
                              SizedBox(
                                height: tileHeight,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: tile(
                                        HomeSection.search,
                                        'البحث عن\nموردين أو عملاء',
                                        const SearchIcon(),
                                        _searchStyle,
                                      ),
                                    ),
                                    const SizedBox(width: gap),
                                    Expanded(
                                      child: tile(
                                        HomeSection.reports,
                                        'إنشاء واستخراج\nالتقارير',
                                        const ReportsIcon(),
                                        _reportsStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: gap),
                              SizedBox(
                                width: width * 0.64,
                                height: tileHeight * 0.86,
                                child: tile(
                                  HomeSection.quickEntry,
                                  'الإدخال السريع',
                                  const QuickEntryIcon(),
                                  _quickEntryStyle,
                                  subtitle: 'Excel + إعدادات',
                                ),
                              ),
                              const SizedBox(
                                height: BrandWavesBackground.bottomInset,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const PositionedDirectional(
                top: 4,
                start: 4,
                child: FollowUpBell(),
              ),
              PositionedDirectional(
                top: 4,
                end: 4,
                child: IconButton(
                  key: const Key('home.logout'),
                  tooltip: 'تسجيل الخروج',
                  onPressed: () => _logout(context, ref),
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// الأعمال غير المرسلة تبقى مشفرة على الجهاز باسم صاحبها ولا يراها مستخدم آخر،
/// وتُرسل عند دخوله مجددًا؛ يُنبَّه قبل الخروج حتى لا يظن أنها ضاعت أو وصلت.
Future<void> _logout(BuildContext context, WidgetRef ref) async {
  final waiting = ref.read(syncControllerProvider).ops.length;
  if (waiting > 0) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('توجد بيانات لم تُرسل'),
        content: Text(
          'لديك $waiting عملية لم تصل للسيرفر بعد. ستبقى محفوظة مشفرة على هذا الجهاز '
          'وتُرسل عند دخولك مرة أخرى، ولن يراها أي مستخدم آخر.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('home.confirmLogout'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  await ref.read(authControllerProvider.notifier).logout();
}

class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF5C77A)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFF9A6200)),
          SizedBox(width: 6),
          Text(
            'تعمل دون اتصال بالسيرفر',
            style: TextStyle(fontSize: 12, color: Color(0xFF9A6200)),
          ),
        ],
      ),
    );
  }
}
