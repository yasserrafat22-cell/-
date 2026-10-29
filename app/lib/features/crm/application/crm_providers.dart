import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../data/crm_repository.dart';
import '../domain/crm_models.dart';

/// الوقت الحالي؛ يُستبدل في الاختبارات بتاريخ ثابت حتى لا تتغير الصور المرجعية يوميًا.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    dio: ref.watch(dioProvider),
    auth: ref.watch(authRepositoryProvider),
    onSessionEnded: (reason) =>
        ref.read(authControllerProvider.notifier).sessionEnded(reason),
  ),
);

final crmRepositoryProvider = Provider<CrmRepository>(
  (ref) => CrmRepository(ref.watch(apiClientProvider)),
);

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
