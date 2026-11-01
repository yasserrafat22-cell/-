import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/data/crm_repository.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';
import 'package:qadisiyah/features/crm/presentation/customer_registration_screen.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart'
    show fillSupplier, pumpCrmApp, saveRegistration, tapVisible;

/// «تسجيل مورد» و«بيانات المورد» بنفس مستوى قسم العملاء المعتمد مع قواعد المورد.

Future<void> _type(WidgetTester t, String key, String text) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.enterText(find.byKey(Key(key)), text);
  await t.pumpAndSettle();
}

Future<void> _sheet(
  WidgetTester t,
  String opener,
  String prefix,
  List<String> labels, {
  bool done = true,
}) async {
  await tapVisible(t, find.byKey(Key(opener)));
  for (final l in labels) {
    await tapVisible(t, find.byKey(Key('$prefix.option.$l')));
  }
  if (done) await tapVisible(t, find.byKey(Key('$prefix.done')));
}

void main() {
  testWidgets('a full supplier registration saves products with maker and '
      'origin, employees, sites and files to the same record', (t) async {
    final files = FakeFileServices();
    final crm = await pumpCrmApp(t, at: CrmRoutes.newSupplier, files: files);
    expect(find.text('تسجيل مورد'), findsOneWidget);
    // لا حقل «نشاط العميل» في المورد.
    expect(find.byKey(const Key('register.activities')), findsNothing);

    await fillSupplier(t, name: 'شركة الصفوة للخامات', phone: '0223456789');
    await _type(t, 'register.email', 'sales@safwa.example');
    await _type(t, 'register.employee.0.name', 'م. خالد');
    // رقم موظف المورد قد يكون دوليًا.
    await _type(t, 'register.employee.0.phone', '+966501234567');

    // جريد بلا شركة ثم الشركة: تُحفظ الشركة مع الجريد (نفس إصلاح العملاء).
    await _sheet(t, 'register.gradeSearch', 'grade', [
      'SG-5',
      'PP500 — مصنع تجريبي أ',
    ]);
    await _sheet(t, 'register.maker', 'maker', ['مصنع تجريبي ب'], done: false);
    expect(crm.gradesCreated.single['manufacturerId'], 'man-b');

    // بلد صنع PP500 من الشريحة.
    await t.ensureVisible(find.byKey(const Key('register.grade.PP500')));
    await t.tap(
      find
          .descendant(
            of: find.byKey(const Key('register.grade.PP500')),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await t.pumpAndSettle();
    await tapVisible(t, find.byKey(const Key('origin.option.السعودية')));

    await _sheet(t, 'register.governorate', 'governorate', [
      'القاهرة',
    ], done: false);
    await _type(t, 'register.address', 'المنطقة الحرة');
    await tapVisible(t, find.byKey(const Key('register.saveSite')));
    await tapVisible(t, find.byKey(const Key('register.addFile')));

    await saveRegistration(t);
    final party = crm.created.single;
    expect(party.isCustomer, isFalse);
    expect(party.activityId, 'act-importer');
    expect(party.email, 'sales@safwa.example');
    final json = party.toJson();
    expect(json['isSupplier'], isTrue);
    expect(json.containsKey('interests'), isFalse);
    expect(json.containsKey('customerActivityIds'), isFalse);
    final products = (json['products']! as List).cast<Map<String, Object?>>();
    expect(
      products.map((p) => (p['gradeId'], p['originCountryId'])),
      containsAll([('g-new', null), ('g-pp500', 'c-sa')]),
    );
    expect(crm.contactsAdded.single.mobile, '+966501234567');
    expect(crm.locationsCreated.single.$1, party.id);
    expect(crm.uploads.single['partyId'], party.id);
  });

  testWidgets('supplier rules: any valid phone, supplier type required, '
      'materials optional', (t) async {
    await pumpCrmApp(t, at: CrmRoutes.newSupplier);
    bool enabled() =>
        t.widget<InkWell>(find.byKey(const Key('register.save'))).onTap != null;
    await _type(t, 'register.name', 'مورد دولي');
    await _type(t, 'register.phone', '+8613800138000');
    expect(enabled(), isFalse); // نوع المورد إلزامي
    await tapVisible(t, find.byKey(const Key('register.supplierTypePicker')));
    await tapVisible(t, find.byKey(const Key('supplierType.option.مصنع')));
    expect(enabled(), isTrue); // بلا خامات
    await _type(t, 'register.phone', '0155566');
    expect(enabled(), isFalse);
    expect(find.text('أساسي'), findsNWidgets(3)); // الاسم والهاتف ونوع المورد
  });

  testWidgets('the supplier card shows supplies, products and supplier files '
      'and logs a supply from «more»', (t) async {
    await pumpCrmApp(t, at: CrmRoutes.party('party-2'));
    expect(find.byKey(const Key('details.supplierType')), findsOneWidget);
    expect(find.text('مورد نشط'), findsOneWidget);
    t.widget<InkWell>(find.byKey(const Key('tab.5'))).onTap!();
    await t.pumpAndSettle();
    expect(find.text('لا توجد توريدات مسجلة بعد'), findsOneWidget);

    await tapVisible(t, find.byKey(const Key('profile.more')));
    expect(find.byKey(const Key('more.supply')), findsOneWidget);
    expect(find.byKey(const Key('more.order')), findsNothing);
    await tapVisible(t, find.byKey(const Key('more.supply')));
    expect(find.text('تسجيل توريد جديد'), findsWidgets);
  });

  testWidgets('supplier contact sharing uses supplier wording and accepts '
      'international employee numbers', (t) async {
    final crm = FakeCrmRepository()
      ..contactList['party-2'] = [
        const PartyContact(
          id: 'c-sa',
          name: 'م. خالد',
          mobile: '+966501234567',
        ),
      ];
    await pumpCrmApp(t, crm: crm, at: CrmRoutes.party('party-2'));
    await tapVisible(t, find.byKey(const Key('profile.shareContact')));
    expect(find.byKey(const Key('share.invalidEmployee')), findsNothing);
    await tapVisible(t, find.byKey(const Key('share.send')));
    final text = crm.shared.single;
    expect(text, startsWith('🏢 *بيانات المورد*'));
    expect(text, contains('*👤 اسم المورد*'));
    expect(text, contains('📱 +966501234567'));
  });

  test('customer share text is unchanged by the supplier option', () {
    expect(
      buildContactShareText(name: 'شركة النور'),
      startsWith('🏢 *بيانات العميل*'),
    );
    expect(
      buildContactShareText(name: 'شركة', supplier: true),
      contains('*👤 اسم المورد*\nشركة'),
    );
  });

  testWidgets('offline: a supplier saved without connection opens its card', (
    t,
  ) async {
    final crm = FakeCrmRepository()..createOffline = true;
    await pumpCrmApp(t, crm: crm, at: CrmRoutes.newSupplier);
    await fillSupplier(t);
    await saveRegistration(t);
    expect(crm.created.single.isCustomer, isFalse);
    expect(find.text('حُفظ على الجهاز — بانتظار المزامنة'), findsOneWidget);
  });

  test('a supplier NewParty sends products, never interests', () {
    const p = NewParty(
      id: 'x',
      name: 'n',
      phone: '0223456789',
      isCustomer: false,
      activityId: 'act-importer',
      specs: [SpecChoice(materialId: 'mat-pp', gradeId: 'g-pp500')],
      activityIds: ['ca-film'],
    );
    final json = p.toJson();
    expect(json['supplierActivityId'], 'act-importer');
    expect(json.containsKey('customerActivityId'), isFalse);
    expect(json.containsKey('customerActivityIds'), isFalse);
    expect(
      (json['products']! as List).single,
      containsPair('gradeId', 'g-pp500'),
    );
  });
}
