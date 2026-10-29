import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

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

  testWidgets('an order uses another saved location and the driver message '
      'is shared manually', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newOrder('party-1'));
    expect(find.text('المصنع — البوابة 2 (افتراضي)'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('record.location')));
    await tester.tap(find.byKey(const Key('pickLocation.loc-2')));
    await tester.pumpAndSettle();
    expect(find.text('موقع التسليم'), findsWidgets);

    await tester.tap(find.byKey(const Key('line.0.material')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spec.material.PP')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('spec.grade.PP500')));
    await tapVisible(tester, find.byKey(const Key('spec.done')));
    await tester.enterText(find.byKey(const Key('line.0.quantity')), '3');
    await tapVisible(tester, find.byKey(const Key('record.driver')));
    expect(crm.shared.single, contains('PP · مصنع تجريبي أ · PP500'));
    expect(crm.shared.single, contains('https://maps.app.goo.gl/AbCdEf123'));

    await tapVisible(tester, find.byKey(const Key('crm.save')));
    expect(crm.ordersSent.single['locationId'], 'loc-2');
  });
}
