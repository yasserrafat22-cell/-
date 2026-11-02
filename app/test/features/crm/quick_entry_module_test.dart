import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/core/offline/offline_store.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/domain/quick_entry.dart';
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
    'customers.create',
    'suppliers.create',
    'reports.export',
    'import.run',
  },
  mustChangePassword: false,
);

const _manager = AuthUser(
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

/// يصدّر العملاء فقط (لا يطّلع على الموردين).
const _customerExporter = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000012',
  username: 'sales',
  displayName: 'مبيعات',
  roles: ['sales_manager'],
  permissions: {'customers.view_all', 'customers.create', 'reports.export'},
  mustChangePassword: false,
);

PendingEntry _pending({
  String id = 'e1',
  String status = 'pending',
  String? kind = 'customer',
  String? name = 'شركة الأمل',
  String? phone = '01011112222',
  String? material = 'PVC',
  String? grade,
  List<String> issues = const ['grade_missing'],
  String? duplicateOfId,
  String? duplicateName,
}) => PendingEntry(
  id: id,
  batchId: 'b1',
  method: 'paste',
  row: 1,
  kind: kind,
  name: name,
  phone: phone,
  material: material,
  grade: grade,
  status: status,
  issues: issues,
  duplicateOfId: duplicateOfId,
  duplicateName: duplicateName,
  createdAt: DateTime(2026, 11, 1),
);

Future<void> _pickOption(WidgetTester tester, String key, String label) async {
  await tapVisible(tester, find.byKey(Key(key)));
  await tapVisible(tester, find.byKey(Key(label)));
}

void main() {
  group('paste parsing and local rules', () {
    test('tab grid from Excel maps by content, not column order', () {
      final p = parsePaste(
        '01011112222\tPVC\tشركة الأمل\tSG-5\n'
        '01122223333\tPP\tمصنع الفجر\t129H',
        testReference,
      );
      expect(p.free, isFalse);
      expect(p.mapping, {'phone': 0, 'material': 1, 'grade': 3, 'name': 2});
    });

    test('comma-separated WhatsApp lines are records, not Excel columns', () {
      final p = parsePaste(
        'شركة أ، 01011112222، PVC، SG-5\nشركة ب، 01122223333، PP، 129H',
        testReference,
      );
      // لا تعيين أعمدة للنص الحر.
      expect(p.free, isTrue);
      expect(p.cells.first, [
        'شركة أ',
        '01011112222',
        'PVC',
        'SG-5',
        '',
        '',
        '',
      ]);
      expect(p.cells[1].take(4), ['شركة ب', '01122223333', 'PP', '129H']);
    });

    test('WhatsApp free text extracts phone, material and grade', () {
      final p = parsePaste(
        'أحمد علي - مصنع النور 010 1111 2222 PP PP500\n'
        'شركة السلام، فرع العاشر 01122223333',
        testReference,
      );
      expect(p.free, isTrue);
      expect(p.cells[0].take(4), [
        'أحمد علي - مصنع النور',
        '01011112222',
        'PP',
        'PP500',
      ]);
      // الفاصلة داخل الاسم لا تقسمه.
      expect(p.cells[1][0], 'شركة السلام، فرع العاشر');
      expect(p.cells[1][1], '01122223333');
    });

    test('free text: a name line followed by a phone line is one record', () {
      final p = parsePaste(
        'مصنع الهدى للبلاستيك\n01011112222\nPP 575P\n\n'
        'شركة النيل\n01122223333\nHDPE 668',
        testReference,
      );
      expect(p.cells, hasLength(2));
      expect(p.cells[0].take(4), [
        'مصنع الهدى للبلاستيك',
        '01011112222',
        'PP',
        '575P',
      ]);
      expect(p.cells[1].take(4), ['شركة النيل', '01122223333', 'HDPE', '668']);
    });

    test('free text: name lines alternate with phone lines', () {
      final p = parsePaste(
        'شركة أ\n01011112222 PP\nشركة ب\n01122223333 HDPE 5502',
        testReference,
      );
      expect(
        [for (final c in p.cells) c.take(3).toList()],
        [
          ['شركة أ', '01011112222', 'PP'],
          ['شركة ب', '01122223333', 'HDPE'],
        ],
      );
    });

    test(
      'free text: two records without a delimiter are split and flagged',
      () {
        final p = parsePaste(
          'شركة أ 01011112222 PP 575P شركة ب 01122223333 HDPE 668',
          testReference,
        );
        expect(p.cells, hasLength(2));
        expect(p.cells[0].take(4), ['شركة أ', '01011112222', 'PP', '575P']);
        expect(p.cells[1].take(4), ['شركة ب', '01122223333', 'HDPE', '668']);
        expect(p.flags[0], contains('split_uncertain'));
      },
    );

    test('free text: a country inside a company name is not an origin', () {
      final p = parsePaste(
        'شركة مصر للبلاستيك 01011112222 PP\n'
        'مصنع النور 01122223333 PP 575P منشأ السعودية',
        testReference,
      );
      expect(p.cells[0][0], 'شركة مصر للبلاستيك');
      expect(p.cells[0][5], '');
      expect(p.cells[1][0], 'مصنع النور');
      expect(p.cells[1][5], 'السعودية');
    });

    test(
      'free text: WhatsApp export prefix, quantity and price are ignored',
      () {
        final p = parsePaste(
          '2/11/26, 10:15 م - Sales: شركة الأمان 01011112222 HDPE 5502 '
          'الكمية 25 طن بسعر 61000',
          testReference,
        );
        expect(p.cells.single.take(4), [
          'شركة الأمان',
          '01011112222',
          'HDPE',
          '5502',
        ]);
      },
    );

    test('excel rows keep their source row numbers and origin column', () {
      final sheet = ExcelSheetData.fromJson(const {
        'name': 'موردين',
        'headers': ['المورد', 'رقم الهاتف', 'الخامه', 'الدرجة', 'بلد المنشأ'],
        'rows': [
          ['شركة ز', '1177778888', 'HDPE', '5502', 'السعودية'],
          ['شركة ح', '01011112222', 'PP', '', ''],
        ],
        'mapping': {
          'name': 0,
          'phone': 1,
          'material': 2,
          'grade': 3,
          'origin': 4,
        },
        'headerRow': 3,
        'sourceRows': [5, 9],
      });
      var n = 0;
      final rows = rowsFrom(
        sheet.rows,
        sheet.mapping,
        newId: () => '${n++}',
        kind: 'supplier',
        firstRow: sheet.headerRow + 1,
        sourceRows: sheet.sourceRows,
      );
      expect([for (final r in rows) r.row], [5, 9]);
      expect(rows.first.origin, 'السعودية');
      // Excel يحذف الصفر الأول: الرقم صحيح بنفس قاعدة السيرفر.
      expect(normalizeMobile(rows.first.phone!), '01177778888');
      final check = checkRow(rows.first, 'supplier', testReference);
      expect(check.issues, isEmpty);
      expect(check.origin?.id, 'c-sa');
      expect(rows.first.toJson()['origin'], 'السعودية');
    });

    test('name, Egyptian mobile and catalog material are required; grade is '
        'optional', () {
      LocalCheck check(EntryRow r, [String audience = 'customer']) =>
          checkRow(r, audience, testReference);
      final ok = check(
        EntryRow(
          id: 'a',
          row: 1,
          name: 'شركة',
          phone: '1011112222',
          material: 'pvc',
          grade: 'sg5',
        ),
      );
      expect(ok.issues, isEmpty, reason: 'Excel يحذف الصفر الأول');
      expect(ok.grade?.id, 'g-sg5');
      expect(
        check(
          EntryRow(
            id: 'b',
            row: 1,
            name: 'شركة',
            phone: '01311112222',
            material: 'ABS',
            grade: 'X',
          ),
        ).issues,
        ['phone_invalid', 'material_unknown'],
      );
      expect(
        check(
          EntryRow(
            id: 'c',
            row: 1,
            name: 'شركة',
            phone: '01011112222',
            material: 'PP',
          ),
          'mixed',
        ).issues,
        ['kind_missing'],
      );
      expect(
        check(
          EntryRow(
            id: 'd',
            row: 1,
            name: 'شركة',
            phone: '01011112222',
            material: 'PP',
          ),
        ).warnings,
        ['grade_missing'],
      );
    });

    test('a grade shared by two manufacturers is never guessed', () {
      const refs = ReferenceData(
        activityTypes: [],
        contactOutcomes: [],
        governorates: [],
        currencies: [],
        units: [],
        representatives: [],
        materials: [
          MaterialItem(
            id: 'm',
            code: 'PP',
            nameAr: 'PP',
            grades: [
              GradeItem(id: 'ga', code: 'X1', manufacturerId: 'ma'),
              GradeItem(id: 'gb', code: 'X1', manufacturerId: 'mb'),
            ],
          ),
        ],
        manufacturers: [
          ManufacturerItem(id: 'ma', name: 'مصنع أ'),
          ManufacturerItem(id: 'mb', name: 'مصنع ب'),
        ],
      );
      final row = EntryRow(
        id: 'a',
        row: 1,
        name: 'شركة',
        phone: '01011112222',
        material: 'PP',
        grade: 'X1',
      );
      final ambiguous = checkRow(row, 'customer', refs);
      expect(ambiguous.issues, isEmpty);
      expect(ambiguous.warnings, ['grade_ambiguous']);
      expect(ambiguous.grade, isNull);
      expect(ambiguous.unverifiedGrade, 'X1');
      expect(ambiguous.status(), 'needs_review');
      expect(ambiguous.status(acknowledged: true), 'ready');
      row.manufacturer = 'مصنع ب';
      expect(checkRow(row, 'customer', refs).grade?.id, 'gb');
    });
  });

  testWidgets('paste: complete rows become cards, incomplete go pending, '
      'duplicates are flagged; the batch is sent once', (tester) async {
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await tester.enterText(
      find.byKey(const Key('paste.text')),
      'شركة الأمل\t01011112222\tPVC\tSG-5\n'
      'مصنع الفجر\t0123\tPP\t\n'
      'شركة مكررة\t01001234567\tHDPE\t5502',
    );
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('paste.analyze')));
    expect(find.byKey(const Key('map.name')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('paste.review')));

    expect(find.text('جاهز: 1'), findsOneWidget);
    expect(find.text('ناقص: 1'), findsOneWidget);
    expect(find.text('مكرر: 1'), findsOneWidget);
    expect(crm.quickValidations.last.$2, 'customer');

    // تصفية بالناقص.
    await tapVisible(tester, find.byKey(const Key('qr.count.pending')));
    expect(find.byKey(const Key('qr.row.2')), findsOneWidget);
    expect(find.byKey(const Key('qr.row.1')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('qr.count.pending')));

    await tapVisible(tester, find.byKey(const Key('qr.commit')));
    expect(crm.quickCommits, hasLength(1));
    expect(crm.quickCommits.single.$2, 'paste');
    expect(crm.quickCommits.single.$1, crm.quickValidations.last.$1);
    expect(find.text('أُضيف: 1'), findsOneWidget);
    expect(find.text('بانتظار الاستكمال: 1'), findsOneWidget);
    expect(find.text('مكرر محتمل: 1'), findsOneWidget);
    expect(find.byKey(const Key('qr.open.1')), findsOneWidget);
    expect(crm.pendingStore, hasLength(2));
  });

  testWidgets('review: a row is corrected inline from the catalog and can be '
      'excluded', (tester) async {
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await tester.enterText(
      find.byKey(const Key('paste.text')),
      'مصنع الفجر 01233334444 PP\nشركة زائدة 01155556666',
    );
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('paste.analyze')));
    await tapVisible(tester, find.byKey(const Key('paste.review')));
    // الـ Grade اختياري: الصف بالخامة جاهز، والصف بلا خامة ناقص.
    expect(find.text('جاهز: 1'), findsOneWidget);
    expect(find.text('ناقص: 1'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('qr.row.1')));
    expect(find.byKey(const Key('qe.complete')), findsOneWidget);
    await _pickOption(
      tester,
      'qe.grade',
      'qeGrade.option.129H — مصنع تجريبي ب',
    );
    expect(find.byKey(const Key('qe.complete')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('qe.saveRow')));
    expect(find.text('جاهز: 1'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('qr.row.2')));
    await tapVisible(tester, find.byKey(const Key('qe.excludeRow')));
    expect(find.text('مستبعد: 1'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('qr.commit')));
    final sent = crm.quickCommits.single.$4;
    expect(sent, hasLength(1));
    expect(sent.single.gradeId, 'g-129h');
  });

  testWidgets('review flags a phone already waiting in the offline queue', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..pendingList.add(
        PendingOp(
          id: 'op-1',
          userId: 'u',
          method: 'POST',
          path: '/api/v1/parties',
          body: {
            'name': 'شركة محفوظة',
            'phones': [
              {'e164': '+201011112222'},
            ],
          },
          label: 'تسجيل عميل',
          createdAt: DateTime(2026, 11, 1),
        ),
      );
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await tester.enterText(
      find.byKey(const Key('paste.text')),
      'شركة الأمل 01011112222 PVC SG-5',
    );
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('paste.analyze')));
    await tapVisible(tester, find.byKey(const Key('paste.review')));
    expect(find.text('مكرر: 1'), findsOneWidget);
    expect(
      find.text('الرقم في عملية محفوظة على الجهاز بانتظار المزامنة'),
      findsOneWidget,
    );
  });

  testWidgets('paste offline: the batch is kept on the device', (tester) async {
    final crm = FakeCrmRepository()..quickOffline = true;
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await tester.enterText(
      find.byKey(const Key('paste.text')),
      'شركة الأمل 01011112222 PVC SG-5',
    );
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('paste.analyze')));
    await tapVisible(tester, find.byKey(const Key('paste.review')));
    await tapVisible(tester, find.byKey(const Key('qr.commit')));
    expect(find.text('حُفظت الدفعة على الجهاز'), findsOneWidget);
  });

  testWidgets('excel: file, sheet, mapping, mixed needs a type column', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..excelSheets = const [
        ExcelSheetData(
          name: 'بيانات',
          headers: ['الموبايل', 'الاسم', 'الخامة', 'Grade', 'النوع'],
          rows: [
            ['01011112222', 'شركة الأمل', 'PVC', 'SG-5', 'عميل'],
            ['01122223333', 'مورد الخليج', 'PP', '129H', 'مورد'],
          ],
          mapping: {'phone': 0, 'name': 1, 'material': 2, 'grade': 3},
        ),
        ExcelSheetData(name: 'فارغة', headers: [], rows: [], mapping: {}),
      ];
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await tapVisible(tester, find.text('استيراد Excel'));
    await tapVisible(tester, find.byKey(const Key('excel.pick')));
    expect(find.text('عملاء.xlsx'), findsOneWidget);
    expect(find.text('الورقة «بيانات»: 2 صف'), findsOneWidget);
    expect(find.byKey(const Key('excel.sheet')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('excel.audience.mixed')));
    expect(find.byKey(const Key('excel.needKind')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('map.kind')));
    await tester.tap(find.text('النوع — عميل').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('excel.needKind')), findsNothing);

    await tapVisible(tester, find.byKey(const Key('excel.review')));
    expect(find.text('جاهز: 2'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('qr.commit')));
    final commit = crm.quickCommits.single;
    expect(commit.$2, 'excel');
    expect(commit.$3, 'mixed');
    expect(commit.$4.map((r) => r.kind), ['عميل', 'مورد']);
    expect(commit.$4.first.row, 2, reason: 'الصف 1 عناوين');
    expect(find.text('أُضيف: 2'), findsOneWidget);
  });

  testWidgets('excel: an unsupported file shows the server message', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..excelError = const ApiException(
        'import.xls',
        'صيغة XLS القديمة غير مدعومة',
      );
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await tapVisible(tester, find.text('استيراد Excel'));
    await tapVisible(tester, find.byKey(const Key('excel.pick')));
    expect(find.text('صيغة XLS القديمة غير مدعومة'), findsOneWidget);
  });

  testWidgets('pending: correct, save progress, then create the card once', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..pendingStore.add(_pending(phone: null, issues: const ['phone_missing']))
      ..completeSimilarOnce = true;
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickPending,
      user: _secretary,
    );
    expect(find.text('1 صف'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pending.row.e1')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('pending.complete')))
          .onPressed,
      isNull,
      reason: 'ناقص رقم الموبايل',
    );
    await tester.enterText(find.byKey(const Key('qe.phone')), '01011112222');
    await tester.pump();
    await _pickOption(tester, 'qe.grade', 'qeGrade.option.SG-5');
    await tapVisible(tester, find.byKey(const Key('pending.complete')));
    // اسم مشابه: تأكيد صريح.
    expect(find.text('اسم مشابه موجود'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(crm.pendingUpdates.single.$2.gradeId, 'g-sg5');
    expect(crm.pendingCompletes, [('e1', false), ('e1', true)]);
    expect(find.text('فتح البطاقة'), findsOneWidget);
    expect(find.byKey(const Key('pending.empty')), findsOneWidget);
  });

  testWidgets('pending duplicate: appending to the existing record needs '
      'explicit confirmation, and a new role a second one', (tester) async {
    final crm = FakeCrmRepository()
      ..mergeNeedsRole = true
      ..pendingStore.add(
        _pending(
          status: 'duplicate',
          kind: 'supplier',
          phone: '01001234567',
          grade: 'SG-5',
          issues: const [],
          duplicateOfId: 'party-1',
          duplicateName: 'شركة النور للصناعات البلاستيكية',
        ),
      );
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickPending,
      user: _secretary,
    );
    await tapVisible(tester, find.byKey(const Key('pending.row.e1')));
    expect(find.byKey(const Key('pending.duplicateNote')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pending.merge')));
    expect(crm.pendingMerges, isEmpty, reason: 'لا دمج قبل التأكيد');
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(find.text('إضافة دور'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(crm.pendingMerges, [('e1', false), ('e1', true)]);
  });

  testWidgets('pending list exports to Excel, PDF and print', (tester) async {
    final docs = FakeDocumentServices();
    final crm = FakeCrmRepository()..pendingStore.add(_pending());
    await pumpCrmApp(
      tester,
      crm: crm,
      documents: docs,
      at: CrmRoutes.quickPending,
      user: _secretary,
    );
    for (final f in ['Excel', 'PDF', 'طباعة']) {
      await tapVisible(tester, find.byKey(const Key('pending.export')));
      await tapVisible(tester, find.text(f).last);
    }
    expect(crm.exported, ['pending']);
    expect(docs.pdfs.single.rows.single[1], 'شركة الأمل');
    expect(docs.printed, hasLength(1));
  });

  testWidgets('export: preview counts, then Excel, PDF and print from the '
      'same query', (tester) async {
    final docs = FakeDocumentServices();
    final crm = FakeCrmRepository()
      ..exportResult = const ExportData(1, 1, [
        ExportItem(
          kind: 'customer',
          partyId: 'p1',
          name: 'شركة الأمل',
          phone: '01011112222',
          material: 'PP',
          grade: '129H',
        ),
        ExportItem(
          kind: 'supplier',
          partyId: 'p2',
          name: 'مورد الخليج',
          phone: '01122223333',
          material: 'PP',
          grade: '129H',
        ),
      ]);
    await pumpCrmApp(
      tester,
      crm: crm,
      documents: docs,
      at: CrmRoutes.quickEntry,
      user: _secretary,
    );
    await tapVisible(tester, find.text('تصدير البيانات'));
    await tapVisible(tester, find.byKey(const Key('export.audience.mixed')));
    await tapVisible(tester, find.byKey(const Key('export.scope.true')));
    await _pickOption(tester, 'export.material', 'exMaterial.option.PP');
    await _pickOption(
      tester,
      'export.grade',
      'exGrade.option.129H — مصنع تجريبي ب',
    );
    await tapVisible(tester, find.byKey(const Key('export.preview')));
    expect(crm.exportCalls.single, ('mixed', 'mat-pp', 'g-129h'));
    expect(find.text('عملاء: 1'), findsOneWidget);
    expect(find.text('موردون: 1'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('export.excel')));
    await tapVisible(tester, find.byKey(const Key('export.pdf')));
    await tapVisible(tester, find.byKey(const Key('export.print')));
    expect(crm.exported, ['export.mixed']);
    final pdf = docs.pdfs.single;
    expect(pdf.sections.map((s) => s.$1), ['العملاء (1)', 'الموردون (1)']);
    expect(pdf.sections.first.$2.single[1], '01011112222');
    expect(docs.printed, hasLength(1));
  });

  testWidgets('export: suppliers are hidden from users who cannot see them', (
    tester,
  ) async {
    await pumpCrmApp(tester, at: CrmRoutes.quickEntry, user: _customerExporter);
    await tapVisible(tester, find.text('تصدير البيانات'));
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('export.audience.supplier')),
    );
    expect(chip.onSelected, isNull);
  });

  testWidgets('batches: the manager undoes a batch and sees what was kept', (
    tester,
  ) async {
    final crm = FakeCrmRepository()
      ..batchList = [
        BatchSummary(
          id: 'b1',
          method: 'excel',
          audience: 'customer',
          fileName: 'عملاء.xlsx',
          rowCount: 3,
          created: 2,
          pending: 1,
          duplicate: 0,
          failed: 0,
          status: 'processed',
          createdAt: DateTime(2026, 11, 1),
          createdByName: 'السكرتارية',
        ),
      ];
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickBatches,
      user: _manager,
    );
    await tapVisible(tester, find.byKey(const Key('batch.undo.b1')));
    await tapVisible(tester, find.byKey(const Key('confirm.ok')));
    expect(crm.undone, ['b1']);
    expect(find.textContaining('شركة معدلة'), findsOneWidget);
  });

  testWidgets('batches: undo is for the manager only', (tester) async {
    final crm = FakeCrmRepository()
      ..batchList = [
        BatchSummary(
          id: 'b1',
          rowCount: 1,
          created: 1,
          pending: 0,
          duplicate: 0,
          failed: 0,
          createdAt: DateTime(2026, 11, 1),
        ),
      ];
    await pumpCrmApp(
      tester,
      crm: crm,
      at: CrmRoutes.quickBatches,
      user: _secretary,
    );
    expect(find.byKey(const Key('batch.b1')), findsOneWidget);
    expect(find.byKey(const Key('batch.undo.b1')), findsNothing);
  });
}
