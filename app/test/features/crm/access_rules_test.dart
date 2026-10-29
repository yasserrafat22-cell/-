import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/presentation/contact_launcher.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

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
    'records.assign',
    'customers.create',
  },
  mustChangePassword: false,
);

Future<void> _fillCustomer(
  WidgetTester tester, {
  String phone = '01009876543',
}) async {
  await tester.enterText(find.byKey(const Key('party.name')), 'شركة الأمل');
  await tester.enterText(find.byKey(const Key('party.phone')), phone);
  await tester.tap(find.byKey(const Key('activity.act-factory')));
  await tester.pumpAndSettle();
}

const _admin = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000010',
  username: 'boss',
  displayName: 'المدير العام',
  roles: ['system_admin'],
  permissions: {
    'customers.view_all',
    'suppliers.view_all',
    'records.manage',
    'records.assign',
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

void main() {
  testWidgets('a representative has no suppliers tab and no deleted tab', (
    tester,
  ) async {
    await pumpCrmApp(tester, at: CrmRoutes.registry, user: _rep);
    expect(find.text('الموردين'), findsNothing);
    expect(find.text('المحذوفات'), findsNothing);
    expect(find.text('المفضلة'), findsOneWidget);
  });

  testWidgets('the admin restores a deleted record from the registry', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.registry, user: _admin);
    await tester.tap(find.byKey(const Key('tab.3')));
    await tester.pumpAndSettle();
    expect(crm.registryQueries.last.deleted, isTrue);
    await tester.tap(find.byKey(const Key('registry.item.party-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('registry.confirmRestore')));
    await tester.pumpAndSettle();
    expect(crm.restored, ['party-1']);
  });

  group('phone rules match the server', () {
    test('egyptian mobile, landline and international numbers', () {
      expect(ContactLauncher.phoneError('01012345678'), isNull);
      expect(ContactLauncher.phoneError('01512345678'), isNull);
      expect(ContactLauncher.phoneError('0223456789'), isNull);
      expect(ContactLauncher.phoneError('+966501234567'), isNull);
      expect(ContactLauncher.phoneError('0101234567'), isNotNull);
      expect(ContactLauncher.phoneError('01312345678'), isNotNull);
      expect(ContactLauncher.phoneError(''), 'رقم الهاتف مطلوب');
    });

    testWidgets('the phone field turns red then green while typing', (
      tester,
    ) async {
      await pumpCrmApp(tester, at: CrmRoutes.newCustomer);
      await tester.enterText(find.byKey(const Key('party.phone')), '0101234');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('phone.invalid')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('party.phone')),
        '01012345678',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('phone.valid')), findsOneWidget);
    });
  });

  testWidgets('office staff choose the responsible representative and date', (
    tester,
  ) async {
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.newCustomer,
      user: _secretary,
    );
    expect(find.byKey(const Key('party.fixedOwner')), findsNothing);
    expect(find.byKey(const Key('party.representative')), findsOneWidget);
    expect(find.byKey(const Key('party.recordDate')), findsOneWidget);
    await _fillCustomer(tester);
    await tapVisible(tester, find.byKey(const Key('crm.save')));
    expect(crm.created.single.representativeId, isNotNull);
  });

  testWidgets(
    'a record saved but hidden from its creator closes with success',
    (tester) async {
      final crm = FakeCrmRepository()..createHidden = true;
      await pumpCrmApp(tester, crm: crm, at: CrmRoutes.newCustomer);
      await _fillCustomer(tester);
      await tapVisible(tester, find.byKey(const Key('crm.save')));
      expect(crm.created, hasLength(1));
      expect(find.text('تم الحفظ وأُرسل للإدارة'), findsOneWidget);
      expect(find.byKey(const Key('party.name')), findsNothing);
    },
  );

  testWidgets('a duplicate of a hidden record shows only a generic message', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..createError = const ApiException(
        'party.duplicate_phone_hidden',
        'هذا الرقم مسجل بالفعل. تواصل مع الإدارة',
      );
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.newCustomer);
    await _fillCustomer(tester);
    await tapVisible(tester, find.byKey(const Key('crm.save')));
    expect(
      find.text('هذا الرقم مسجل بالفعل. تواصل مع الإدارة'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('duplicate.open')), findsNothing);
  });

  testWidgets('a representative adds to a saved record but cannot edit it', (
    tester,
  ) async {
    final crm = FakeCrmRepository(
      parties: [sampleCustomer(canEdit: false, canAdd: true)],
    );
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-1'));
    expect(find.byKey(const Key('profile.newRecord')), findsOneWidget);
    expect(find.byKey(const Key('profile.menu')), findsNothing);
    await tester.tap(find.byKey(const Key('tab.3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile.addMaterial')), findsOneWidget);
    expect(find.byKey(const Key('profile.edit')), findsNothing);
    expect(find.byKey(const Key('profile.delete')), findsNothing);
  });

  testWidgets('the admin deletes a record after confirming', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
    await tester.tap(find.byKey(const Key('tab.3')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('profile.delete')));
    await tapVisible(tester, find.byKey(const Key('party.confirmDelete')));
    expect(crm.deleted, ['party-1']);
  });

  testWidgets('a department manager reassigns a record to another rep', (
    tester,
  ) async {
    const manager = AuthUser(
      id: '0192f0c0-0000-7000-8000-000000000012',
      username: 'sales',
      displayName: 'مدير المبيعات',
      roles: ['sales_manager'],
      permissions: {'customers.view_all', 'team.assign'},
      mustChangePassword: false,
    );
    final crm = FakeCrmRepository(
      parties: [sampleCustomer(canEdit: false, canAdd: true)],
    );
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.party('party-1'),
      user: manager,
    );
    await tester.tap(find.byKey(const Key('tab.3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile.edit')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('profile.assign')));
    await tester.tap(find.byKey(const Key('assign.rep-other')));
    await tester.pumpAndSettle();
    expect(crm.assigned, [('party-1', 'rep-other')]);
  });

  testWidgets('representatives have no reassignment action', (tester) async {
    final crm = FakeCrmRepository(
      parties: [sampleCustomer(canEdit: false, canAdd: true)],
    );
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.party('party-1'),
      user: _rep,
    );
    await tester.tap(find.byKey(const Key('tab.3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile.assign')), findsNothing);
  });
}
