import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/offline/offline_store.dart';
import 'package:qadisiyah/core/storage/secure_store.dart';
import 'package:qadisiyah/features/crm/application/sync_controller.dart';
import 'package:qadisiyah/core/device/device_location.dart';
import 'package:qadisiyah/core/device/file_services.dart';
import 'package:qadisiyah/core/device/share_service.dart';
import 'package:qadisiyah/app/app.dart';
import 'package:qadisiyah/app/router.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/features/auth/application/auth_controller.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';
import 'package:qadisiyah/features/crm/application/crm_providers.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';
import 'package:qadisiyah/features/crm/presentation/new_contact_screen.dart';
import 'package:qadisiyah/features/crm/presentation/party_profile_screen.dart';
import 'package:qadisiyah/features/crm/presentation/quick_add_party_screen.dart';

import '../../helpers/crm_fakes.dart';
import '../../helpers/test_app.dart';

late ProviderContainer container;

Future<FakeCrmRepository> pumpCrmApp(
  WidgetTester tester, {
  FakeCrmRepository? crm,
  String? at,
  FakeFileServices? files,
  AuthUser user = testUser,
}) async {
  await loadAppFonts();
  tester.view
    ..physicalSize = const Size(390, 900) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final repo = crm ?? FakeCrmRepository();
  container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(restored: ActiveSession(user, offline: false)),
      ),
      crmRepositoryProvider.overrideWithValue(repo),
      offlineStoreProvider.overrideWithValue(
        OfflineStore(keys: InMemorySecureStore(), storage: MemoryBlobStorage()),
      ),
      shareServiceProvider.overrideWithValue(FakeShareService(repo.shared)),
      deviceLocationProvider.overrideWithValue(const FakeDeviceLocation()),
      fileServicesProvider.overrideWithValue(files ?? FakeFileServices()),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 28, 10)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const QadisiyahApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (at != null) {
    unawaited(container.read(routerProvider).push(at));
    await tester.pumpAndSettle();
  }
  return repo;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('quick registration', () {
    testWidgets('home customers tile opens quick customer registration', (
      tester,
    ) async {
      await pumpCrmApp(tester);
      await tester.tap(find.byKey(const Key('home.customers')));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAddPartyScreen), findsOneWidget);
      expect(find.text('إضافة عميل جديد'), findsOneWidget);
      expect(find.text('محول بلاستيك'), findsOneWidget);
      expect(find.text('مستورد'), findsNothing);
      // المندوب: المسؤول هو نفسه وتاريخ اليوم، دون اختيار.
      expect(find.byKey(const Key('party.fixedOwner')), findsOneWidget);
      expect(
        find.textContaining('أحمد محمد', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const Key('party.representative')), findsNothing);
    });

    testWidgets('supplier registration shows supplier types', (tester) async {
      await pumpCrmApp(tester);
      await tester.tap(find.byKey(const Key('home.suppliers')));
      await tester.pumpAndSettle();

      expect(find.text('إضافة مورد جديد'), findsOneWidget);
      expect(find.text('مستورد'), findsOneWidget);
      expect(find.text('محول بلاستيك'), findsNothing);
      expect(find.text('الخامات المتاحة'), findsOneWidget);
    });

    testWidgets('missing required fields are flagged and nothing is sent', (
      tester,
    ) async {
      final crm = await pumpCrmApp(tester, at: CrmRoutes.newCustomer);
      await tapVisible(tester, find.byKey(const Key('crm.save')));

      expect(find.text('اكتب اسم العميل'), findsOneWidget);
      expect(find.text('رقم الهاتف مطلوب'), findsOneWidget);
      expect(find.text('اختر نوع النشاط'), findsOneWidget);
      expect(crm.created, isEmpty);
    });

    testWidgets(
      'saving a customer sends the quick fields and opens the profile',
      (tester) async {
        final crm = await pumpCrmApp(tester, at: CrmRoutes.newCustomer);
        await tester.enterText(
          find.byKey(const Key('party.name')),
          'شركة الأمل للبلاستيك',
        );
        await tester.enterText(
          find.byKey(const Key('party.phone')),
          '01009876543',
        );
        await tester.tap(find.byKey(const Key('activity.act-factory')));
        await tapVisible(tester, find.byKey(const Key('chips.add')));
        await tester.tap(find.byKey(const Key('spec.material.PP')));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byKey(const Key('spec.grade.PP500')));
        await tapVisible(tester, find.byKey(const Key('spec.origin.SA')));
        await tapVisible(tester, find.byKey(const Key('spec.done')));
        await tapVisible(tester, find.byKey(const Key('chips.add')));
        await tester.tap(find.byKey(const Key('spec.material.HDPE')));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byKey(const Key('spec.open')));
        await tapVisible(tester, find.byKey(const Key('spec.done')));
        expect(find.text('PP500'), findsOneWidget);
        expect(find.text('أي شركة'), findsOneWidget);
        await tapVisible(tester, find.byKey(const Key('crm.save')));

        final sent = crm.created.single;
        expect(sent.name, 'شركة الأمل للبلاستيك');
        expect(sent.phone, '01009876543');
        expect(sent.activityId, 'act-factory');
        expect(sent.representativeId, 'rep-me');
        expect(sent.toJson()['interests'], [
          {
            'materialId': 'mat-pp',
            'gradeId': 'g-pp500',
            'originCountryId': 'c-sa',
            'openSpec': false,
          },
          {
            'materialId': 'mat-hdpe',
            'gradeId': null,
            'originCountryId': null,
            'openSpec': true,
          },
        ]);
        expect(find.byType(PartyProfileScreen), findsOneWidget);
        expect(find.text('عميل جديد'), findsWidgets);
      },
    );

    testWidgets('retrying after a connection error reuses the same id', (
      tester,
    ) async {
      final crm = FakeCrmRepository()..createError = ApiException.network;
      await pumpCrmApp(tester, crm: crm, at: CrmRoutes.newCustomer);
      await tester.enterText(find.byKey(const Key('party.name')), 'شركة الأمل');
      await tester.enterText(
        find.byKey(const Key('party.phone')),
        '01009876543',
      );
      await tester.tap(find.byKey(const Key('activity.act-trader')));
      await tapVisible(tester, find.byKey(const Key('crm.save')));
      expect(find.textContaining('تعذر الاتصال'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      crm.createError = null;
      await tapVisible(tester, find.byKey(const Key('crm.save')));
      final firstId = crm.created.single.id;
      expect(firstId, isNotEmpty);
      expect(crm.parties.containsKey(firstId), isTrue);
    });

    testWidgets(
      'duplicate phone offers adding the supplier role to the existing company',
      (tester) async {
        final crm = FakeCrmRepository()
          ..createError = const ApiException(
            'party.duplicate_phone',
            'رقم الهاتف مسجل بالفعل باسم «شركة النور للصناعات البلاستيكية»',
            data: {
              'partyId': 'party-1',
              'name': 'شركة النور',
              'isCustomer': true,
              'isSupplier': false,
            },
          );
        await pumpCrmApp(tester, crm: crm, at: CrmRoutes.newSupplier);
        await tester.enterText(find.byKey(const Key('party.name')), 'النور');
        await tester.enterText(
          find.byKey(const Key('party.phone')),
          '01001234567',
        );
        await tester.tap(find.byKey(const Key('activity.act-importer')));
        await tapVisible(tester, find.byKey(const Key('crm.save')));

        expect(find.text('رقم مسجل بالفعل'), findsOneWidget);
        await tester.tap(find.byKey(const Key('duplicate.addRole')));
        await tester.pumpAndSettle();

        expect(crm.roles, [('party-1', false)]);
        expect(find.byType(PartyProfileScreen), findsOneWidget);
      },
    );
  });

  group('profile', () {
    testWidgets('overview shows values derived on the server', (tester) async {
      await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));

      expect(find.text('بيانات العميل'), findsOneWidget);
      expect(find.text('15 أكتوبر 2026'), findsOneWidget);
      expect(find.text('3 طن'), findsOneWidget);
      expect(find.text('24 أكتوبر 2026'), findsOneWidget);
      expect(find.text('PP , HDPE'), findsOneWidget);
      expect(find.text('عميل نشط'), findsOneWidget);
      expect(find.text('نشط'), findsOneWidget);
      expect(find.text('القاهرة - المنطقة الصناعية'), findsOneWidget);
      expect(find.text('المندوب: أحمد محمد'), findsOneWidget);
    });

    testWidgets('orders and contacts tabs list records', (tester) async {
      await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
      await tester.tap(find.byKey(const Key('tab.1')));
      await tester.pumpAndSettle();
      expect(find.text('طلب مؤكد'), findsOneWidget);
      expect(find.text('SG-5'), findsOneWidget);
      expect(find.text('الشركة غير محددة'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab.2')));
      await tester.pumpAndSettle();
      expect(find.text('اتصال — تم التواصل بنجاح'), findsOneWidget);
      expect(find.text('طلب عرض سعر لخامة PVC'), findsOneWidget);
    });

    testWidgets('changing an order stage asks for confirmation', (
      tester,
    ) async {
      final crm = await pumpCrmApp(tester, at: CrmRoutes.party('party-1'));
      await tester.tap(find.byKey(const Key('tab.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('تغيير الحالة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تغيير إلى: قيد التنفيذ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      expect(crm.stageChanges, [('order-1', OrderStage.inProgress)]);
    });

    testWidgets('supplier details list products and latest prices', (
      tester,
    ) async {
      await pumpCrmApp(tester, at: CrmRoutes.party('party-2'));
      expect(find.text('بيانات المورد'), findsOneWidget);
      expect(find.text('آخر توريد'), findsOneWidget);
      expect(find.byKey(const Key('tab.4')), findsNothing);
      await tester.tap(find.byKey(const Key('tab.3')));
      await tester.pumpAndSettle();
      expect(find.text('SG-5'), findsOneWidget);
      expect(find.text('الشركة غير محددة'), findsOneWidget);
      expect(find.textContaining('آخر سعر: 42000 EGP/طن'), findsOneWidget);
    });

    testWidgets('read-only users see no edit or record buttons', (
      tester,
    ) async {
      await pumpCrmApp(
        tester,
        crm: FakeCrmRepository(parties: [sampleCustomer(canEdit: false)]),
        at: CrmRoutes.party('party-1'),
      );
      expect(find.byKey(const Key('profile.newRecord')), findsNothing);
      expect(find.byKey(const Key('profile.newContact')), findsNothing);
      expect(find.byKey(const Key('profile.menu')), findsNothing);
      expect(find.byKey(const Key('profile.call')), findsOneWidget);
    });
  });

  group('records', () {
    testWidgets('new order sends lines with grade, unit and stage', (
      tester,
    ) async {
      final crm = await pumpCrmApp(tester, at: CrmRoutes.newOrder('party-1'));

      await tapVisible(tester, find.byKey(const Key('crm.save')));
      expect(find.byKey(const Key('record.error')), findsOneWidget);
      expect(crm.ordersSent, isEmpty);

      await tester.tap(find.byKey(const Key('line.0.material')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spec.material.PVC')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('spec.grade.SG-5')));
      expect(find.text('الشركة غير محددة'), findsWidgets);
      await tapVisible(tester, find.byKey(const Key('spec.done')));
      await tester.enterText(find.byKey(const Key('line.0.quantity')), '3');
      await tapVisible(
        tester,
        find.byKey(const Key('stage.OrderStage.confirmed')),
      );
      await tapVisible(tester, find.byKey(const Key('crm.save')));

      final order = crm.ordersSent.single;
      expect(order['customerId'], 'party-1');
      expect(order['stage'], OrderStage.confirmed);
      expect(order['lines'], [
        {
          'materialId': 'mat-pvc',
          'gradeId': 'g-sg5',
          'originCountryId': null,
          'openSpec': false,
          'quantity': 3.0,
          'unitId': 'unit-ton',
        },
      ]);
    });

    testWidgets('new supply records received material', (tester) async {
      final crm = await pumpCrmApp(tester, at: CrmRoutes.newSupply('party-2'));
      expect(find.text('تسجيل توريد جديد'), findsOneWidget);
      await tester.tap(find.byKey(const Key('line.0.material')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spec.material.HDPE')));
      await tester.pumpAndSettle();
      // التوريد بمواصفات محددة فقط؛ لا خيار «أي شركة».
      expect(find.byKey(const Key('spec.open')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('spec.done')));
      await tester.enterText(find.byKey(const Key('line.0.quantity')), '5');
      await tapVisible(tester, find.byKey(const Key('crm.save')));

      expect(crm.suppliesSent.single['status'], SupplyStatus.received);
    });

    testWidgets('contact requires an outcome and keeps the launched channel', (
      tester,
    ) async {
      final crm = await pumpCrmApp(
        tester,
        at: CrmRoutes.newContact('party-1', channel: ContactChannel.whatsApp),
      );
      expect(find.byType(NewContactScreen), findsOneWidget);
      // نتائج الموردين فقط لا تظهر لعميل.
      expect(find.text('تم الاتفاق على المتابعة'), findsNothing);
      expect(find.text('طلب عرض سعر'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('crm.save')));
      expect(find.text('اختر نتيجة التواصل'), findsOneWidget);

      await tester.tap(find.byKey(const Key('outcome.reached')));
      await tester.enterText(
        find.byKey(const Key('contact.notes')),
        'تم إرسال العرض',
      );
      await tapVisible(tester, find.byKey(const Key('crm.save')));

      final sent = crm.interactionsSent.single;
      expect(sent['channel'], ContactChannel.whatsApp);
      expect(sent['outcomeId'], 'out-reached');
      expect(sent['notes'], 'تم إرسال العرض');
      expect(sent['remind'], isFalse);
    });

    testWidgets('editing details sends the completed address', (tester) async {
      final crm = await pumpCrmApp(
        tester,
        at: CrmRoutes.editDetails('party-1'),
      );
      await tester.enterText(
        find.byKey(const Key('edit.email')),
        'info@alnour.example',
      );
      await tester.enterText(find.byKey(const Key('edit.address')), 'شارع 10');
      await tapVisible(tester, find.byKey(const Key('crm.save')));

      final update = crm.updates.single;
      expect(update.email, 'info@alnour.example');
      expect(update.addressLine, 'شارع 10');
      expect(update.region, 'المنطقة الصناعية');
      expect(update.phone, '01001234567');
    });

    testWidgets('a concurrent edit is reported instead of overwritten', (
      tester,
    ) async {
      final crm = FakeCrmRepository()
        ..updateError = const ApiException(
          'concurrency.stale',
          'تم تعديل هذا السجل من مستخدم آخر. حدّث البيانات ثم أعد المحاولة.',
        );
      await pumpCrmApp(tester, crm: crm, at: CrmRoutes.editDetails('party-1'));
      await tapVisible(tester, find.byKey(const Key('crm.save')));
      expect(find.textContaining('تم تعديل هذا السجل'), findsOneWidget);
      expect(crm.updates, isEmpty);
    });
  });
}
