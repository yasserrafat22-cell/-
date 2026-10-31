import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

/// تبويب «الموظفين» في بطاقة العميل.
Future<void> _details(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tab.2')));
  await tester.pumpAndSettle();
}

void main() {
  group('company contacts', () {
    testWidgets('a contact is added with a validated mobile', (tester) async {
      final crm = FakeCrmRepository(
        parties: [sampleCustomer(canEdit: false, canAdd: true)],
      );
      await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-1'));
      await _details(tester);
      await tapVisible(tester, find.byKey(const Key('contact.add')));
      await tester.enterText(find.byKey(const Key('contact.name')), 'م. سامي');
      await tester.enterText(find.byKey(const Key('contact.job')), 'مشتريات');
      await tester.enterText(
        find.byKey(const Key('contact.mobile')),
        '0131234567',
      );
      await tester.tap(find.byKey(const Key('contact.save')));
      await tester.pumpAndSettle();
      expect(crm.contactsAdded, isEmpty);
      expect(find.byKey(const Key('phone.invalid')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('contact.mobile')),
        '01112345678',
      );
      await tester.tap(find.byKey(const Key('contact.save')));
      await tester.pumpAndSettle();
      final added = crm.contactsAdded.single;
      expect(added.name, 'م. سامي');
      expect(added.jobTitle, 'مشتريات');
      expect(added.isPrimary, isTrue);
      // تمت الإضافة؛ لا حذف لغير المدير.
      expect(find.byKey(Key('contact.call.${added.id}')), findsOneWidget);
      expect(find.byKey(Key('contact.delete.${added.id}')), findsNothing);
    });

    testWidgets('the admin can delete a contact', (tester) async {
      final crm = FakeCrmRepository()
        ..contactList['party-1'] = [
          const PartyContact(id: 'c-1', name: 'أ. منى', isPrimary: true),
        ];
      await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-1'));
      await _details(tester);
      await tapVisible(tester, find.byKey(const Key('contact.delete.c-1')));
      await tester.tap(find.byKey(const Key('contact.confirmDelete')));
      await tester.pumpAndSettle();
      expect(crm.contactsRemoved, ['c-1']);
    });
  });

  testWidgets('the + circle adds the first logo', (tester) async {
    final crm = FakeCrmRepository(
      parties: [sampleCustomer(canEdit: false, canAdd: true)],
    );
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-1'));
    expect(find.byKey(const Key('logo.add')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile.logo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logo.gallery')));
    await tester.pumpAndSettle();
    expect(crm.uploads.single['kind'], AttachmentKind.logo);
  });

  testWidgets('a similar record asks before saving and then saves', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..createErrorOnce = true
      ..createError = const ApiException(
        'party.similar',
        'يوجد سجل مشابه. تأكد أنه ليس نفس الشركة قبل الحفظ',
        data: [
          {
            'partyId': 'party-1',
            'name': 'شركة النور',
            'reasons': ['name'],
          },
        ],
      );
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.newSupplier);
    await tester.enterText(find.byKey(const Key('party.name')), 'مصنع النور');
    await tester.enterText(find.byKey(const Key('party.phone')), '01009876543');
    await tester.tap(find.byKey(const Key('activity.act-importer')));
    await tapVisible(tester, find.byKey(const Key('crm.save')));

    expect(find.byKey(const Key('similar.party-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('similar.saveAnyway')));
    await tester.pumpAndSettle();
    expect(crm.createAttempts.map((p) => p.confirmSimilar), [false, true]);
    expect(crm.created.single.toJson()['confirmSimilar'], isTrue);
  });

  testWidgets('favorites show whether each entry is a customer or supplier', (
    tester,
  ) async {
    final crm = FakeCrmRepository(
      parties: [sampleCustomer(), sampleSupplier(isFavorite: true)],
    );
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.registry);
    await tester.tap(find.byKey(const Key('tab.2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('registry.badge.supplier')), findsOneWidget);
    expect(find.byKey(const Key('registry.badge.customer')), findsNothing);
  });

  testWidgets('a grade datasheet is added from the material picker', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.newSupplier);
    await tapVisible(tester, find.byKey(const Key('chips.add')));
    await tester.tap(find.byKey(const Key('spec.material.PP')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('spec.grade.PP500')));
    await tapVisible(tester, find.byKey(const Key('gradeFile.sheet.g-pp500')));
    expect(crm.gradeFilesUploaded.single, (
      'g-pp500',
      'dataSheet',
      'sheet.pdf',
    ));
  });
}
