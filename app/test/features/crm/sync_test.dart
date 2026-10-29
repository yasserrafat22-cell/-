import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/offline/offline_store.dart';
import 'package:qadisiyah/features/crm/data/crm_repository.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

PendingOp _op(
  String id, {
  String partyId = 'party-1',
  String? kind,
  PendingStatus status = PendingStatus.pending,
  String? error,
}) => PendingOp(
  id: id,
  userId: 'u',
  method: 'POST',
  path: '/api/v1/parties/$partyId/contacts',
  body: const {},
  label: 'جهة اتصال: سامي',
  createdAt: DateTime(2026, 10, 28, 9),
  partyId: partyId,
  kind: kind,
  status: status,
  error: error,
);

void main() {
  testWidgets('home shows what waits for sync and syncs on demand', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..pendingList.addAll([
        _op('o1'),
        _op('o2', status: PendingStatus.needsReview, error: 'مرفوض'),
      ])
      ..nextSync = const SyncResult(1, 1);
    await pumpCrmApp(tester, crm: crm);
    // فتح التطبيق مع بيانات معلقة يبدأ مزامنة تلقائية؛ يبقى ما يحتاج مراجعة.
    expect(crm.syncCalls, 1);
    expect(find.text('تحتاج مراجعة: 1'), findsOneWidget);

    crm.pendingList.add(_op('o3'));
    await tester.tap(find.byKey(const Key('sync.now')));
    await tester.pumpAndSettle();
    expect(crm.syncCalls, 2);
    expect(find.text('تمت مزامنة 1، و1 تحتاج مراجعة'), findsOneWidget);
  });

  testWidgets('a rejected operation is reviewed: retry or discard', (
    tester,
  ) async {
    final rejected = _op(
      'o2',
      status: PendingStatus.needsReview,
      error: 'رقم الهاتف مسجل بالفعل في النظام',
    );
    final crm = FakeCrmRepository()..pendingList.add(rejected);
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.sync);
    expect(find.text('رقم الهاتف مسجل بالفعل في النظام'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync.discard.o2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sync.confirmDiscard')));
    await tester.pumpAndSettle();
    expect(crm.pendingList, isEmpty);
    expect(find.text('كل البيانات وصلت للسيرفر'), findsOneWidget);
  });

  testWidgets('a record with nothing pending shows it is synced', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..pendingList.add(
        _op('o1', partyId: 'party-2', status: PendingStatus.needsReview),
      );
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-1'));
    expect(find.byKey(const Key('sync.status.synced')), findsOneWidget);
  });

  testWidgets('a record with a rejected operation needs review', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..pendingList.add(
        _op('o1', partyId: 'party-2', status: PendingStatus.needsReview),
      );
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-2'));
    expect(find.byKey(const Key('sync.status.needsReview')), findsOneWidget);
  });

  testWidgets('a record created on the device is labelled as such in the '
      'registry', (tester) async {
    final crm = FakeCrmRepository()
      ..pendingList.add(_op('o1', kind: 'party.create'));
    await pumpCrmApp(tester, crm: crm, at: CrmRoutes.registry);
    expect(find.byKey(const Key('sync.status.savedLocally')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('registry.item.party-1')));
    expect(find.byKey(const Key('sync.status.savedLocally')), findsOneWidget);
  });
}
