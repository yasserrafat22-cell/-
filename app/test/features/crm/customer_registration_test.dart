import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';
import 'package:qadisiyah/features/crm/presentation/customer_registration_screen.dart';
import 'package:qadisiyah/features/crm/presentation/party_profile_screen.dart';

import '../../helpers/crm_fakes.dart';

import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

const _rep = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000011',
  username: 'rep',
  displayName: 'أحمد محمد',
  roles: ['representative'],
  permissions: {'customers.view', 'customers.create', 'suppliers.create'},
  mustChangePassword: false,
);

const _secretary = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000009',
  username: 'office',
  displayName: 'منى السكرتارية',
  roles: ['secretary'],
  permissions: {
    'customers.view_all',
    'suppliers.view_all',
    'customers.create',
    'suppliers.create',
    'records.assign',
    'team.assign',
  },
  mustChangePassword: false,
);

Future<void> _type(WidgetTester t, String key, String text) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.enterText(find.byKey(Key(key)), text);
  await t.pumpAndSettle();
}

Future<void> _pickFromSheet(
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

bool _saveEnabled(WidgetTester t) =>
    t.widget<InkWell>(find.byKey(const Key('register.save'))).onTap != null;

Future<void> _required(WidgetTester t) async {
  await _type(t, 'register.name', 'شركة الأمل للبلاستيك');
  await _type(t, 'register.phone', '01009876543');
  await _pickFromSheet(t, 'register.gradeSearch', 'grade', [
    'PP500 — مصنع تجريبي أ',
  ]);
}

void main() {
  testWidgets('only name, Egyptian mobile and a material grade are required', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newCustomer, user: _rep);
    expect(find.byType(CustomerRegistrationScreen), findsOneWidget);
    // «أساسي» بجوار الإلزامي فقط: الاسم، الهاتف، الخامات، الجريدات.
    expect(find.text('أساسي'), findsNWidgets(4));
    expect(find.textContaining('اختياري'), findsNothing);
    expect(_saveEnabled(tester), isFalse);

    await _type(tester, 'register.name', 'شركة الأمل');
    await _type(tester, 'register.phone', '0131234567');
    expect(_saveEnabled(tester), isFalse);
    await _type(tester, 'register.phone', '01312345678');
    expect(_saveEnabled(tester), isFalse); // بادئة غير مصرية
    await _type(tester, 'register.phone', '01512345678');
    expect(_saveEnabled(tester), isFalse); // لا Grade بعد
    expect(find.textContaining('خامة + Grade'), findsOneWidget);

    // خامة بلا Grade لا تكفي.
    await _pickFromSheet(tester, 'register.materialSearch', 'material', [
      'PVC',
    ]);
    expect(_saveEnabled(tester), isFalse);
    await _pickFromSheet(tester, 'register.gradeSearch', 'grade', ['SG-5']);
    expect(_saveEnabled(tester), isTrue);

    // بريد خاطئ يمنع الحفظ، وتركه فارغًا لا يمنع.
    await _type(tester, 'register.email', 'not-an-email');
    expect(_saveEnabled(tester), isFalse);
    await _type(tester, 'register.email', '');
    expect(_saveEnabled(tester), isTrue);

    await tapVisible(tester, find.byKey(const Key('register.save')));
    final sent = crm.created.single;
    expect(sent.phone, '01512345678');
    expect(sent.toJson()['interests'], [
      {
        'materialId': 'mat-pvc',
        'gradeId': 'g-sg5',
        'originCountryId': null,
        'openSpec': false,
      },
    ]);
    // لا موظفين ولا مواقع ولا ملفات عند تركها فارغة.
    expect(crm.contactsAdded, isEmpty);
    expect(crm.locationsCreated, isEmpty);
    expect(crm.uploads, isEmpty);
    expect(find.byType(PartyProfileScreen), findsOneWidget);
  });

  testWidgets('identity shows the signed-in role and name, not editable', (
    tester,
  ) async {
    await pumpCrmApp(tester, at: CrmRoutes.newCustomer, user: _rep);
    final card = find.byKey(const Key('register.identity'));
    expect(
      find.descendant(of: card, matching: find.text('المندوب: مندوب مبيعات')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('أحمد محمد')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(TextField)),
      findsNothing,
    );
  });

  testWidgets('a full registration keeps every grade, employee, site and '
      'file and sends them after the record', (tester) async {
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.newCustomer,
      user: _secretary,
    );
    await _type(tester, 'register.name', 'مصنع النيل');
    await _type(tester, 'register.phone', '01112345678');

    // الخامات: البحث بالحروف الأولى، واختيار أكثر من خامة.
    await tapVisible(tester, find.byKey(const Key('register.materialSearch')));
    await tester.enterText(find.byKey(const Key('material.search')), 'HD');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('material.option.HDPE')), findsOneWidget);
    expect(find.byKey(const Key('material.option.PP')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('material.option.HDPE')));
    await tester.enterText(find.byKey(const Key('material.search')), '');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('material.option.PP')));
    await tapVisible(tester, find.byKey(const Key('material.done')));
    expect(find.byKey(const Key('register.material.HDPE')), findsOneWidget);
    expect(find.byKey(const Key('register.material.PP')), findsOneWidget);

    // Grade أول ثم ثانٍ: الأول يبقى والحقل لا يختفي.
    await _pickFromSheet(tester, 'register.gradeSearch', 'grade', [
      'PP500 — مصنع تجريبي أ',
    ]);
    await _pickFromSheet(tester, 'register.gradeSearch', 'grade', [
      '129H — مصنع تجريبي ب',
    ]);
    expect(find.byKey(const Key('register.grade.PP500')), findsOneWidget);
    expect(find.byKey(const Key('register.grade.129H')), findsOneWidget);
    expect(find.byKey(const Key('register.gradeSearch')), findsOneWidget);

    // موظفان، الثاني بوظيفة مخصصة.
    await _type(tester, 'register.employee.0.name', 'م. سامي');
    await _type(tester, 'register.employee.0.phone', '01001112223');
    await tapVisible(
      tester,
      find.byKey(const Key('register.employee.0.title')),
    );
    await tester.tap(find.text('مدير مشتريات').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('register.addEmployee')));
    await _type(tester, 'register.employee.1.name', 'أ. منى');
    await tapVisible(
      tester,
      find.byKey(const Key('register.employee.1.title')),
    );
    await tester.tap(find.text('وظيفة أخرى').last);
    await tester.pumpAndSettle();
    await _type(tester, 'register.employee.1.customTitle', 'محاسبة');

    // موقعان مستقلان: الأول يُحفظ ثم الثاني لا يحل محله.
    await _pickFromSheet(tester, 'register.governorate', 'governorate', [
      'الجيزة',
    ], done: false);
    await _pickFromSheet(tester, 'register.city', 'city', [
      '6 أكتوبر',
    ], done: false);
    await tapVisible(
      tester,
      find.byKey(const Key('register.siteKind.factory')),
    );
    await _type(
      tester,
      'register.siteLink',
      'https://www.google.com/maps?q=29.9,30.9',
    );
    await tapVisible(tester, find.byKey(const Key('register.saveSite')));
    await tapVisible(tester, find.byKey(const Key('register.siteKind.other')));
    await _type(tester, 'register.siteLabel', 'مكتب');
    await _type(tester, 'register.address', 'شارع التحرير');
    await tapVisible(tester, find.byKey(const Key('register.saveSite')));
    expect(find.byKey(const Key('register.site.0')), findsOneWidget);
    expect(find.byKey(const Key('register.site.1')), findsOneWidget);

    // صورة الشركة وملفان.
    await tapVisible(tester, find.byKey(const Key('register.logo')));
    await tester.tap(find.byKey(const Key('source.gallery')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('register.addFile')));
    await tapVisible(tester, find.byKey(const Key('register.addFile')));

    // السكرتارية تُسند لمندوب.
    await _pickFromSheet(tester, 'register.assign', 'assign', [
      'محمود علي',
    ], done: false);

    await tapVisible(tester, find.byKey(const Key('register.save')));
    final sent = crm.created.single;
    expect(sent.representativeId, 'rep-other');
    expect(
      (sent.toJson()['interests'] as List).map((i) => (i as Map)['gradeId']),
      containsAll(['g-pp500', 'g-129h']),
    );
    // HDPE مختارة بلا Grade تُحفظ أيضًا.
    expect(
      (sent.toJson()['interests'] as List).map((i) => (i as Map)['materialId']),
      contains('mat-hdpe'),
    );
    expect(sent.governorateId, 'gov-giza');
    expect(sent.region, '6 أكتوبر');

    expect(crm.contactsAdded.map((c) => (c.name, c.jobTitle, c.isPrimary)), [
      ('م. سامي', 'مدير مشتريات', true),
      ('أ. منى', 'محاسبة', false),
    ]);
    final sites = crm.locationsCreated.map((l) => l.$2).toList();
    expect(sites, hasLength(2));
    expect(sites[0].kind, LocationKind.factory);
    expect(sites[0].latitude, 29.9);
    expect(sites[0].governorateId, 'gov-giza');
    expect(sites[1].label, 'مكتب');
    expect(sites[1].addressLine, 'شارع التحرير');
    expect(sites.where((s) => s.isDefault), hasLength(1));
    expect(crm.uploads.map((u) => u['kind']), [
      AttachmentKind.logo,
      AttachmentKind.other,
      AttachmentKind.other,
    ]);
    expect(crm.locationsCreated.every((l) => l.$1 == sent.id), isTrue);
  });

  testWidgets('new material, grade and manufacturer are added from the last '
      'empty entry without dropping earlier choices', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newCustomer, user: _rep);
    await _pickFromSheet(tester, 'register.materialSearch', 'material', [
      'PP',
    ], done: false);
    await tester.enterText(find.byKey(const Key('material.addField')), 'POM');
    await tapVisible(tester, find.byKey(const Key('material.add')));
    await tapVisible(tester, find.byKey(const Key('material.done')));
    expect(crm.materialsCreated, ['POM']);
    expect(find.byKey(const Key('register.material.PP')), findsOneWidget);
    expect(find.byKey(const Key('register.material.POM')), findsOneWidget);

    // Grade جديد بلا شركة: لا تُخمَّن الشركة.
    await tapVisible(tester, find.byKey(const Key('register.gradeSearch')));
    await tester.enterText(find.byKey(const Key('grade.addField')), '668');
    await tapVisible(tester, find.byKey(const Key('grade.add')));
    await tapVisible(tester, find.byKey(const Key('gradeMaterial.option.PP')));
    await tapVisible(tester, find.byKey(const Key('grade.done')));
    expect(crm.gradesCreated.single['manufacturerId'], isNull);
    expect(crm.gradesCreated.single['materialId'], 'mat-pp');
    expect(find.byKey(const Key('register.grade.668')), findsOneWidget);

    // شركة جديدة من آخر القائمة، ثم Grade مرتبط بها صراحة.
    await tapVisible(tester, find.byKey(const Key('register.maker')));
    await tester.enterText(find.byKey(const Key('maker.addField')), 'Kayan');
    await tapVisible(tester, find.byKey(const Key('maker.add')));
    expect(find.text('Kayan'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('register.gradeSearch')));
    await tester.enterText(find.byKey(const Key('grade.addField')), '500P');
    await tapVisible(tester, find.byKey(const Key('grade.add')));
    await tapVisible(tester, find.byKey(const Key('gradeMaterial.option.PP')));
    await tapVisible(tester, find.byKey(const Key('grade.done')));
    expect(crm.gradesCreated.last['manufacturerId'], 'man-new');
    expect(find.byKey(const Key('register.grade.668')), findsOneWidget);
    expect(find.byKey(const Key('register.grade.500P')), findsOneWidget);
  });

  testWidgets('a representative cannot assign; sharing previews first', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newCustomer, user: _rep);
    await tester.ensureVisible(find.byKey(const Key('register.assign')));
    await tester.tap(find.byKey(const Key('register.assign')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assign.search')), findsNothing);

    await _type(tester, 'register.name', 'شركة الأمل');
    await _type(tester, 'register.phone', '01009876543');
    await _type(tester, 'register.email', 'info@amal.example');
    await tapVisible(tester, find.byKey(const Key('register.share')));
    expect(
      find.descendant(
        of: find.byKey(const Key('share.preview')),
        matching: find.textContaining('info@amal.example'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('share.field.email')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share.send')));
    await tester.pumpAndSettle();
    expect(crm.shared.last, contains('شركة الأمل'));
    expect(crm.shared.last, contains('01009876543'));
    expect(crm.shared.last, isNot(contains('info@amal.example')));
  });

  testWidgets('deleting an unsaved record asks first and sends nothing', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, user: _rep);
    await tester.tap(find.byKey(const Key('home.customers')));
    await tester.pumpAndSettle();
    await _required(tester);
    await tapVisible(tester, find.byKey(const Key('register.discard')));
    expect(find.text('حذف السجل؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('register.confirmDiscard')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerRegistrationScreen), findsNothing);
    expect(crm.created, isEmpty);
  });

  testWidgets('saving twice sends one record with the same id', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newCustomer, user: _rep);
    await _required(tester);
    await tester.ensureVisible(find.byKey(const Key('register.save')));
    await tester.tap(find.byKey(const Key('register.save')));
    await tester.tap(
      find.byKey(const Key('register.save')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(crm.createAttempts, hasLength(1));
  });

  testWidgets('a phone already registered to a supplier adds the customer '
      'role and its grades instead of a duplicate company', (tester) async {
    final crm = FakeCrmRepository()
      ..createError = const ApiException(
        'party.duplicate_phone',
        'رقم الهاتف مسجل بالفعل باسم «شركة الصفوة»',
        data: {
          'partyId': 'party-2',
          'name': 'شركة الصفوة',
          'isCustomer': false,
          'isSupplier': true,
        },
      );
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.newCustomer, user: _rep);
    await _required(tester);
    await tapVisible(tester, find.byKey(const Key('register.save')));
    await tester.tap(find.byKey(const Key('duplicate.addRole')));
    await tester.pumpAndSettle();
    expect(crm.roles, [('party-2', true)]);
    expect(crm.interestsAdded, [
      const SpecChoice(materialId: 'mat-pp', gradeId: 'g-pp500'),
    ]);
    expect(crm.created, isEmpty);
  });

  group('customer card', () {
    testWidgets('shows the number, stats and the approved tabs', (
      tester,
    ) async {
      final crm = FakeCrmRepository(parties: [sampleCustomer(number: 125)]);
      await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-1'));
      expect(find.text('# C000125'), findsOneWidget);
      for (final t in customerTabs) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('card.stat.2')),
          matching: find.text('2026-10-15'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('card.company')), findsOneWidget);
    });

    testWidgets('call lets the user choose between company and employee '
        'numbers and opens nothing else', (tester) async {
      final crm = FakeCrmRepository()
        ..contactList['party-1'] = [
          const PartyContact(
            id: 'c-1',
            name: 'م. سامي',
            jobTitle: 'مدير مشتريات',
            mobile: '+201112223334',
          ),
        ];
      await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-1'));
      await tester.tap(find.byKey(const Key('profile.call')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('contact.number.+201001234567')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('contact.number.+201112223334')),
        findsOneWidget,
      );
      expect(find.text('م. سامي - مدير مشتريات'), findsOneWidget);
    });
  });
}
