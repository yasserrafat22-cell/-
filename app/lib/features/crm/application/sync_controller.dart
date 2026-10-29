import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/offline/offline_store.dart';
import '../../auth/application/auth_controller.dart';
import 'crm_providers.dart';

/// قاعدة البيانات المحلية المشفرة (نسخ للعرض دون اتصال + طابور المزامنة).
final offlineStoreProvider = Provider<OfflineStore>(
  (ref) => OfflineStore(keys: ref.watch(secureStoreProvider)),
);

/// حالة السجل كما تظهر للمستخدم.
enum RecordSync {
  /// أُنشئ على الجهاز ولم يُرسل بعد.
  savedLocally,

  /// له عمليات محفوظة بانتظار الإرسال.
  pending,

  /// رفض السيرفر عملية له وتحتاج قرارًا.
  needsReview,

  /// كل ما عليه وصل للسيرفر.
  synced,
}

class SyncState {
  const SyncState({this.ops = const [], this.syncing = false, this.message});

  final List<PendingOp> ops;
  final bool syncing;

  /// نتيجة آخر مزامنة يدوية (لعرضها مرة).
  final String? message;

  int get pending => ops.where((o) => o.status == PendingStatus.pending).length;
  int get needsReview =>
      ops.where((o) => o.status == PendingStatus.needsReview).length;

  RecordSync of(String partyId) {
    final mine = ops.where((o) => o.partyId == partyId);
    if (mine.isEmpty) return RecordSync.synced;
    if (mine.any((o) => o.status == PendingStatus.needsReview)) {
      return RecordSync.needsReview;
    }
    if (mine.any((o) => o.kind == 'party.create')) {
      return RecordSync.savedLocally;
    }
    return RecordSync.pending;
  }
}

/// المزامنة: عند فتح التطبيق، عند العودة إليه، وبزر «مزامنة الآن».
class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() {
    final sub = ref.watch(offlineStoreProvider).changes.listen((_) => reload());
    ref.onDispose(sub.cancel);
    // عند فتح التطبيق: إن وُجدت بيانات محفوظة تُرسل تلقائيًا.
    Future.microtask(syncIfPending);
    return const SyncState();
  }

  Future<void> syncIfPending() async {
    await reload();
    if (ref.mounted && state.pending > 0) await syncNow(quiet: true);
  }

  Future<void> reload() async {
    final ops = await ref.read(crmRepositoryProvider).pendingOps();
    if (!ref.mounted) return;
    state = SyncState(ops: ops, syncing: state.syncing, message: state.message);
  }

  Future<void> syncNow({bool quiet = false}) async {
    if (state.syncing) return;
    state = SyncState(ops: state.ops, syncing: true);
    String? message;
    try {
      final result = await ref.read(crmRepositoryProvider).syncPending();
      final left = (await ref.read(crmRepositoryProvider).pendingOps())
          .where((o) => o.status == PendingStatus.pending)
          .length;
      message = switch ((result.sent, left, result.needsReview)) {
        (0, 0, 0) => 'لا توجد بيانات بانتظار المزامنة',
        (_, > 0, _) => 'تعذر الاتصال بالسيرفر. البيانات محفوظة على الجهاز',
        (_, _, > 0) =>
          'تمت مزامنة ${result.sent}، و${result.needsReview} تحتاج مراجعة',
        _ => 'تمت مزامنة ${result.sent}',
      };
      if (result.sent > 0) ref.invalidate(registryProvider);
    } on ApiException catch (e) {
      message = e.message;
    }
    if (!ref.mounted) return;
    state = SyncState(
      ops: state.ops,
      syncing: false,
      message: quiet ? null : message,
    );
    await reload();
  }

  Future<void> retry(PendingOp op, {bool confirmSimilar = false}) async {
    await ref
        .read(crmRepositoryProvider)
        .retryOp(op, confirmSimilar: confirmSimilar);
    await syncNow();
  }

  Future<void> discard(PendingOp op) async {
    await ref.read(crmRepositoryProvider).discardOp(op);
    await reload();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);
