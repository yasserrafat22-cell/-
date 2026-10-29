import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';
import 'package:qadisiyah/features/crm/presentation/party_profile_screen.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

FollowUpItem _f(
  String id, {
  required FollowUpStatus status,
  required DateTime due,
  bool remind = true,
  bool mine = true,
  String partyId = 'party-1',
}) => FollowUpItem(
  interactionId: id,
  partyId: partyId,
  partyName: 'شركة النور',
  isCustomer: true,
  dueAt: due,
  status: status,
  remind: remind,
  mine: mine,
  representativeName: 'أحمد محمد',
);

// الساعة الثابتة في الاختبارات: 2026-10-28 10:00.
final _later = DateTime(2026, 10, 28, 15);
final _tomorrow = DateTime(2026, 10, 29, 11);

const _rep = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000011',
  username: 'rep',
  displayName: 'مندوب',
  roles: ['representative'],
  permissions: {'customers.view', 'customers.create', 'reports.view'},
  mustChangePassword: false,
);

void main() {
  group('follow-up bell and reminders', () {
    testWidgets('the bell counts today and overdue and opens the list', (
      tester,
    ) async {
      final crm = FakeCrmRepository()
        ..followUpList = [
          _f('i1', status: FollowUpStatus.overdue, due: DateTime(2026, 10, 27)),
          _f('i2', status: FollowUpStatus.today, due: _later),
          _f('i3', status: FollowUpStatus.upcoming, due: _tomorrow),
        ];
      await pumpCrmApp(tester, crm: crm);
      expect(find.byKey(const Key('home.bellCount')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home.bell')));
      await tester.pumpAndSettle();
      expect(find.text('متأخرة (1)'), findsOneWidget);
      expect(find.text('اليوم (1)'), findsOneWidget);
      expect(find.text('القادمة (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('followUp.i2')));
      await tester.pumpAndSettle();
      expect(find.byType(PartyProfileScreen), findsOneWidget);
    });

    testWidgets('only own future follow-ups with «تذكير» notify, once each', (
      tester,
    ) async {
      final reminders = FakeReminderScheduler();
      final crm = FakeCrmRepository()
        ..followUpList = [
          _f('remind', status: FollowUpStatus.today, due: _later),
          _f(
            'no-remind',
            status: FollowUpStatus.today,
            due: _later,
            remind: false,
          ),
          _f(
            'other-rep',
            status: FollowUpStatus.upcoming,
            due: _tomorrow,
            mine: false,
          ),
          _f(
            'past',
            status: FollowUpStatus.overdue,
            due: DateTime(2026, 10, 27),
          ),
        ];
      await pumpCrmApp(tester, crm: crm, reminders: reminders);
      expect(reminders.scheduled.keys, ['remind']);
      expect(reminders.scheduled['remind']!.at, _later);
      expect(reminders.permissionRequests, 1);

      // الضغط على الإشعار يفتح ملف السجل.
      reminders.onOpen!('party-1');
      await tester.pumpAndSettle();
      expect(find.byType(PartyProfileScreen), findsOneWidget);
    });

    testWidgets('closing or moving a follow-up updates its notification and '
        'logout clears all', (tester) async {
      final reminders = FakeReminderScheduler();
      final crm = FakeCrmRepository()
        ..followUpList = [
          _f('a', status: FollowUpStatus.today, due: _later),
          _f('b', status: FollowUpStatus.upcoming, due: _tomorrow),
        ];
      await pumpCrmApp(tester, crm: crm, reminders: reminders);
      expect(reminders.scheduled.keys, unorderedEquals(['a', 'b']));

      // تسجيل تواصل جديد أغلق «a» وغيّر موعد «b».
      final moved = DateTime(2026, 10, 30, 9);
      crm.followUpList = [_f('b', status: FollowUpStatus.upcoming, due: moved)];
      await tapVisible(tester, find.byKey(const Key('home.bell')));
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(reminders.scheduled.keys, ['b']);
      expect(reminders.scheduled['b']!.at, moved);

      Navigator.of(tester.element(find.byType(ListView).first)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.logout')));
      await tester.pumpAndSettle();
      expect(reminders.clears, 1);
      expect(reminders.scheduled, isEmpty);
    });
  });

  group('supplier matching', () {
    final match = SupplierMatch(
      supplierId: 'party-2',
      supplierName: 'شركة الصفوة لمواد البلاستيك',
      product: const MaterialSpec(
        materialId: 'mat-pp',
        materialCode: 'PP',
        gradeId: 'g-pp500',
        gradeCode: 'PP500',
        precision: SpecPrecision.exact,
      ),
      need: const MaterialSpec(materialId: 'mat-pp', materialCode: 'PP'),
      score: 110,
      reasons: const ['نفس الخامة والشركة المصنّعة والـ Grade'],
      price: 45000,
      currency: 'EGP',
      quoteDate: DateTime(2026, 10, 20),
    );

    testWidgets(
      'office staff see exact matches and alternatives with reasons',
      (tester) async {
        final crm = FakeCrmRepository()..matches = SupplierMatches([match], []);
        await pumpCrmApp(tester, crm: crm, at: CrmRoutes.party('party-1'));
        await tester.tap(find.byKey(const Key('tab.3')));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byKey(const Key('profile.matches')));
        expect(find.text('مطابقة دقيقة'), findsOneWidget);
        expect(
          find.text('• نفس الخامة والشركة المصنّعة والـ Grade'),
          findsOneWidget,
        );
        expect(find.textContaining('آخر سعر مسجل: 45000 EGP'), findsOneWidget);
      },
    );

    testWidgets('a representative never sees supplier matching', (
      tester,
    ) async {
      final crm = FakeCrmRepository(
        parties: [sampleCustomer(canEdit: false, canAdd: true)],
      )..matches = SupplierMatches([match], []);
      await pumpCrmApp(
        tester,
        crm: crm,
        at: CrmRoutes.party('party-1'),
        user: _rep,
      );
      await tester.tap(find.byKey(const Key('tab.3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile.matches')), findsNothing);
      expect(find.textContaining('الصفوة'), findsNothing);
    });
  });
}
