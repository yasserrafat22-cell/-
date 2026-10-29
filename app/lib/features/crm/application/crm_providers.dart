import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/device/file_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/notifications/reminder_scheduler.dart';
import '../../auth/application/auth_controller.dart';
import '../data/crm_repository.dart';
import '../domain/crm_models.dart';
import '../presentation/crm_routes.dart';
import 'sync_controller.dart';

/// الوقت الحالي؛ يُستبدل في الاختبارات بتاريخ ثابت حتى لا تتغير الصور المرجعية يوميًا.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// المدير والسكرتارية والمديرون يحددون المسؤول وتاريخ السجل؛ المندوب يُثبت له
/// نفسه وتاريخ اليوم (والسيرفر يفرض ذلك أيضًا).
final canAssignProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  final user = auth is Authenticated ? auth.user : null;
  return user != null &&
      (user.can('records.assign') || user.can('records.manage'));
});

/// الموردون (القوائم والبحث والمفضلة) لمن يطّلع على الكل فقط؛ لا يراهم المندوب.
final canSeeSuppliersProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth is Authenticated && auth.user.can('suppliers.view_all');
});

/// النسخة الاحتياطية الكاملة: للمدير العام فقط.
final canBackupProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth is Authenticated && auth.user.can('backup.manage');
});

/// الإسناد للمدير العام ولمديري الأقسام داخل نطاقهم.
final canTeamAssignProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth is Authenticated &&
      (auth.user.can('team.assign') || auth.user.can('records.manage'));
});

/// المدير العام: تعديل وحذف واستعادة البيانات المحفوظة.
final canManageProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth is Authenticated && auth.user.can('records.manage');
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    dio: ref.watch(dioProvider),
    auth: ref.watch(authRepositoryProvider),
    onSessionEnded: (reason) =>
        ref.read(authControllerProvider.notifier).sessionEnded(reason),
  ),
);

final crmRepositoryProvider = Provider<CrmRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  return CrmRepository(
    ref.watch(apiClientProvider),
    offline: ref.watch(offlineStoreProvider),
    userId: auth is Authenticated ? auth.user.id : null,
    files: ref.watch(fileServicesProvider),
  );
});

/// القوائم الأساسية تُحمّل مرة لكل جلسة.
final referenceDataProvider = FutureProvider<ReferenceData>(
  (ref) => ref.watch(crmRepositoryProvider).reference(),
);

final partyProvider = FutureProvider.autoDispose.family<PartyDetail, String>(
  (ref, id) => ref.watch(crmRepositoryProvider).party(id),
);

final interactionsProvider = FutureProvider.autoDispose
    .family<List<InteractionItem>, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).interactions(id),
    );

final ordersProvider = FutureProvider.autoDispose
    .family<List<OrderItem>, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).orders(id),
    );

final suppliesProvider = FutureProvider.autoDispose
    .family<List<SupplyItem>, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).supplies(id),
    );

/// يحدّث ملف الطرف وكل سجلاته بعد أي تسجيل جديد.
void refreshParty(WidgetRef ref, String id) {
  ref
    ..invalidate(partyProvider(id))
    ..invalidate(interactionsProvider(id))
    ..invalidate(ordersProvider(id))
    ..invalidate(suppliesProvider(id))
    ..invalidate(historyProvider(id))
    ..invalidate(locationsProvider(id))
    ..invalidate(contactsProvider(id))
    ..invalidate(followUpsProvider)
    ..invalidate(attachmentsProvider(id))
    ..invalidate(registryProvider);
}

final historyProvider = FutureProvider.autoDispose
    .family<List<HistoryEntry>, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).history(id),
    );

/// الصفحة الأولى من نتائج «السجل» لكل مجموعة فلاتر.
final registryProvider = FutureProvider.autoDispose
    .family<RegistryPage, RegistryFilter>(
      (ref, filter) => ref.watch(crmRepositoryProvider).registry(filter),
    );

final contactsProvider = FutureProvider.autoDispose
    .family<List<PartyContact>, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).contacts(id),
    );

final locationsProvider = FutureProvider.autoDispose
    .family<List<PartyLocation>, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).locations(id),
    );

final attachmentsProvider = FutureProvider.autoDispose
    .family<List<AttachmentItem>, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).attachments(id),
    );

/// محتوى المرفق (للصور المصغرة والشعار) يبقى في الذاكرة أثناء عرضه فقط.
final gradeFileBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).gradeFileBytes(id),
    );

final attachmentBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).attachmentBytes(id),
    );

/// المتابعات المفتوحة (جرس الرئيسية). عند كل تحميل تُعاد جدولة إشعارات الهاتف:
/// فقط ما فُعّل له «تذكير بالمتابعة» وكان المستخدم مسؤولًا عنه، والموعد لم يمر.
final followUpsProvider = FutureProvider.autoDispose<List<FollowUpItem>>((
  ref,
) async {
  final items = await ref.watch(crmRepositoryProvider).followUps();
  final now = ref.read(clockProvider)();
  final reminders = [
    for (final f in items)
      if (f.remind && f.mine && f.dueAt.isAfter(now))
        Reminder(
          key: f.interactionId,
          at: f.dueAt,
          title: 'متابعة ${f.partyName}',
          partyId: f.partyId,
        ),
  ];
  final scheduler = ref.read(reminderSchedulerProvider);
  final router = ref.read(routerProvider);
  try {
    await scheduler.init((partyId) => router.push(CrmRoutes.party(partyId)));
    if (reminders.isNotEmpty) await scheduler.ensurePermission();
    await scheduler.replaceAll(reminders);
  } on Object {
    // تعذر الإشعار لا يمنع عرض المتابعات في التطبيق.
  }
  return items;
});

/// مطابقة احتياجات العميل بالموردين (للإدارة فقط).
final supplierMatchesProvider = FutureProvider.autoDispose
    .family<SupplierMatches, String>(
      (ref, id) => ref.watch(crmRepositoryProvider).supplierMatches(id),
    );

final reportSummaryProvider = FutureProvider.autoDispose<ReportSummary>(
  (ref) => ref.watch(crmRepositoryProvider).reportSummary(),
);
