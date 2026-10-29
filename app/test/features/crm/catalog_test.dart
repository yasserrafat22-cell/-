import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../../helpers/crm_fakes.dart';
import 'crm_flow_test.dart' show pumpCrmApp, tapVisible;

Future<void> _openPicker(WidgetTester tester, String material) async {
  await tapVisible(tester, find.byKey(const Key('chips.add')));
  await tester.tap(find.byKey(Key('spec.material.$material')));
  await tester.pumpAndSettle();
}

void main() {
  group('material picker', () {
    testWidgets('lists grades with their manufacturer and filters by it', (
      tester,
    ) async {
      await pumpCrmApp(tester, at: CrmRoutes.newCustomer);
      await _openPicker(tester, 'PP');

      expect(find.text('PP500'), findsOneWidget);
      expect(find.text('مصنع تجريبي أ'), findsOneWidget);
      expect(find.text('بانتظار التحقق'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('spec.search')), 'تجريبي ب');
      await tester.pumpAndSettle();
      expect(find.text('129H'), findsOneWidget);
      expect(find.text('PP500'), findsNothing);
    });

    testWidgets('a missing grade is added under its manufacturer', (
      tester,
    ) async {
      final crm = await pumpCrmApp(tester, at: CrmRoutes.newCustomer);
      await _openPicker(tester, 'PP');
      await tapVisible(tester, find.byKey(const Key('spec.addGrade')));
      await tester.enterText(
        find.byKey(const Key('grade.maker')),
        'مصنع تجريبي أ',
      );
      await tester.enterText(find.byKey(const Key('grade.code')), 'NEW-1');
      await tapVisible(tester, find.byKey(const Key('grade.save')));

      expect(crm.gradesCreated.single, {
        'materialId': 'mat-pp',
        'manufacturerId': 'man-a',
        'code': 'NEW-1',
        'confirmSimilar': false,
      });
    });

    testWidgets('the same code from another manufacturer needs confirmation', (
      tester,
    ) async {
      final crm = FakeCrmRepository()
        ..createGradeError = const ApiException(
          'catalog.similar_grade',
          'يوجد Grade بنفس الكود',
          data: [
            {
              'id': 'g-129h',
              'materialId': 'mat-pp',
              'materialCode': 'PP',
              'code': '129H',
              'manufacturerId': 'man-b',
              'manufacturerName': 'مصنع تجريبي ب',
            },
          ],
        );
      await pumpCrmApp(tester, crm: crm, at: CrmRoutes.newCustomer);
      await _openPicker(tester, 'PP');
      await tapVisible(tester, find.byKey(const Key('spec.addGrade')));
      await tester.enterText(
        find.byKey(const Key('grade.maker')),
        'مصنع تجريبي أ',
      );
      await tester.enterText(find.byKey(const Key('grade.code')), '129 H');
      await tapVisible(tester, find.byKey(const Key('grade.save')));

      expect(find.text('يوجد Grade بنفس الكود'), findsOneWidget);
      expect(find.text('مصنع تجريبي ب'), findsWidgets);
      await tapVisible(tester, find.byKey(const Key('grade.confirmNew')));
      expect(crm.gradesCreated.single['confirmSimilar'], isTrue);
    });
  });

  testWidgets('a customer material is added without dropping existing ones', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
    await tester.tap(find.byKey(const Key('tab.3')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('profile.addMaterial')));
    await tester.tap(find.byKey(const Key('spec.material.PVC')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('spec.done')));

    expect(crm.interestsSet.single, [
      const SpecChoice(
        materialId: 'mat-pp',
        gradeId: 'g-pp500',
        originId: 'c-sa',
      ),
      const SpecChoice(materialId: 'mat-hdpe', open: true),
      const SpecChoice(materialId: 'mat-pvc'),
    ]);
  });

  testWidgets('catalog lists pending grades and the admin verifies them', (
    tester,
  ) async {
    final crm = await pumpCrmApp(tester, at: CrmRoutes.catalog);
    expect(find.text('بانتظار التحقق (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab.2')));
    await tester.pumpAndSettle();
    expect(find.text('MARLEX 030'), findsOneWidget);
    expect(find.textContaining('أضافه أحمد محمد'), findsOneWidget);
    await tapVisible(
      tester,
      find.byKey(const Key('catalog.verify.MARLEX 030')),
    );
    expect(crm.verified, ['g-m030']);
  });

  testWidgets('a manufacturer is added from the catalog dialog', (
    tester,
  ) async {
    await pumpCrmApp(tester, at: CrmRoutes.catalog);
    await tester.tap(find.byKey(const Key('tab.1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog.addMaker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('dialog.field.0')),
      'مصنع جديد',
    );
    await tester.tap(find.byKey(const Key('dialog.confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dialog.field.0')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
