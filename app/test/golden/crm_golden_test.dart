@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/app/app.dart';
import 'package:qadisiyah/app/router.dart';
import 'package:qadisiyah/features/auth/application/auth_controller.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';
import 'package:qadisiyah/features/crm/application/crm_providers.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../helpers/crm_fakes.dart';
import '../helpers/test_app.dart';
import 'screens_golden_test.dart' show withShadows;

/// يفتح التطبيق على [path] ببيانات تجريبية ثم ينفذ [prepare].
Future<void> pumpCrmScreen(
  WidgetTester tester,
  String path, {
  Future<void> Function(WidgetTester)? prepare,
  Size size = referencePhone,
}) async {
  await loadAppFonts();
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          restored: const ActiveSession(testUser, offline: false),
        ),
      ),
      crmRepositoryProvider.overrideWithValue(FakeCrmRepository()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(child: QadisiyahApp()),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(container.read(routerProvider).push(path));
  await tester.pumpAndSettle();
  await prepare?.call(tester);
}

Future<void> _fillQuickAdd(
  WidgetTester tester, {
  required bool customer,
}) async {
  await tester.enterText(
    find.byKey(const Key('party.name')),
    customer
        ? 'شركة النور للصناعات البلاستيكية'
        : 'شركة الصفوة لمواد البلاستيك',
  );
  await tester.enterText(find.byKey(const Key('party.phone')), '01001234567');
  await tester.tap(find.byKey(const Key('activity.act-factory')));
  await tester.ensureVisible(find.byKey(const Key('chips.add')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chips.add')));
  await tester.pumpAndSettle();
  for (final code in ['PP', 'HDPE', 'PVC']) {
    await tester.tap(find.byKey(Key('material.$code')));
  }
  await tester.tap(find.byKey(const Key('material.done')));
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.drag(find.byType(ListView).first, const Offset(0, 600));
  await tester.pumpAndSettle();
}

Future<void> _fillOrder(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('record.addLine')));
  await tester.pumpAndSettle();
  for (final (i, label, qty) in [
    (0, 'PVC (SG-5)', '3.00'),
    (1, 'HDPE (5502)', '1.00'),
  ]) {
    await tester.tap(find.byKey(Key('line.$i.material')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Key('line.$i.quantity')), qty);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

/// الشاشات المقابلة لتصميمات ص8 وص9.
final crmScreenStates =
    <String, (String, Future<void> Function(WidgetTester)?)>{
      'quick_add_customer': (
        CrmRoutes.newCustomer,
        (t) => _fillQuickAdd(t, customer: true),
      ),
      'quick_add_supplier': (
        CrmRoutes.newSupplier,
        (t) => _fillQuickAdd(t, customer: false),
      ),
      'customer_profile': (CrmRoutes.party('party-1'), null),
      'supplier_profile': (CrmRoutes.party('party-2'), null),
      'new_order': (CrmRoutes.newOrder('party-1'), _fillOrder),
      'new_contact': (
        CrmRoutes.newContact('party-1', channel: ContactChannel.call),
        (t) async {
          await t.tap(find.byKey(const Key('outcome.reached')));
          await t.pumpAndSettle();
        },
      ),
    };

void main() {
  for (final MapEntry(key: name, value: (path, prepare))
      in crmScreenStates.entries) {
    testWidgets(
      name,
      (tester) => withShadows(() async {
        await pumpCrmScreen(tester, path, prepare: prepare);
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/crm_${name}_390x844.png'),
        );
      }),
    );
  }

  testWidgets(
    'customer profile small screen',
    (tester) => withShadows(() async {
      await pumpCrmScreen(
        tester,
        CrmRoutes.party('party-1'),
        size: const Size(360, 640),
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/crm_customer_profile_360x640.png'),
      );
    }),
  );
}
