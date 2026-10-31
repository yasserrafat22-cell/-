import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

/// تبويب «المرفقات» في بطاقة العميل.
Future<void> _openAttachments(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('tab.4')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('tab.4')));
  await tester.pumpAndSettle();
}

Future<void> _openDetails(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tab.3')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('supplier files show the TDS with its grade and can be shared '
      'and viewed', (tester) async {
    final files = FakeFileServices();
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.party('party-2'),
      files: files,
    );
    await _openDetails(tester);
    await tester.scrollUntilVisible(find.text('Technical Data Sheets'), 200);

    expect(find.textContaining('TDS-5502.pdf • 1.2 MB'), findsOneWidget);
    expect(find.byKey(const Key('attachment.image.att-photo')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('attachment.share.att-tds')));
    expect(crm.shared.single, 'file:/tmp/att-tds/TDS-5502.pdf');
    await tapVisible(tester, find.byKey(const Key('attachment.view.att-tds')));
    expect(files.opened.single, '/tmp/att-tds/TDS-5502.pdf');
  });

  testWidgets('a TDS is uploaded for the chosen exact grade', (tester) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-2'));
    await _openDetails(tester);
    await tapVisible(tester, find.byKey(const Key('attachment.add')));
    await tester.tap(
      find.byKey(const Key('attachment.kind.technicalDataSheet')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment.spec.g-5502')));
    await tester.pumpAndSettle();

    expect(crm.uploads.single, {
      'partyId': 'party-2',
      'kind': AttachmentKind.technicalDataSheet,
      'fileName': 'sheet.pdf',
      'gradeId': 'g-5502',
      'materialId': 'mat-hdpe',
    });
  });

  testWidgets('a TDS cannot use a grade whose manufacturer is unknown', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-2'));
    await _openDetails(tester);
    await tapVisible(tester, find.byKey(const Key('attachment.add')));
    await tester.tap(
      find.byKey(const Key('attachment.kind.technicalDataSheet')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment.otherGrade')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spec.material.PVC')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('spec.grade.SG-5')));
    await tapVisible(tester, find.byKey(const Key('spec.done')));

    expect(find.textContaining('محدد الشركة المصنّعة'), findsOneWidget);
    expect(crm.uploads, isEmpty);
  });

  testWidgets('customers get logo and other files only; big files are '
      'refused before upload', (tester) async {
    final files = FakeFileServices()..nextSize = 11 * 1024 * 1024;
    final crm = await pumpCrmApp(
      tester,
      at: CrmRoutes.party('party-1'),
      files: files,
    );
    await _openAttachments(tester);
    await tapVisible(tester, find.byKey(const Key('attachment.add')));
    expect(
      find.byKey(const Key('attachment.kind.technicalDataSheet')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('attachment.kind.logo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment.gallery')));
    await tester.pumpAndSettle();

    expect(find.text('الحد الأقصى للصورة هو 10MB'), findsOneWidget);
    expect(crm.uploads, isEmpty);
  });
}
