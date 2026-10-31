import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/theme/app_colors.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/domain/phone_rules.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';
import 'package:qadisiyah/features/crm/presentation/customer_registration_screen.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

/// دفعة الإصلاحات 02 (الملاحظات 01–08) على مستوى التطبيق.

const _rep = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000011',
  username: 'rep',
  displayName: 'أحمد محمد',
  roles: ['representative'],
  permissions: {'customers.view', 'customers.create', 'suppliers.create'},
  mustChangePassword: false,
);

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

bool _saveEnabled(WidgetTester t) =>
    t.widget<InkWell>(find.byKey(const Key('register.save'))).onTap != null;

Future<void> _required(WidgetTester t) async {
  await _type(t, 'register.name', 'شركة الأمل للبلاستيك');
  await _type(t, 'register.phone', '01009876543');
  await _sheet(t, 'register.gradeSearch', 'grade', ['PP500 — مصنع تجريبي أ']);
}

Future<void> _save(WidgetTester t) async {
  await t.tap(find.byKey(const Key('register.save')));
  await t.pumpAndSettle();
}

Color? _border(WidgetTester t, String key) {
  final field = t.widget<TextField>(find.byKey(Key(key)));
  return (field.decoration!.enabledBorder! as OutlineInputBorder)
      .borderSide
      .color;
}

void main() {
  group('01 customer activity', () {
    testWidgets('optional: a customer saves without any activity', (t) async {
      final crm = await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
      await _required(t);
      expect(_saveEnabled(t), isTrue);
      await _save(t);
      expect(crm.created.single.activityIds, isEmpty);
      expect(
        crm.created.single.toJson().containsKey('customerActivityIds'),
        isFalse,
      );
    });

    testWidgets('several activities are chosen, shown, removable and saved', (
      t,
    ) async {
      final crm = await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
      await _required(t);
      await _sheet(t, 'register.activity', 'activity', [
        'حقن البلاستيك',
        'سحب الأفلام',
        'نفخ البلاستيك',
      ]);
      for (final a in ['حقن البلاستيك', 'سحب الأفلام', 'نفخ البلاستيك']) {
        expect(find.byKey(Key('register.activity.$a')), findsOneWidget);
      }
      // إزالة اختيار من شريحته.
      await tapVisible(
        t,
        find.descendant(
          of: find.byKey(const Key('register.activity.سحب الأفلام')),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      expect(
        find.byKey(const Key('register.activity.سحب الأفلام')),
        findsNothing,
      );
      await _save(t);
      expect(crm.created.single.activityIds, ['ca-injection', 'ca-blowing']);
      expect(crm.created.single.toJson()['customerActivityIds'], [
        'ca-injection',
        'ca-blowing',
      ]);
    });

    testWidgets('a new activity joins the catalog once and is selected', (
      t,
    ) async {
      final crm = await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
      await _required(t);
      await tapVisible(t, find.byKey(const Key('register.activity')));
      // نفس الاسم بصيغة أخرى (همزة/مسافات) لا يُضاف مرة ثانية بل يُختار.
      await t.enterText(
        find.byKey(const Key('activity.addField')),
        ' حقن  البلاستيك ',
      );
      await tapVisible(t, find.byKey(const Key('activity.add')));
      expect(crm.activitiesCreated, isEmpty);
      await t.enterText(
        find.byKey(const Key('activity.addField')),
        'تشكيل حراري',
      );
      await tapVisible(t, find.byKey(const Key('activity.add')));
      expect(crm.activitiesCreated.single.name, 'تشكيل حراري');
      expect(
        find.byKey(const Key('activity.option.تشكيل حراري')),
        findsOneWidget,
      );
      await tapVisible(t, find.byKey(const Key('activity.done')));
      expect(
        find.byKey(const Key('register.activity.تشكيل حراري')),
        findsOneWidget,
      );
      await _save(t);
      expect(
        crm.created.single.activityIds,
        containsAll(['ca-injection', 'ca-new-0']),
      );
    });

    testWidgets('activities are restored and edited from the customer card', (
      t,
    ) async {
      final crm = FakeCrmRepository(
        parties: [
          const PartyDetail(
            id: 'party-1',
            version: 2,
            name: 'شركة النور',
            isCustomer: true,
            isSupplier: false,
            phones: [Phone(e164: '+201001234567', isPrimary: true)],
            interests: [],
            products: [],
            canEdit: true,
            customerActivityIds: ['ca-film'],
          ),
        ],
      );
      await pumpCrmApp(t, crm: crm, at: CrmRoutes.party('party-1'));
      expect(find.text('سحب الأفلام'), findsWidgets);
      await tapVisible(t, find.byKey(const Key('profile.edit')));
      expect(find.byKey(const Key('edit.activity.ca-film')), findsOneWidget);
      await _sheet(t, 'edit.activities', 'activity', ['حقن البلاستيك']);
      await tapVisible(t, find.text('حفظ التعديلات'));
      expect(crm.updates.single.activityIds, ['ca-film', 'ca-injection']);
    });

    testWidgets('registry filters customers by activity', (t) async {
      final crm = await pumpCrmApp(t, at: CrmRoutes.registry);
      await tapVisible(t, find.byKey(const Key('registry.activity')));
      await tapVisible(t, find.text('نفخ البلاستيك').last);
      expect(crm.registryQueries.last.activityId, 'ca-blowing');
      expect(crm.registryQueries.last.toQuery()['activityId'], 'ca-blowing');
    });
  });

  testWidgets('01 reports can be narrowed to a customer activity', (t) async {
    final crm = await pumpCrmApp(t, at: CrmRoutes.reports);
    await tapVisible(t, find.byKey(const Key('report.activity')));
    await tapVisible(t, find.byKey(const Key('report.option.ca-film')));
    expect(crm.reportFilters.last.activityId, 'ca-film');
    expect(crm.reportFilters.last.toQuery()['activityId'], 'ca-film');
  });

  group('02 manufacturer reaches the saved grade', () {
    testWidgets('a maker chosen after a grade without maker is saved with it '
        'without touching a grade that already has its maker', (t) async {
      final crm = await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
      await _type(t, 'register.name', 'شركة الشركة');
      await _type(t, 'register.phone', '01009876543');
      // SG-5 بلا شركة، وPP500 لها شركتها.
      await _sheet(t, 'register.gradeSearch', 'grade', [
        'SG-5',
        'PP500 — مصنع تجريبي أ',
      ]);
      await _sheet(t, 'register.maker', 'maker', [
        'مصنع تجريبي ب',
      ], done: false);
      expect(crm.gradesCreated.single, {
        'materialId': 'mat-pvc',
        'manufacturerId': 'man-b',
        'code': 'SG-5',
        'confirmSimilar': true,
      });
      expect(find.byKey(const Key('register.grade.SG-5')), findsOneWidget);
      expect(find.textContaining('SG-5 — مصنع تجريبي ب'), findsOneWidget);
      await _save(t);
      final specs = crm.created.single.specs;
      expect(specs.map((s) => s.gradeId), containsAll(['g-new', 'g-pp500']));
      expect(specs.map((s) => s.gradeId), isNot(contains('g-sg5')));
    });

    testWidgets(
      'an existing grade of the chosen maker is reused, not duplicated',
      (t) async {
        final crm = await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
        await _type(t, 'register.name', 'شركة الشركة');
        await _type(t, 'register.phone', '01009876543');
        // Grade جديد بلا شركة ثم اختيار الشركة: يُنشأ نفس الكود للشركة مرة واحدة.
        await _sheet(t, 'register.materialSearch', 'material', ['PP']);
        await tapVisible(t, find.byKey(const Key('register.gradeSearch')));
        await t.enterText(find.byKey(const Key('grade.addField')), '777X');
        await tapVisible(t, find.byKey(const Key('grade.add')));
        await tapVisible(t, find.byKey(const Key('grade.done')));
        expect(crm.gradesCreated.single['manufacturerId'], isNull);
        await _sheet(t, 'register.maker', 'maker', [
          'مصنع تجريبي ج',
        ], done: false);
        expect(crm.gradesCreated, hasLength(2));
        expect(crm.gradesCreated.last['manufacturerId'], 'man-c');
        await _save(t);
        expect(crm.created.single.specs.single.gradeId, 'g-new-1');
      },
    );
  });

  group('03 employee phone', () {
    test('shared validator: exactly 11 digits starting 010/011/012/015', () {
      for (final ok in [
        '01012345678',
        '01112345678',
        '01212345678',
        '01512345678',
        '+201012345678',
      ]) {
        expect(isEgyptianMobile(ok), isTrue, reason: ok);
        expect(employeeMobileError(ok), isNull, reason: ok);
      }
      for (final bad in [
        '0155566',
        '0101234567',
        '010123456789',
        '01312345678',
        '0223456789',
        '+966501234567',
        '1012345678',
      ]) {
        expect(isEgyptianMobile(bad), isFalse, reason: bad);
        expect(employeeMobileError(bad), isNotNull, reason: bad);
      }
      expect(employeeMobileError(''), isNull); // اختياري
      expect(employeeMobileError('01a12345678'), 'أرقام فقط');
    });

    testWidgets('an incomplete number is red, never green, and blocks saving', (
      t,
    ) async {
      final crm = await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
      await _required(t);
      await _type(t, 'register.employee.0.name', 'مكرم');
      await _type(t, 'register.employee.0.phone', '0155566');
      expect(_border(t, 'register.employee.0.phone'), AppColors.error);
      expect(_saveEnabled(t), isFalse);
      expect(find.textContaining('رقم موظف صحيح'), findsOneWidget);
      // أرقام فقط: الحروف لا تُكتب، والصفر الأول يبقى.
      await _type(t, 'register.employee.0.phone', '01a55-5 66');
      expect(
        t
            .widget<TextField>(
              find.byKey(const Key('register.employee.0.phone')),
            )
            .controller!
            .text,
        '0155566',
      );
      await _type(t, 'register.employee.0.phone', '01555667788');
      expect(_saveEnabled(t), isTrue);
      await _type(t, 'register.employee.0.phone', '');
      expect(_saveEnabled(t), isTrue); // فارغ مسموح
      await _type(t, 'register.employee.0.phone', '01555667788');
      await _save(t);
      expect(crm.contactsAdded.single.mobile, '01555667788');
    });

    testWidgets('the employee field turns green only for a complete number', (
      t,
    ) async {
      await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
      await _type(t, 'register.employee.0.phone', '0155566');
      expect(_border(t, 'register.employee.0.phone'), AppColors.error);
      await _type(t, 'register.employee.0.phone', '0155566778');
      expect(_border(t, 'register.employee.0.phone'), AppColors.error);
      await _type(t, 'register.employee.0.phone', '01555667788');
      expect(_border(t, 'register.employee.0.phone'), AppColors.greenDark);
      await _type(t, 'register.phone', '01555667788');
      expect(_border(t, 'register.phone'), AppColors.greenDark);
    });

    testWidgets('a customer employee added from the card needs a mobile', (
      t,
    ) async {
      final crm = await pumpCrmApp(t, at: CrmRoutes.party('party-1'));
      await tapVisible(t, find.byKey(const Key('tab.2')));
      await tapVisible(t, find.byKey(const Key('contact.add')));
      await t.enterText(find.byKey(const Key('contact.name')), 'موظف');
      await t.enterText(find.byKey(const Key('contact.mobile')), '0223456789');
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const Key('contact.save')));
      expect(crm.contactsAdded, isEmpty);
      expect(find.textContaining('11 رقمًا'), findsWidgets);
      await t.enterText(find.byKey(const Key('contact.mobile')), '01012345678');
      await tapVisible(t, find.byKey(const Key('contact.save')));
      expect(crm.contactsAdded.single.mobile, '01012345678');
    });

    testWidgets('an old invalid employee number is kept and flagged', (
      t,
    ) async {
      final crm = FakeCrmRepository()
        ..contactList['party-1'] = [
          const PartyContact(id: 'old', name: 'قديم', mobile: '+20225551234'),
        ];
      await pumpCrmApp(t, crm: crm, at: CrmRoutes.party('party-1'));
      await tapVisible(t, find.byKey(const Key('tab.2')));
      expect(find.byKey(const Key('contact.invalidMobile')), findsOneWidget);
      expect(crm.contactsUpdated, isEmpty);
      expect(crm.contactsRemoved, isEmpty);
    });
  });

  group('06 registry logo', () {
    testWidgets('the saved company logo is shown; others keep the icon', (
      t,
    ) async {
      final crm = FakeCrmRepository(
        parties: [
          sampleCustomer(),
          const PartyDetail(
            id: 'party-3',
            version: 1,
            name: 'عميل بلا صورة',
            isCustomer: true,
            isSupplier: false,
            phones: [Phone(e164: '+201001110000', isPrimary: true)],
            interests: [],
            products: [],
            canEdit: true,
          ),
        ],
      )..registryLogos['party-1'] = 'logo-1';
      await pumpCrmApp(t, crm: crm, at: CrmRoutes.registry);
      expect(find.byKey(const Key('registry.logo.logo-1')), findsOneWidget);
      expect(find.byIcon(Icons.factory_rounded), findsOneWidget);
      // يُنهي ذاكرة الشعار المؤقتة قبل نهاية الاختبار.
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(minutes: 11));
    });
  });

  group('07 share message', () {
    test('approved format with bold headings and only chosen data', () {
      final text = buildContactShareText(
        name: 'شركة النور',
        phone: '01001234567',
        employees: const [
          ('مكرم الدالي', 'مدير مشتريات', '01012345678'),
          ('موظف قديم', null, '0155566'),
        ],
        email: 'a@b.co',
        address: 'المنطقة الصناعية - القاهرة',
        locations: const [
          ShareLocation(
            kind: LocationKind.headOffice,
            title: 'المقر الرئيسي',
            address: 'المنطقة الصناعية - القاهرة',
          ),
          ShareLocation(
            kind: LocationKind.factory,
            title: 'المصنع',
            address: 'العاشر من رمضان',
            link: 'https://maps.google.com/?q=30.2950,31.7420',
          ),
        ],
      );
      expect(
        text,
        '🏢 *بيانات العميل*\n'
        '━━━━━━━━━━━━\n\n'
        '*👤 اسم العميل*\nشركة النور\n\n'
        '*📞 رقم الهاتف*\n01001234567\n\n'
        '*👨‍💼 جهة الاتصال*\nمكرم الدالي\nالوظيفة: مدير مشتريات\n📱 01012345678\n\n'
        '*👨‍💼 جهة الاتصال*\nموظف قديم\n⚠️ رقم الموظف غير صالح (يحتاج تصحيح)\n\n'
        '*✉️ البريد الإلكتروني*\na@b.co\n\n'
        '*📍 العناوين*\n\n'
        '*🏢 المقر الرئيسي*\nالمنطقة الصناعية - القاهرة\n\n'
        '*🏭 المصنع*\nالعاشر من رمضان\n🗺️ الموقع على الخريطة\nhttps://maps.google.com/?q=30.2950,31.7420\n\n'
        '━━━━━━━━━━━━',
      );
      // العنوان العام لم يتكرر لأنه مطابق لعنوان المقر.
      expect('المنطقة الصناعية - القاهرة'.allMatches(text), hasLength(1));
      expect(text, isNot(contains('0155566')));
    });

    test('unselected fields and sites are not sent', () {
      final text = buildContactShareText(
        name: 'شركة النور',
        locations: const [
          ShareLocation(kind: LocationKind.warehouse, title: 'المخزن'),
        ],
      );
      expect(text, contains('*🏬 المخزن*'));
      expect(text, isNot(contains('رقم الهاتف')));
      expect(text, isNot(contains('البريد')));
      expect(buildContactShareText(name: null), isEmpty);
    });

    testWidgets('share from the card respects chosen sites and warns', (
      t,
    ) async {
      final crm = FakeCrmRepository()
        ..contactList['party-1'] = [
          const PartyContact(id: 'old', name: 'قديم', mobile: '+20225551234'),
        ];
      await pumpCrmApp(t, crm: crm, at: CrmRoutes.party('party-1'));
      await tapVisible(t, find.byKey(const Key('profile.shareContact')));
      expect(find.byKey(const Key('share.invalidEmployee')), findsOneWidget);
      await tapVisible(t, find.byKey(const Key('share.site.0')));
      await tapVisible(t, find.byKey(const Key('share.send')));
      final text = crm.shared.single;
      expect(text, startsWith('🏢 *بيانات العميل*'));
      expect(text, isNot(contains('maps.google.com'))); // الموقع أُلغي اختياره
      expect(text, isNot(contains('225551234')));
      expect(crm.interactionsSent, isEmpty); // لا تسجيل نشاط بعد المشاركة
    });
  });

  group('08 governorate then city', () {
    testWidgets('governorate comes first and the city list follows it', (
      t,
    ) async {
      await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
      await t.ensureVisible(find.byKey(const Key('register.governorate')));
      await t.pumpAndSettle();
      final gov = t.getRect(find.byKey(const Key('register.governorate')));
      final city = t.getRect(find.byKey(const Key('register.city')));
      // RTL: الأول على اليمين (أو أعلى عند الضيق).
      expect(gov.left > city.left || gov.top < city.top, isTrue);

      // المدينة قبل المحافظة: يُطلب اختيار المحافظة أولًا.
      await tapVisible(t, find.byKey(const Key('register.city')));
      expect(find.text('اختر المحافظة أولًا'), findsOneWidget);
      expect(find.byKey(const Key('city.search')), findsNothing);
    });

    testWidgets('changing governorate keeps a compatible city and clears '
        'an incompatible one', (t) async {
      await pumpCrmApp(t, at: CrmRoutes.newCustomer, user: _rep);
      await _sheet(t, 'register.governorate', 'governorate', [
        'القاهرة',
      ], done: false);
      await tapVisible(t, find.byKey(const Key('register.city')));
      final cairoCity = t
          .widgetList<ListTile>(find.byType(ListTile))
          .map((w) => (w.key! as ValueKey<String>).value)
          .firstWhere((k) => k.startsWith('city.option.'))
          .substring('city.option.'.length);
      await tapVisible(t, find.byKey(Key('city.option.$cairoCity')));
      expect(find.text(cairoCity), findsOneWidget);

      // نفس المحافظة مرة أخرى: المدينة تبقى.
      await _sheet(t, 'register.governorate', 'governorate', [
        'القاهرة',
      ], done: false);
      expect(find.text(cairoCity), findsOneWidget);

      // محافظة أخرى لا تضم المدينة: تُمسح ويُطلب اختيار مدينة جديدة.
      await _sheet(t, 'register.governorate', 'governorate', [
        'الجيزة',
      ], done: false);
      expect(find.text(cairoCity), findsNothing);
      expect(
        find.text('اختر المنطقة / المدينة للمحافظة الجديدة'),
        findsOneWidget,
      );
    });
  });
}
