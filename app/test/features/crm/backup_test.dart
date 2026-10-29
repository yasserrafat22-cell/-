import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

const _admin = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000010',
  username: 'boss',
  displayName: 'المدير العام',
  roles: ['system_admin'],
  permissions: {
    'customers.view_all',
    'suppliers.view_all',
    'records.manage',
    'backup.manage',
  },
  mustChangePassword: false,
);

void main() {
  testWidgets('the admin saves a full backup protected by its own password', (
    tester,
  ) async {
    final crm = FakeCrmRepository();
    await pumpCrmApp(tester, crm: crm, user: _admin);
    await tester.tap(find.byKey(const Key('backup.full')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('backup.password')), 'short');
    await tester.enterText(
      find.byKey(const Key('backup.passwordAgain')),
      'short',
    );
    await tester.tap(find.byKey(const Key('backup.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('على الأقل 10 أحرف'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('backup.password')),
      'Long-Secret-2026',
    );
    await tester.enterText(
      find.byKey(const Key('backup.passwordAgain')),
      'Long-Secret-2027',
    );
    await tester.tap(find.byKey(const Key('backup.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('backup.passwordAgain')),
      'Long-Secret-2026',
    );
    await tester.tap(find.byKey(const Key('backup.confirm')));
    await tester.pumpAndSettle();
    expect(crm.backupPasswords, ['Long-Secret-2026']);
    expect(crm.shared.single, endsWith('.qbk'));
  });

  testWidgets('other users have no full backup button', (tester) async {
    await pumpCrmApp(tester);
    expect(find.byKey(const Key('backup.full')), findsNothing);
    expect(find.byKey(const Key('sync.now')), findsOneWidget);
  });

  testWidgets('the registry exports the current list to Excel', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.registry);
    await tester.tap(find.byKey(const Key('tab.1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('registry.export')));
    await tester.pumpAndSettle();
    expect(crm.exported, ['supplier']);
    expect(crm.shared.single, endsWith('.xlsx'));
  });

  testWidgets('device data can be saved from the sync screen', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.sync);
    await tapVisible(tester, find.byKey(const Key('device.backup')));
    await tester.enterText(
      find.byKey(const Key('backup.password')),
      'Device-Secret-1',
    );
    await tester.enterText(
      find.byKey(const Key('backup.passwordAgain')),
      'Device-Secret-1',
    );
    await tester.tap(find.byKey(const Key('backup.confirm')));
    await tester.pumpAndSettle();
    expect(crm.shared.single, endsWith('.qdv'));
  });
}
