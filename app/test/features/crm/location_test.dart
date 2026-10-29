import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

Future<void> _openDetails(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tab.3')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('details list locations and share one as text', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
    await _openDetails(tester);

    expect(find.text('المصنع — البوابة 2'), findsOneWidget);
    expect(find.text('افتراضي'), findsOneWidget);
    expect(find.textContaining('رابط بدون إحداثيات'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('location.share.0')));
    expect(
      crm.shared.single,
      contains('https://maps.google.com/?q=30.2950,31.7420'),
    );
    expect(crm.shared.single, contains('ملاحظات الوصول: التحميل حتى 4 م'));
  });

  testWidgets('a pasted Google Maps link fills the coordinates', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
    await _openDetails(tester);
    await tapVisible(tester, find.byKey(const Key('location.add')));
    await tester.tap(find.byKey(const Key('location.kind.warehouse')));
    await tester.enterText(
      find.byKey(const Key('location.url')),
      'https://www.google.com/maps/place/x/data=!3d30.0444!4d31.2357',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('30.04440 , 31.23570'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('crm.save')));

    final (partyId, draft) = crm.locationsCreated.single;
    expect(partyId, 'party-1');
    expect(draft.kind, LocationKind.warehouse);
    expect((draft.latitude, draft.longitude), (30.0444, 31.2357));
  });

  testWidgets('a short link without coordinates is saved as is, other sites '
      'are rejected', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
    await _openDetails(tester);
    await tapVisible(tester, find.byKey(const Key('location.add')));
    await tester.enterText(
      find.byKey(const Key('location.url')),
      'https://example.com/place',
    );
    await tapVisible(tester, find.byKey(const Key('crm.save')));
    expect(find.text('الرابط يجب أن يكون رابط Google Maps'), findsOneWidget);
    expect(crm.locationsCreated, isEmpty);

    await tester.enterText(
      find.byKey(const Key('location.url')),
      'https://maps.app.goo.gl/XyZ987',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('سيُحفظ الرابط كما هو'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('crm.save')));
    final draft = crm.locationsCreated.single.$2;
    expect(draft.mapsUrl, 'https://maps.app.goo.gl/XyZ987');
    expect(draft.latitude, isNull);
  });

  testWidgets('the phone location is used after permission', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
    await _openDetails(tester);
    await tapVisible(tester, find.byKey(const Key('location.add')));
    await tapVisible(tester, find.byKey(const Key('location.gps')));
    await tapVisible(tester, find.byKey(const Key('crm.save')));
    final draft = crm.locationsCreated.single.$2;
    expect((draft.latitude, draft.longitude), (30.0444, 31.2357));
  });

  testWidgets('an order uses the chosen location; the driver message is '
      'previewed, edited and shared manually', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newOrder('party-1'));
    expect(find.text('المصنع — البوابة 2 (افتراضي)'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('record.location')));
    await tester.tap(find.byKey(const Key('pickLocation.loc-2')));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const Key('record.driver')));
    final preview = tester
        .widget<TextField>(find.byKey(const Key('driver.text')))
        .controller!
        .text;
    expect(preview, startsWith('🚚 بيانات موقع التسليم'));
    expect(preview, contains('🏢 العميل: شركة النور للصناعات البلاستيكية'));
    expect(preview, contains('📦 الموقع: موقع التسليم'));
    expect(
      preview,
      contains('🗺️ رابط الخريطة:\nhttps://maps.app.goo.gl/AbCdEf123'),
    );
    // الحقول غير المتوفرة لا تظهر.
    expect(preview, isNot(contains('تعليمات الوصول')));
    expect(crm.shared, isEmpty);

    await tester.enterText(
      find.byKey(const Key('driver.text')),
      '$preview\n\nاتصل قبل الوصول',
    );
    await tester.tap(find.byKey(const Key('driver.share')));
    await tester.pumpAndSettle();
    expect(crm.shared.single, endsWith('اتصل قبل الوصول'));

    await tapVisible(tester, find.byKey(const Key('crm.save')));
    expect(find.byKey(const Key('record.error')), findsOneWidget);
    expect(crm.ordersSent, isEmpty);
  });

  testWidgets('cancelling the preview shares nothing', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newOrder('party-1'));
    await tapVisible(tester, find.byKey(const Key('record.driver')));
    await tester.tap(find.byKey(const Key('driver.cancel')));
    await tester.pumpAndSettle();
    expect(crm.shared, isEmpty);
  });

  testWidgets('a supply sends the supplier loading location', (tester) async {
    final crm = FakeCrmRepository()
      ..locationLists['party-2'] = const [
        PartyLocation(
          id: 'loc-s',
          partyId: 'party-2',
          kind: LocationKind.warehouse,
          label: 'مخزن تجريبي',
          latitude: 30.1,
          longitude: 31.2,
          accessNotes: 'البوابة الخلفية',
          isDefault: true,
        ),
      ];
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.newSupply('party-2'));
    await tapVisible(tester, find.byKey(const Key('record.driver')));
    await tester.tap(find.byKey(const Key('driver.share')));
    await tester.pumpAndSettle();

    expect(crm.shared.single, '''🚚 بيانات موقع التحميل

🏭 المورد: شركة الصفوة لمواد البلاستيك

📦 الموقع: المخزن — مخزن تجريبي

🗺️ رابط الخريطة:
https://www.google.com/maps/search/?api=1&query=30.1,31.2

📝 تعليمات الوصول:
البوابة الخلفية''');
  });

  test('no map link is invented from an address alone', () {
    const place = PartyLocation(
      id: 'x',
      partyId: 'p',
      kind: LocationKind.delivery,
      addressLine: 'عنوان فقط',
    );
    final text = place.driverMessage(partyName: 'عميل', loading: false);
    expect(text, contains('📍 العنوان: عنوان فقط'));
    expect(text, isNot(contains('رابط الخريطة')));
  });
}
