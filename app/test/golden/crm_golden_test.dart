@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/notifications/reminder_scheduler.dart';
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
      reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler()),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 28, 10)),
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
  for (final (material, choice) in [
    ('PP', 'spec.grade.PP500'),
    (customer ? 'HDPE' : 'PVC', customer ? 'spec.open' : 'spec.grade.SG-5'),
  ]) {
    await tester.ensureVisible(find.byKey(const Key('chips.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chips.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('spec.material.$material')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(Key(choice)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(choice)));
    await tester.pumpAndSettle();
    if (material == 'PP') {
      await tester.ensureVisible(find.byKey(const Key('spec.origin.SA')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spec.origin.SA')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('spec.done')));
    await tester.pumpAndSettle();
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.drag(find.byType(ListView).first, const Offset(0, 600));
  await tester.pumpAndSettle();
}

Future<void> _fillOrder(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('record.addLine')));
  await tester.pumpAndSettle();
  for (final (i, material, choice, qty) in [
    (0, 'PP', 'spec.grade.PP500', '3.00'),
    (1, 'HDPE', 'spec.open', '1.00'),
  ]) {
    await tester.tap(find.byKey(Key('line.$i.material')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('spec.material.$material')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(choice)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spec.done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Key('line.$i.quantity')), qty);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

/// الشاشات المقابلة لتصميمات ص8 وص9.
final crmScreenStates =
    <String, (String, Future<void> Function(WidgetTester)?)>{
      'customer_registration': (CrmRoutes.newCustomer, null),
      'customer_registration_middle': (
        CrmRoutes.newCustomer,
        (t) async {
          await t.drag(
            find.byKey(const Key('register.list')),
            const Offset(0, -640),
          );
          await t.pumpAndSettle();
        },
      ),
      'customer_registration_bottom': (
        CrmRoutes.newCustomer,
        (t) async {
          await t.drag(
            find.byKey(const Key('register.list')),
            const Offset(0, -3000),
          );
          await t.pumpAndSettle();
        },
      ),
      'quick_add_supplier': (
        CrmRoutes.newSupplier,
        (t) => _fillQuickAdd(t, customer: false),
      ),
      'customer_profile': (CrmRoutes.party('party-1'), null),
      'supplier_profile': (CrmRoutes.party('party-2'), null),
      'new_order': (CrmRoutes.newOrder('party-1'), _fillOrder),
      'material_picker': (
        CrmRoutes.newSupplier,
        (t) async {
          await t.ensureVisible(find.byKey(const Key('chips.add')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('chips.add')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('spec.material.PP')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('spec.grade.PP500')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('spec.origin.SA')));
          await t.pumpAndSettle();
        },
      ),
      'catalog': (CrmRoutes.catalog, null),
      'registry': (CrmRoutes.registry, null),
      'customer_details': (
        CrmRoutes.party('party-1'),
        (t) async {
          await t.tap(find.byKey(const Key('tab.3')));
          await t.pumpAndSettle();
        },
      ),
      'supplier_details': (
        CrmRoutes.party('party-2'),
        (t) async {
          await t.tap(find.byKey(const Key('tab.3')));
          await t.pumpAndSettle();
          await t.drag(find.byType(ListView).first, const Offset(0, -520));
          await t.pumpAndSettle();
        },
      ),
      'add_location': (
        CrmRoutes.party('party-1'),
        (t) async {
          await t.tap(find.byKey(const Key('tab.3')));
          await t.pumpAndSettle();
          await t.ensureVisible(find.byKey(const Key('location.add')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('location.add')));
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('location.url')),
            'https://maps.google.com/?q=30.2950,31.7420',
          );
          await t.enterText(
            find.byKey(const Key('location.address')),
            'المنطقة الصناعية الثالثة، العاشر من رمضان',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pumpAndSettle();
        },
      ),
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
