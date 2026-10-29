import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';
import 'package:qadisiyah/features/crm/presentation/quick_entry_screen.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

const _secretary = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000009',
  username: 'office',
  displayName: 'السكرتارية',
  roles: ['secretary'],
  permissions: {
    'customers.view_all',
    'suppliers.view_all',
    'customers.create',
    'suppliers.create',
    'reports.export',
    'import.run',
  },
  mustChangePassword: false,
);

const _rep = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000011',
  username: 'rep',
  displayName: 'مندوب',
  roles: ['representative'],
  permissions: {'customers.view', 'customers.create', 'suppliers.create'},
  mustChangePassword: false,
);

PartyDetail _unclassified() => const PartyDetail(
  id: 'party-u',
  version: 1,
  name: 'بدون اسم (+201001112223)',
  isCustomer: false,
  isSupplier: false,
  phones: [Phone(e164: '+201001112223', isPrimary: true)],
  interests: [],
  products: [],
  canEdit: false,
  canAdd: false,
  nameMissing: true,
  pendingGrade: 'HP500N',
  canComplete: true,
);

void main() {
  testWidgets('quick entry lists tools by permission', (tester) async {
    await pumpCrmApp(tester, at: CrmRoutes.quickEntry, user: _secretary);
    expect(find.byType(QuickEntryScreen), findsOneWidget);
    for (final key in [
      'addMaterial',
      'importParties',
      'importCatalog',
      'template.parties',
      'template.catalog',
      'exportCatalog',
      'incomplete',
    ]) {
      expect(find.byKey(Key('quick.$key')), findsOneWidget, reason: key);
    }
    // كتالوج الإدارة للمدير فقط.
    expect(find.byKey(const Key('quick.catalog')), findsNothing);
  });

  testWidgets('a representative has no import or bulk export', (tester) async {
    await pumpCrmApp(tester, at: CrmRoutes.quickEntry, user: _rep);
    expect(find.byKey(const Key('quick.addMaterial')), findsOneWidget);
    expect(find.byKey(const Key('quick.incomplete')), findsOneWidget);
    expect(find.byKey(const Key('quick.importParties')), findsNothing);
    expect(find.byKey(const Key('quick.exportCatalog')), findsNothing);
  });

  testWidgets('templates and catalog export are shared as Excel files', (
    tester,
  ) async {
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await tapVisible(tester, find.byKey(const Key('quick.template.parties')));
    await tapVisible(tester, find.byKey(const Key('quick.exportCatalog')));
    expect(crm.exported, ['template.parties', 'catalog']);
    expect(crm.shared.last, contains('.xlsx'));
  });

  testWidgets('import previews counts, remaps columns, and imports valid rows '
      'once with a stable id', (tester) async {
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.importFile('parties'),
      user: _secretary,
    );
    await tapVisible(tester, find.byKey(const Key('import.pick')));
    expect(crm.importCalls.single.$1, 'preview');
    expect(find.text('جديد: 1'), findsOneWidget);
    expect(find.text('غير صالح: 1'), findsOneWidget);
    expect(find.text('مراجعة: 1'), findsOneWidget);
    expect(find.text('غير مصنف — يحتاج تحديد النوع'), findsOneWidget);
    expect(find.text('استيراد الصفوف السليمة (1)'), findsOneWidget);

    // تصفية بالحالة.
    await tapVisible(tester, find.byKey(const Key('import.count.review')));
    expect(find.byKey(const Key('import.row.4')), findsOneWidget);
    expect(find.byKey(const Key('import.row.2')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('import.count.review')));

    // تعيين يدوي: عمود الهاتف ← لا شيء.
    await tapVisible(tester, find.byKey(const Key('import.mapping')));
    await tapVisible(tester, find.byKey(const Key('import.map.phone')));
    await tester.tap(find.text('—').last);
    await tester.pumpAndSettle();
    final remap = crm.importCalls.last;
    expect(remap.$1, 'preview');
    expect(remap.$2, {'name': 0, 'phone': -1, 'grade': 2, 'type': 3});

    await tapVisible(tester, find.byKey(const Key('import.commit')));
    final commit = crm.importCalls.last;
    expect(commit.$1, 'commit');
    expect(commit.$3, isNotNull);
    expect(commit.$2, remap.$2);
    expect(find.byKey(const Key('import.done')), findsOneWidget);
  });

  testWidgets('an unclassified record is completed by filling blanks only', (
    tester,
  ) async {
    final crm = FakeCrmRepository(parties: [_unclassified()]);
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.party('party-u'),
      user: _secretary,
    );
    await tapVisible(tester, find.byKey(const Key('profile.complete')));
    expect(find.textContaining('HP500N'), findsOneWidget);
    // الرقم موجود فلا يُطلب.
    expect(find.byKey(const Key('complete.phone')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('complete.name')),
      'شركة الأمل',
    );
    await tester.tap(find.byKey(const Key('complete.customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('complete.save')));
    await tester.pumpAndSettle();
    expect(crm.completions.single, (
      'party-u',
      'شركة الأمل',
      null,
      true,
      false,
    ));
  });
}
