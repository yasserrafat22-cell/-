import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';
import 'package:qadisiyah/features/crm/presentation/party_profile_screen.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

const _pp500 = MaterialSpec(
  materialId: 'mat-pp',
  materialCode: 'PP',
  gradeId: 'g-pp500',
  gradeCode: 'PP500',
  manufacturerName: 'سابك',
  precision: SpecPrecision.exact,
);

const _results = SearchResults(
  suggestions: [
    SearchSuggestion(kind: 'manufacturer', id: 'man-a', label: 'سابك'),
    SearchSuggestion(
      kind: 'grade',
      id: 'g-pp500',
      label: 'PP · PP500',
      materialId: 'mat-pp',
      manufacturerId: 'man-a',
    ),
  ],
  suppliers: [
    SearchCard(
      partyId: 'party-2',
      name: 'شركة الصفوة لمواد البلاستيك',
      isCustomer: false,
      isSupplier: true,
      phone: '+201112223334',
      specs: [_pp500],
      reasons: ['يوفّر PP · سابك · PP500'],
      exact: true,
    ),
  ],
  customers: [
    SearchCard(
      partyId: 'party-1',
      name: 'شركة النور للصناعات البلاستيكية',
      isCustomer: true,
      isSupplier: false,
      phone: '+201001234567',
      contactName: 'م. سامي',
      email: 'info@alnour.example',
      specs: [_pp500],
      reasons: ['يحتاج PP · سابك · PP500'],
      exact: true,
    ),
    SearchCard(
      partyId: 'party-9',
      name: 'مصنع الأمل',
      isCustomer: true,
      isSupplier: false,
      reasons: ['يقبل أي شركة لخامة PP'],
    ),
  ],
);

const _rep = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000011',
  username: 'rep',
  displayName: 'مندوب',
  roles: ['representative'],
  permissions: {'customers.view', 'customers.create'},
  mustChangePassword: false,
);

const _secretary = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000009',
  username: 'office',
  displayName: 'السكرتارية',
  roles: ['secretary'],
  permissions: {'customers.view_all', 'suppliers.view_all', 'reports.export'},
  mustChangePassword: false,
);

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('search.field')), text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('results appear while typing: suppliers first, then customers '
      'below them', (tester) async {
    final crm = FakeCrmRepository()..searchResults = _results;
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.search);
    await _type(tester, 'سابك');
    expect(crm.searches.last.text, 'سابك');

    final supplier = tester.getTopLeft(
      find.byKey(const Key('search.card.party-2')),
    );
    final customer = tester.getTopLeft(
      find.byKey(const Key('search.card.party-1')),
    );
    expect(supplier.dy, lessThan(customer.dy));
    // تحت بعض وليس في عمودين.
    expect(supplier.dx, customer.dx);
    expect(find.text('الموردون (1)'), findsOneWidget);
    expect(find.text('العملاء المناسبون (2)'), findsOneWidget);
    expect(find.byKey(const Key('search.call.party-1')), findsOneWidget);
    expect(find.byKey(const Key('search.whatsapp.party-1')), findsOneWidget);
    expect(find.byKey(const Key('search.email.party-1')), findsOneWidget);
    expect(find.textContaining('بديل محتمل'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search.suggest.grade.g-pp500')));
    await tester.pumpAndSettle();
    expect(crm.searches.last.gradeId, 'g-pp500');
    expect(find.byKey(const Key('search.picked')), findsOneWidget);

    await tapVisible(tester, find.text('شركة النور للصناعات البلاستيكية'));
    expect(find.byType(PartyProfileScreen), findsOneWidget);
  });

  testWidgets('a card is shared after a preview with the chosen fields', (
    tester,
  ) async {
    final crm = FakeCrmRepository()..searchResults = _results;
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.search, user: _rep);
    await _type(tester, 'النور');
    // المندوب: لا تحديد ولا تصدير جماعي.
    expect(find.byKey(const Key('search.select')), findsNothing);
    expect(find.byKey(const Key('search.excel')), findsNothing);
    expect(find.byKey(const Key('search.print')), findsNothing);

    await tapVisible(tester, find.byKey(const Key('search.shareCard.party-1')));
    await tester.tap(find.byKey(const Key('share.fields.name')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('share.preview')),
        matching: find.textContaining('01001234567'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('share.send')));
    await tester.pumpAndSettle();
    expect(crm.shareRequests, [('card', 1)]);
    expect(crm.shared.single, 'شركة النور للصناعات البلاستيكية (عميل)');
  });

  testWidgets('office staff select results, then share, print, PDF and Excel', (
    tester,
  ) async {
    final docs = FakeDocumentServices();
    final crm = FakeCrmRepository()..searchResults = _results;
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.search,
      user: _secretary,
      documents: docs,
    );
    await _type(tester, 'PP500');
    await tester.tap(find.byKey(const Key('search.select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.card.party-2')));
    await tester.tap(find.byKey(const Key('search.card.party-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search.share')));
    await tester.pumpAndSettle();
    expect(crm.shareRequests.last, ('selection', 2));
    final text = crm.shared.last;
    expect(text.indexOf('الصفوة'), lessThan(text.indexOf('النور')));
    expect(text, isNot(contains('مصنع الأمل')));

    await tester.tap(find.byKey(const Key('search.print')));
    await tester.pumpAndSettle();
    expect(docs.printed.single.sections.map((s) => s.$2.length), [1, 1]);

    await tester.tap(find.byKey(const Key('search.pdf')));
    await tester.pumpAndSettle();
    expect(docs.pdfs.single.title, contains('PP500'));
    expect(crm.shared.last, endsWith('search.pdf'));

    await tester.tap(find.byKey(const Key('search.excel')));
    await tester.pumpAndSettle();
    expect(crm.searchExports.single, unorderedEquals(['party-1', 'party-2']));
  });
}
