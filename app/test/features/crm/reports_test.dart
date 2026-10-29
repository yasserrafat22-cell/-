import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

const _rep = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000011',
  username: 'rep',
  displayName: 'مندوب',
  roles: ['representative'],
  permissions: {'customers.view', 'customers.create', 'reports.view'},
  mustChangePassword: false,
);

const _manager = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000012',
  username: 'sales',
  displayName: 'مدير المبيعات',
  roles: ['sales_manager'],
  permissions: {'customers.view_all', 'reports.view', 'reports.export'},
  mustChangePassword: false,
);

ReportDashboard _dashboard({bool suppliers = false, bool quality = false}) =>
    ReportDashboard(
      from: DateTime(2026, 10),
      to: DateTime(2026, 10, 28),
      kpis: const ReportKpis(
        completedOrders: 3,
        completedKg: 12000,
        openOrders: 2,
        openKg: 4000,
        cancelledOrders: 1,
        cancelledKg: 500,
        activeCustomers: 2,
        newCustomers: 1,
        contacts: 9,
        conversionRate: 0.75,
      ),
      pipeline: const [
        ReportPoint('Inquiry', 1, 1000),
        ReportPoint('Completed', 3, 12000),
        ReportPoint('Cancelled', 1, 500),
      ],
      materials: const [RankRow('PP', 3, 12000, id: 'mat-pp')],
      grades: const [RankRow('PP · سابك · 500P', 2, 8000, id: 'g-1')],
      customers: const [
        RankRow(
          'شركة النور للصناعات البلاستيكية',
          2,
          9000,
          id: 'party-1',
          extra: 'آخر طلب 2026-10-20',
        ),
      ],
      representatives: const [RankRow('مندوب', 3, 12000, extra: '9 تواصل')],
      suppliers: suppliers
          ? const [RankRow('شركة الصفوة', 1, 20000, id: 'party-2')]
          : null,
      trend: const [
        ReportPoint('2026-09', 1, 3000),
        ReportPoint('2026-10', 3, 12000),
      ],
      demand: const [DemandRow('PP', 5, 12000, null)],
      activity: (1, 2, 3, 4),
      overdue: 2,
      today: 1,
      incomplete: 3,
      quality: quality
          ? const DataQuality(
              missingActivity: 1,
              missingGovernorate: 2,
              withoutLocation: 3,
              withoutContacts: 4,
              duplicates: [],
            )
          : null,
    );

void main() {
  testWidgets('a representative sees the current month in scope without '
      'export, suppliers or data quality', (tester) async {
    final crm = FakeCrmRepository()..report = _dashboard();
    await pumpCrmApp(tester, crm: crm, user: _rep);
    await tester.tap(find.byKey(const Key('home.reports')));
    await tester.pumpAndSettle();
    expect(crm.reportFilters.single.isEmpty, isTrue);
    expect(find.text('2026-10-01 — 2026-10-28'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('report.completed')),
        matching: find.text('3 طلب'),
      ),
      findsOneWidget,
    );
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('غير متاحة'), findsOneWidget);
    expect(find.byKey(const Key('report.export')), findsNothing);
    expect(find.byKey(const Key('report.suppliers')), findsNothing);
    expect(find.byKey(const Key('report.quality')), findsNothing);
    await tester.scrollUntilVisible(
      find.textContaining('شركة النور'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('آخر طلب 2026-10-20'), findsOneWidget);
  });

  testWidgets('period filter asks the server for last month', (tester) async {
    final crm = FakeCrmRepository()..report = _dashboard();
    await pumpCrmApp(tester, crm: crm, user: _manager, at: CrmRoutes.reports);
    await tapVisible(tester, find.byKey(const Key('report.period')));
    await tapVisible(
      tester,
      find.byKey(const Key('report.period.الشهر الماضي')),
    );
    final filter = crm.reportFilters.last;
    expect(filter.from, DateTime(2026, 9));
    expect(filter.to, DateTime(2026, 9, 30));
  });

  testWidgets('a manager previews chosen sections then shares text, PDF, '
      'Excel or prints — each authorized by the server', (tester) async {
    final crm = FakeCrmRepository()
      ..report = _dashboard(suppliers: true, quality: true);
    final documents = FakeDocumentServices();
    await pumpCrmApp(
      tester,
      crm: crm,
      user: _manager,
      at: CrmRoutes.reports,
      documents: documents,
    );

    Future<void> export(String format, {bool dropQuality = false}) async {
      await tester.tap(find.byKey(const Key('report.export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('report.export.$format')));
      await tester.pumpAndSettle();
      if (dropQuality) {
        await tapVisible(
          tester,
          find.byKey(const Key('report.section.quality')),
        );
      }
      await tester.tap(find.byKey(const Key('report.confirm')));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('report.export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report.export.text')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('report.preview')),
        matching: find.textContaining('مكتمل (مبيعات محققة)'),
      ),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('report.section.quality')));
    expect(
      find.descendant(
        of: find.byKey(const Key('report.preview')),
        matching: find.textContaining('جودة البيانات'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('report.confirm')));
    await tester.pumpAndSettle();
    expect(crm.shareRequests.last, ('report.text', 12));
    expect(crm.shared.last, contains('تقرير القادسية'));
    expect(crm.shared.last, isNot(contains('جودة البيانات')));

    await export('pdf');
    expect(crm.shareRequests.last.$1, 'report.pdf');
    expect(
      documents.pdfs.single.sections.map((s) => s.$1),
      contains('الموردون'),
    );

    await export('print', dropQuality: true);
    expect(crm.shareRequests.last.$1, 'report.print');
    expect(documents.printed.single.sections.length, 12);

    await export('excel');
    expect(crm.reportExcels.single, contains('kpis'));
  });
}
