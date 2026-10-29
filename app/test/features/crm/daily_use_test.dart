import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

void main() {
  testWidgets('a previous order line is repeated with its spec, quantity and '
      'unit', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newOrder('party-1'));
    await tapVisible(tester, find.byKey(const Key('record.repeatLine')));
    expect(find.text('3 طن'), findsOneWidget);
    await tester.tap(find.byKey(const Key('repeat.0')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('crm.save')));

    expect(crm.ordersSent.single['lines'], [
      {
        'materialId': 'mat-pvc',
        'gradeId': 'g-sg5',
        'originCountryId': null,
        'openSpec': false,
        'quantity': 3.0,
        'unitId': 'unit-ton',
      },
    ]);
  });

  testWidgets('contact details are shared as text with the default location', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
    await tester.tap(find.byKey(const Key('tab.3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('details.phone.0')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('profile.shareContact')));

    final text = crm.shared.single;
    expect(text, startsWith('شركة النور للصناعات البلاستيكية'));
    expect(text, contains('هاتف: 01001234567'));
    expect(
      text,
      contains('الموقع: https://maps.google.com/?q=30.2950,31.7420'),
    );
  });
}
