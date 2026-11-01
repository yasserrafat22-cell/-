import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../helpers/crm_fakes.dart';
import 'batch02_layout_test.dart'
    show capture, cases, checkReadable, pumpAt, shot;

/// «تسجيل مورد» و«بيانات المورد» على نفس المقاسات وتكبير الخط مثل قسم العملاء.
const _longSupplier = 'شركة الصفوة العالمية لاستيراد وتجارة خامات البلاستيك';

FakeCrmRepository _repo() {
  final s = sampleSupplier();
  return FakeCrmRepository(
      parties: [
        PartyDetail(
          id: s.id,
          version: s.version,
          number: 77,
          name: _longSupplier,
          isCustomer: false,
          isSupplier: true,
          phones: s.phones,
          interests: const [],
          products: s.products,
          canEdit: true,
          supplierActivityId: 'act-importer',
          representativeName: 'أحمد محمد',
          governorateId: 'gov-giza',
          region: s.region,
          supplierSummary: s.supplierSummary,
        ),
      ],
    )
    ..contactList['party-2'] = const [
      PartyContact(
        id: 'c-1',
        name: 'خالد عبدالرحمن السعيد',
        jobTitle: 'مدير المبيعات الإقليمي',
        mobile: '+966501234567',
        isPrimary: true,
      ),
    ];
}

void main() {
  for (final (name, size, scale) in cases) {
    testWidgets('supplier registration: $name', (tester) async {
      final problems = await capture((problems) async {
        await pumpAt(tester, CrmRoutes.newSupplier, size, scale, crm: _repo());
        await shot(tester, 'supplier_register_top_$name');
        checkReadable(problems, find.text('تسجيل مورد'), 'العنوان');
        await tester.drag(
          find.byKey(const Key('register.list')),
          const Offset(0, -6000),
        );
        await tester.pumpAndSettle();
        await shot(tester, 'supplier_register_bottom_$name');
        checkReadable(problems, find.text('حذف السجل'), 'زر حذف السجل');
      });
      expect(problems, isEmpty);
    });

    for (final (tab, label) in [
      (0, 'summary'),
      (1, 'products'),
      (2, 'employees'),
    ]) {
      testWidgets('supplier details $label: $name', (tester) async {
        final problems = await capture((problems) async {
          await pumpAt(
            tester,
            CrmRoutes.party('party-2'),
            size,
            scale,
            crm: _repo(),
          );
          checkReadable(problems, find.text(_longSupplier), 'اسم المورد');
          tester.widget<InkWell>(find.byKey(Key('tab.$tab'))).onTap!();
          await tester.pumpAndSettle();
          await shot(tester, 'supplier_${label}_$name');
          if (tab == 2) {
            checkReadable(
              problems,
              find.text('خالد عبدالرحمن السعيد'),
              'اسم الموظف',
            );
          }
          for (final b in ['تعديل', 'حذف السجل']) {
            checkReadable(problems, find.text(b), 'زر $b');
          }
        });
        expect(problems, isEmpty);
      });
    }
  }

  testWidgets('supplier save hint stays above the system nav bar', (t) async {
    await pumpAt(
      t,
      CrmRoutes.newSupplier,
      const Size(390, 844),
      1.0,
      crm: _repo(),
    );
    t.view
      ..padding = const FakeViewPadding(bottom: 96)
      ..viewPadding = const FakeViewPadding(bottom: 96);
    addTearDown(t.view.resetPadding);
    addTearDown(t.view.resetViewPadding);
    await t.pumpAndSettle();
    await t.drag(
      find.byKey(const Key('register.list')),
      const Offset(0, -6000),
    );
    await t.pumpAndSettle();
    expect(
      t.getRect(find.byKey(const Key('register.missing'))).bottom,
      lessThanOrEqualTo(844 - 48),
    );
  });
}
