import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/quick_entry.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../features/crm/crm_flow_test.dart' show pumpCrmApp, tapVisible;
import '../helpers/crm_fakes.dart';
import 'batch02_layout_test.dart' show capture, cases, shot;

/// «الإدخال السريع» على مقاسات الهواتف وتكبير الخط: لا تجاوز ولا قص.
const _user = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000001',
  username: 'gm',
  displayName: 'المدير العام',
  roles: ['general_manager'],
  permissions: {
    'customers.view_all',
    'suppliers.view_all',
    'customers.create',
    'suppliers.create',
    'reports.export',
    'import.run',
    'records.manage',
  },
  mustChangePassword: false,
);

const _long = 'مصنع عبدالرحمن علي حسن للصناعات البلاستيكية والتعبئة والتغليف';

FakeCrmRepository _repo() => FakeCrmRepository()
  ..excelSheets = const [
    ExcelSheetData(
      name: 'ورقة العملاء والموردين الرئيسية',
      headers: [
        'رقم الموبايل الأساسي',
        'اسم الشركة بالكامل',
        'الخامة',
        'Grade',
        'النوع',
      ],
      rows: [
        ['01011112222', _long, 'PP', 'MARLEX 030', 'عميل'],
      ],
      mapping: {'phone': 0, 'name': 1, 'material': 2, 'grade': 3},
    ),
    ExcelSheetData(name: 'ثانية', headers: [], rows: [], mapping: {}),
  ]
  ..exportResult = const ExportData(1, 1, [
    ExportItem(
      kind: 'customer',
      partyId: 'p1',
      name: _long,
      phone: '01011112222',
      material: 'PP',
      grade: 'MARLEX 030',
    ),
    ExportItem(
      kind: 'supplier',
      partyId: 'p2',
      name: _long,
      phone: '01122223333',
      material: 'PP',
      grade: '129H',
    ),
  ])
  ..pendingStore.add(
    PendingEntry(
      id: 'e1',
      batchId: 'b1',
      row: 12,
      kind: 'customer',
      name: _long,
      phone: '0101111',
      material: 'PP',
      grade: 'غير معروف',
      status: 'pending',
      issues: const ['phone_invalid', 'grade_unknown'],
      createdAt: DateTime(2026, 11, 1),
      createdByName: 'السكرتارية',
    ),
  )
  ..batchList = [
    BatchSummary(
      id: 'b1',
      method: 'excel',
      fileName: 'ملف-العملاء-والموردين-نوفمبر-2026-النسخة-النهائية.xlsx',
      rowCount: 1200,
      created: 1100,
      pending: 80,
      duplicate: 20,
      failed: 0,
      status: 'partially_undone',
      createdAt: DateTime(2026, 11, 1),
      createdByName: 'السكرتارية',
    ),
  ];

Future<FakeCrmRepository> _pump(
  WidgetTester tester,
  String at,
  Size size,
  double scale,
) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final crm = await pumpCrmApp(tester, at: at, crm: _repo(), user: _user);
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  await tester.pumpAndSettle();
  return crm;
}

void main() {
  for (final (name, size, scale) in cases) {
    testWidgets('quick entry paste and review: $name', (tester) async {
      final problems = await capture((_) async {
        await _pump(tester, CrmRoutes.quickEntry, size, scale);
        await tester.enterText(
          find.byKey(const Key('paste.text')),
          'الاسم\tالموبايل\tالخامة\tGrade\n'
          '$_long\t01011112222\tPP\tMARLEX 030\n'
          '$_long\t0101\tABS\t',
        );
        await tester.pump();
        await tapVisible(tester, find.byKey(const Key('paste.analyze')));
        await shot(tester, 'quick_paste_$name');
        await tapVisible(tester, find.byKey(const Key('paste.review')));
        await shot(tester, 'quick_review_$name');
        await tapVisible(tester, find.byKey(const Key('qr.row.3')));
        await shot(tester, 'quick_review_edit_$name');
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byKey(const Key('qr.commit')));
        await shot(tester, 'quick_result_$name');
      });
      expect(problems, isEmpty);
    });

    testWidgets('quick entry excel and export tabs: $name', (tester) async {
      final problems = await capture((_) async {
        await _pump(tester, CrmRoutes.quickEntry, size, scale);
        await tapVisible(tester, find.text('استيراد Excel'));
        await tapVisible(tester, find.byKey(const Key('excel.pick')));
        await tapVisible(tester, find.byKey(const Key('excel.audience.mixed')));
        await shot(tester, 'quick_excel_$name');
        await tapVisible(tester, find.text('تصدير البيانات'));
        await tapVisible(
          tester,
          find.byKey(const Key('export.audience.mixed')),
        );
        await tapVisible(tester, find.byKey(const Key('export.scope.true')));
        await tapVisible(tester, find.byKey(const Key('export.preview')));
        await shot(tester, 'quick_export_$name');
        await tapVisible(tester, find.byKey(const Key('quick.tools')));
        await shot(tester, 'quick_tools_$name');
      });
      expect(problems, isEmpty);
    });

    testWidgets('pending and batches: $name', (tester) async {
      final problems = await capture((_) async {
        await _pump(tester, CrmRoutes.quickPending, size, scale);
        await shot(tester, 'quick_pending_$name');
        await tapVisible(tester, find.byKey(const Key('pending.row.e1')));
        await shot(tester, 'quick_pending_edit_$name');
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      });
      expect(problems, isEmpty);
    });

    testWidgets('batches: $name', (tester) async {
      final batches = await capture((_) async {
        await _pump(tester, CrmRoutes.quickBatches, size, scale);
        await shot(tester, 'quick_batches_$name');
      });
      expect(batches, isEmpty);
    });
  }
}
