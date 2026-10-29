import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';
import 'package:qadisiyah/features/crm/presentation/party_profile_screen.dart';
import 'package:qadisiyah/features/crm/presentation/registry_screen.dart';

import 'crm_flow_test.dart' show pumpCrmApp;

void main() {
  testWidgets('the home search tile opens the registry with customers', (
    tester,
  ) async {
    await pumpCrmApp(tester);
    await tester.tap(find.byKey(const Key('home.search')));
    await tester.pumpAndSettle();

    expect(find.byType(RegistryScreen), findsOneWidget);
    expect(find.text('شركة النور للصناعات البلاستيكية'), findsOneWidget);
    expect(find.text('شركة الصفوة لمواد البلاستيك'), findsNothing);
    expect(find.text('آخر طلب: 15 أكتوبر 2026'), findsOneWidget);
    expect(find.byKey(const Key('registry.add')), findsOneWidget);
  });

  testWidgets('tapping a card opens the original profile', (tester) async {
    await pumpCrmApp(tester, at: CrmRoutes.registry);
    await tester.tap(find.byKey(const Key('tab.1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('registry.item.party-2')));
    await tester.pumpAndSettle();

    expect(find.byType(PartyProfileScreen), findsOneWidget);
    expect(find.text('بيانات المورد'), findsOneWidget);
    // زر التعديل ظاهر في رأس الملف.
    expect(find.byKey(const Key('profile.menu')), findsOneWidget);
  });

  testWidgets('search and material filter go to the server and open matches '
      'are labelled', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.registry);
    await tester.enterText(find.byKey(const Key('registry.search')), 'النور');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(crm.registryQueries.last.query, 'النور');

    await tester.tap(find.byKey(const Key('registry.material')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('registry.option.PP')));
    await tester.pumpAndSettle();
    expect(crm.registryQueries.last.materialId, 'mat-pp');
    expect(find.text('مطابقة مفتوحة: يقبل أي شركة'), findsOneWidget);
    expect(find.byKey(const Key('registry.grade')), findsOneWidget);
  });

  testWidgets('favorites toggle from the list and the profile', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.registry);
    await tester.tap(find.byKey(const Key('registry.favorite.party-1')));
    await tester.pumpAndSettle();
    expect(crm.favorites, [('party-1', true)]);

    await tester.tap(find.byKey(const Key('registry.item.party-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile.favorite')));
    await tester.pumpAndSettle();
    expect(crm.favorites.last, ('party-1', true));
  });

  testWidgets('profile details show the change history', (tester) async {
    await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
    await tester.tap(find.byKey(const Key('tab.3')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('عدّل: الاسم'), 200);
    expect(find.textContaining('أنشأ السجل'), findsOneWidget);
  });
}
