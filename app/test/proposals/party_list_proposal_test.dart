@Tags(['golden'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/theme/app_colors.dart';
import 'package:qadisiyah/features/crm/presentation/crm_widgets.dart';

import '../golden/screens_golden_test.dart' show withShadows;
import '../helpers/test_app.dart';

/// مقترح شاشة قائمة العملاء/الموردين (لا يوجد لها تصميم معتمد).
/// موجود داخل test فقط ولا يدخل التطبيق قبل الموافقة.
class _Row {
  const _Row(
    this.name,
    this.activity,
    this.place,
    this.status,
    this.kind,
    this.last,
  );
  final String name;
  final String activity;
  final String place;
  final String status;
  final int kind; // 0 نشط، 1 يحتاج متابعة، 2 متوقف، 3 جديد
  final String last;
}

class PartyListProposal extends StatelessWidget {
  const PartyListProposal({super.key, required this.supplier});

  final bool supplier;

  @override
  Widget build(BuildContext context) {
    final rows = supplier
        ? const [
            _Row(
              'شركة الصفوة لمواد البلاستيك',
              'مصنع',
              'الجيزة',
              'نشط',
              0,
              'آخر توريد: 15 أكتوبر 2026',
            ),
            _Row(
              'المتحدة للبتروكيماويات',
              'مستورد',
              'الإسكندرية',
              'يحتاج متابعة',
              1,
              'آخر توريد: 2 أغسطس 2026',
            ),
            _Row(
              'مؤسسة الأمل للتجارة',
              'تاجر',
              'القاهرة',
              'جديد',
              3,
              'لم يتم التوريد بعد',
            ),
          ]
        : const [
            _Row(
              'شركة النور للصناعات البلاستيكية',
              'مصنع',
              'القاهرة',
              'نشط',
              0,
              'آخر طلب: 15 أكتوبر 2026',
            ),
            _Row(
              'مصنع الهدى للأكياس',
              'محول بلاستيك',
              'الشرقية',
              'يحتاج متابعة',
              1,
              'آخر طلب: 20 يوليو 2026',
            ),
            _Row(
              'الشروق للعبوات',
              'مصنع',
              'العاشر من رمضان',
              'متوقف',
              2,
              'آخر طلب: 3 مارس 2026',
            ),
            _Row(
              'مؤسسة الفجر',
              'تاجر',
              'الجيزة',
              'جديد',
              3,
              'لم يتم الطلب بعد',
            ),
          ];
    return CrmScaffold(
      title: supplier ? 'الموردين' : 'العملاء',
      icon: supplier ? Icons.local_shipping_rounded : Icons.groups_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextField(
            decoration: formDecoration(
              hint: 'بحث بالاسم أو رقم الهاتف أو الخامة',
              prefix: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, l) in [
                  'الكل (${rows.length})',
                  'نشط',
                  'يحتاج متابعة',
                  'متوقف',
                  'جديد',
                  'عملائي فقط',
                ].indexed)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(l),
                      selected: i == 0,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: i == 0 ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) {},
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final r in rows) ...[
            SectionCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.fieldFill,
                    child: Icon(
                      supplier
                          ? Icons.local_shipping_rounded
                          : Icons.factory_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${r.activity} • ${r.place}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Pill.forStatusColor(
                              r.status,
                              r.kind == 0 || r.kind == 3,
                              r.kind == 1,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                r.last,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      IconButton.filled(
                        onPressed: () {},
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        icon: const Icon(Icons.phone_rounded, size: 20),
                      ),
                      IconButton.filled(
                        onPressed: () {},
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.green,
                        ),
                        icon: const Icon(Icons.chat_rounded, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ActionPill(
          label: supplier ? 'إضافة مورد جديد' : 'إضافة عميل جديد',
          icon: Icons.person_add_alt_1_rounded,
          colors: ActionPill.blue,
          onTap: () {},
        ),
      ),
    );
  }
}

void main() {
  for (final supplier in [false, true]) {
    final name = supplier ? 'supplier_list' : 'customer_list';
    testWidgets(
      'proposal $name',
      (tester) => withShadows(() async {
        await pumpScreen(
          tester,
          RepaintBoundary(child: PartyListProposal(supplier: supplier)),
        );
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/proposal_${name}_390x844.png'),
        );
        if (Platform.environment['EXPORT_SCREENSHOTS'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final bytes = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            return data!.buffer.asUint8List();
          });
          Directory('../docs/phase3/proposals').createSync(recursive: true);
          File('../docs/phase3/proposals/proposal_$name.png')
              .writeAsBytesSync(bytes!);
        }
      }),
    );
  }
}
