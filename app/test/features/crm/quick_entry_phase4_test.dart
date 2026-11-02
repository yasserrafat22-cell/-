import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/quick_entry.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

/// الإدخال السريع 0.7.0 — المرحلة 4 (الواجهة): التحذيرات والـ Grade غير الموثق وأعلام المحلل، التأكيد
/// الصريح للمراجعة، تنظيف «بانتظار الاستكمال»، الوعي بالعمليات المحلية، الخروج دون حفظ، ومسافة شريط النظام.
const _secretary = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000031',
  username: 'office',
  displayName: 'سكرتارية',
  roles: ['secretary'],
  permissions: {
    'customers.view_all',
    'suppliers.view_all',
    'customers.create',
    'suppliers.create',
    'reports.export',
    'import.run',
  },
  mustChangePassword: false,
);

PendingEntry _entry(
  String id, {
  String name = 'شركة معلقة',
  String? phone = '01011112222',
  String? material = 'PVC',
  String? grade,
  List<String> issues = const [],
  List<String> warnings = const [],
  bool needsReview = false,
  String? unverifiedGrade,
}) => PendingEntry(
  id: id,
  batchId: 'b1',
  method: 'paste',
  row: 1,
  kind: 'customer',
  name: name,
  phone: phone,
  material: material,
  grade: grade,
  status: 'pending',
  issues: issues,
  warnings: warnings,
  needsReview: needsReview,
  unverifiedGrade: unverifiedGrade,
  createdAt: DateTime(2026, 11, 2),
);

Future<void> _paste(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('paste.text')), text);
  await tester.pump();
  await tapVisible(tester, find.byKey(const Key('paste.analyze')));
  await tapVisible(tester, find.byKey(const Key('paste.review')));
}

void main() {
  testWidgets('review shows warnings, unverified grades and parser flags; an '
      'ambiguous grade is saved only after explicit acknowledgment', (
    tester,
  ) async {
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    // PP500 مسجل لخامة PP فقط: مع PVC يحتاج مراجعة. و«PP 500» رقم مستدير قد يكون كمية.
    await _paste(
      tester,
      'شركة الخطأ 01011112222 PVC PP500\nشركة الأمانة 01012121212 PP 500',
    );

    expect(find.byKey(const Key('qr.count.needs_review')), findsOneWidget);
    expect(find.text('يحتاج مراجعة'), findsWidgets);
    expect(find.byKey(const Key('qr.warnings.1')), findsOneWidget);
    expect(find.byKey(const Key('qr.unverified.1')), findsOneWidget);
    expect(find.byKey(const Key('qr.unverified.2')), findsOneWidget);
    expect(find.byKey(const Key('qr.flags.2')), findsOneWidget);
    // الصف الثاني جاهز رغم الـ Grade غير الموثق (اختياري ولا يمنع الحفظ).
    expect(find.byKey(const Key('qr.ack.2')), findsNothing);

    await tapVisible(tester, find.byKey(const Key('qr.ack.1')));
    expect(find.byKey(const Key('qr.ackDialog')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('qr.ackOk')));
    expect(find.byKey(const Key('qr.acked.1')), findsOneWidget);
    expect(find.byKey(const Key('qr.count.needs_review')), findsNothing);

    await tapVisible(tester, find.byKey(const Key('qr.commit')));
    final sent = crm.quickCommits.single.$4;
    expect(sent.first.reviewAcknowledged, isTrue);
    expect(sent.first.toJson()['reviewAcknowledged'], isTrue);
    expect(sent.last.reviewAcknowledged, isFalse);
  });

  testWidgets('leaving an unsaved review asks to discard temporary data or '
      'continue reviewing', (tester) async {
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await _paste(tester, 'شركة النور 01011112222 PP');

    await tapVisible(tester, find.byKey(const Key('crm.back')));
    expect(find.byKey(const Key('qr.leaveDialog')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('qr.leaveStay')));
    expect(find.byKey(const Key('qr.list')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('crm.back')));
    await tapVisible(tester, find.byKey(const Key('qr.leaveDiscard')));
    expect(find.byKey(const Key('qr.list')), findsNothing);
    expect(find.byKey(const Key('paste.text')), findsOneWidget);
    expect(crm.quickCommits, isEmpty);
    expect(crm.pendingList, isEmpty, reason: 'لا يُحذف شيء من طابور الجهاز');
  });

  testWidgets('pending cleanup: single, multi-select and discard-all follow '
      'the server results and show protected reasons', (tester) async {
    final crm = FakeCrmRepository()
      ..pendingStore.addAll([
        _entry('e1', name: 'صف أول'),
        _entry('e2', name: 'صف ثانٍ'),
        _entry('e3', name: 'صف محمي'),
        _entry('e4', name: 'صف رابع'),
      ])
      ..protectedPending['e3'] = 'awaiting_promotion'
      ..localQuickOpsCount = 2;
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickPending,
      user: _secretary,
    );
    // العمليات المحلية للعرض فقط.
    expect(find.byKey(const Key('pending.localOps')), findsOneWidget);

    // فردي.
    await tapVisible(tester, find.byKey(const Key('pending.discard.e1')));
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(crm.pendingDiscards, ['e1']);
    expect(find.byKey(const Key('pending.row.e1')), findsNothing);

    // فردي على صف محمي: رسالة السيرفر ولا استبعاد.
    await tapVisible(tester, find.byKey(const Key('pending.discard.e3')));
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(find.text(discardReasonLabel('awaiting_promotion')), findsOneWidget);
    expect(find.byKey(const Key('pending.row.e3')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // انتهاء رسالة الخطأ
    await tester.pumpAndSettle();

    // تحديد متعدد: صف عادي + صف محمي.
    await tester.longPress(find.byKey(const Key('pending.row.e2')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('pending.row.e3')));
    expect(find.text('محدد: 2'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pending.discardSelected')));
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(find.byKey(const Key('pending.result')), findsOneWidget);
    expect(find.text('استُبعد: 1'), findsOneWidget);
    expect(find.text('لم يُستبعد (محمي): 1'), findsOneWidget);
    expect(
      find.text('• ${discardReasonLabel('awaiting_promotion')}: 1'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('حسنًا'));
    expect(crm.pendingDiscards, ['e1', 'e2']);

    // حذف الكل: معاينة بالأعداد، ثم تأكيد ثانٍ، ثم التنفيذ بنفس الرمز.
    await tapVisible(tester, find.byKey(const Key('pending.discardAll')));
    expect(find.byKey(const Key('pending.allPreview')), findsOneWidget);
    expect(find.text('سيُستبعد: 1'), findsOneWidget);
    expect(find.text('محمي ولن يُستبعد: 1'), findsOneWidget);
    expect(find.text('العدد بعد الاستبعاد: 1'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pending.allNext')));
    expect(find.text('استبعاد 1 صف نهائيًا من «بانتظار الاستكمال»؟'), findsOne);
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(crm.discardAllCalls, [null, 'e4']);
    expect(find.text('استُبعد: 1'), findsOneWidget);
    await tapVisible(tester, find.text('حسنًا'));
    expect(find.text('1 صف'), findsOneWidget); // المحمي فقط
    expect(find.byKey(const Key('pending.row.e3')), findsOneWidget);
  });

  testWidgets('discard-all stops safely when the list changed after preview', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..pendingStore.addAll([_entry('e1'), _entry('e2')])
      ..snapshotChangeOnce = true;
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickPending,
      user: _secretary,
    );
    await tapVisible(tester, find.byKey(const Key('pending.discardAll')));
    await tapVisible(tester, find.byKey(const Key('pending.allNext')));
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(
      find.text(
        'تغيرت القائمة منذ المعاينة ولم يُستبعد شيء. افتح المعاينة من جديد.',
      ),
      findsOneWidget,
    );
    expect(crm.pendingDiscards, isEmpty);
    expect(find.text('2 صف'), findsOneWidget);
  });

  testWidgets('completing a pending row with an ambiguous grade asks for '
      'explicit review and sends the acknowledgment', (tester) async {
    final crm = FakeCrmRepository()
      ..pendingStore.add(
        _entry(
          'e1',
          material: 'PVC',
          grade: 'PP500',
          warnings: const ['grade_material_mismatch'],
          needsReview: true,
          unverifiedGrade: 'PP500',
        ),
      );
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickPending,
      user: _secretary,
    );
    expect(find.text('يحتاج مراجعة'), findsOneWidget);
    expect(find.byKey(const Key('pending.warnings.e1')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pending.row.e1')));
    expect(find.byKey(const Key('qe.needsReview')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pending.complete')));
    expect(find.text('تأكيد مراجعة الـ Grade'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(crm.reviewAcks, ['e1']);
    expect(find.text('فتح البطاقة'), findsOneWidget);
  });

  testWidgets('with the keyboard open the paste actions stay reachable', (
    tester,
  ) async {
    await pumpCrmApp(tester, at: CrmRoutes.quickEntry, user: _secretary);
    tester.view
      ..physicalSize = const Size(360, 720) * 2
      ..devicePixelRatio = 2
      ..viewPadding = const FakeViewPadding(bottom: 96)
      ..viewInsets = const FakeViewPadding(bottom: 600); // لوحة مفاتيح 300dp
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('paste.text')),
      'شركة النور 01011112222 PP',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('paste.analyze')));
    await tester.pumpAndSettle();
    final analyze = tester.getRect(find.byKey(const Key('paste.analyze')));
    expect(analyze.bottom, lessThanOrEqualTo(720 - 300));
    expect(tester.takeException(), isNull);
  });

  for (final (name, navBar) in [('3-button', 96.0), ('gesture', 48.0)]) {
    testWidgets('quick entry buttons stay above the system nav bar: $name', (
      tester,
    ) async {
      await pumpCrmApp(tester, at: CrmRoutes.quickEntry, user: _secretary);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view
        ..physicalSize = const Size(360, 720) * 2
        ..devicePixelRatio = 2
        ..padding = FakeViewPadding(bottom: navBar)
        ..viewPadding = FakeViewPadding(bottom: navBar);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('paste.text')),
        'مصنع عبدالرحمن علي حسن للصناعات البلاستيكية 01011112222 PP 575P',
      );
      await tester.pump();
      await tapVisible(tester, find.byKey(const Key('paste.analyze')));
      await tester.drag(
        find.byKey(const Key('paste.view')),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      final review = tester.getRect(find.byKey(const Key('paste.review')));
      expect(review.bottom, lessThanOrEqualTo(720 - navBar / 2));
      expect(
        find.byKey(const Key('paste.review')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('pending selection bar stays above the system nav bar: $name', (
      tester,
    ) async {
      final crm = FakeCrmRepository()
        ..pendingStore.addAll([
          for (var i = 0; i < 12; i++) _entry('e$i', name: 'صف رقم $i'),
        ]);
      await pumpCrmApp(
        tester,
        crm: crm,
        at: CrmRoutes.quickPending,
        user: _secretary,
      );
      tester.view
        ..physicalSize = const Size(320, 640) * 2
        ..devicePixelRatio = 2
        ..padding = FakeViewPadding(bottom: navBar)
        ..viewPadding = FakeViewPadding(bottom: navBar);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('pending.row.e0')));
      await tester.pumpAndSettle();
      final bar = tester.getRect(
        find.byKey(const Key('pending.discardSelected')),
      );
      expect(bar.bottom, lessThanOrEqualTo(640 - navBar / 2));
      expect(tester.takeException(), isNull);
    });
  }
}
