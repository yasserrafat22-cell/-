import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/offline/offline_store.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../application/sync_controller.dart';
import '../domain/crm_format.dart';
import 'backup_actions.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';

/// شريط المزامنة في الشاشة الرئيسية: العدادات وزر «مزامنة الآن».
class SyncBar extends ConsumerStatefulWidget {
  const SyncBar({super.key});

  @override
  ConsumerState<SyncBar> createState() => _SyncBarState();
}

class _SyncBarState extends ConsumerState<SyncBar> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // عند العودة للتطبيق تُرسل البيانات المحفوظة تلقائيًا إن وُجد اتصال.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(syncControllerProvider.notifier).syncIfPending(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(syncControllerProvider);
    ref.listen(syncControllerProvider.select((s) => s.message), (_, message) {
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });
    final waiting = state.pending + state.needsReview;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        if (waiting > 0)
          ActionChip(
            key: const Key('sync.open'),
            avatar: Icon(
              state.needsReview > 0
                  ? Icons.error_outline_rounded
                  : Icons.cloud_upload_outlined,
              color: state.needsReview > 0
                  ? AppColors.error
                  : const Color(0xFF9A6200),
              size: 18,
            ),
            label: Text(
              [
                if (state.pending > 0) 'بانتظار المزامنة: ${state.pending}',
                if (state.needsReview > 0) 'تحتاج مراجعة: ${state.needsReview}',
              ].join(' • '),
            ),
            onPressed: () => context.push(CrmRoutes.sync),
          ),
        if (ref.watch(canBackupProvider))
          ActionChip(
            key: const Key('backup.full'),
            avatar: const Icon(Icons.backup_rounded, size: 18),
            label: const Text('حفظ نسخة'),
            onPressed: () => saveFullBackup(context, ref),
          ),
        ActionChip(
          key: const Key('sync.now'),
          avatar: state.syncing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded, size: 18),
          label: const Text('مزامنة الآن'),
          onPressed: state.syncing
              ? null
              : () => ref.read(syncControllerProvider.notifier).syncNow(),
        ),
      ],
    );
  }
}

/// حالة السجل: محفوظ على الجهاز / بانتظار المزامنة / يحتاج مراجعة / تمت المزامنة.
class SyncPill extends ConsumerWidget {
  const SyncPill({super.key, required this.partyId, this.hideSynced = false});

  final String partyId;
  final bool hideSynced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      syncControllerProvider.select((s) => s.of(partyId)),
    );
    if (hideSynced && status == RecordSync.synced) {
      return const SizedBox.shrink();
    }
    final (text, color, textColor) = switch (status) {
      RecordSync.savedLocally => (
        'محفوظ على الجهاز',
        const Color(0xFFFFF4E0),
        const Color(0xFF9A6200),
      ),
      RecordSync.pending => (
        'بانتظار المزامنة',
        const Color(0xFFFFF4E0),
        const Color(0xFF9A6200),
      ),
      RecordSync.needsReview => (
        'يحتاج مراجعة',
        const Color(0xFFFDE2E1),
        AppColors.error,
      ),
      RecordSync.synced => (
        'تمت المزامنة',
        const Color(0xFFDFF3D3),
        AppColors.greenDark,
      ),
    };
    return Pill(
      text,
      key: Key('sync.status.${status.name}'),
      color: color,
      textColor: textColor,
    );
  }
}

/// العمليات المحفوظة على الجهاز: ما ينتظر الإرسال وما رفضه السيرفر مع سببه.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  Future<void> _discard(
    BuildContext context,
    WidgetRef ref,
    PendingOp op,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تجاهل هذه العملية؟'),
        content: Text('${op.label}\nلن تُرسل للسيرفر وستُحذف من الجهاز.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('sync.confirmDiscard'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تجاهل'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(syncControllerProvider.notifier).discard(op);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncControllerProvider);
    return CrmScaffold(
      title: 'المزامنة',
      icon: Icons.sync_rounded,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ActionPill(
            key: const Key('sync.screenNow'),
            label: state.syncing ? 'جارٍ المزامنة...' : 'مزامنة الآن',
            icon: Icons.sync_rounded,
            colors: ActionPill.blue,
            onTap: state.syncing
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const Key('device.backup'),
                  onPressed: () => saveDeviceBackup(context, ref),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('نسخة من بيانات الجهاز'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  key: const Key('device.import'),
                  onPressed: () => importDeviceBackup(context, ref),
                  icon: const Icon(Icons.restore_page_outlined),
                  label: const Text('استرجاع نسخة الجهاز'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.ops.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'كل البيانات وصلت للسيرفر',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final op in state.ops)
            Card(
              key: Key('sync.op.${op.id}'),
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: op.status == PendingStatus.needsReview
                      ? AppColors.error
                      : AppColors.fieldBorder,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      op.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${CrmFormat.dateTime(op.createdAt)} • '
                      '${op.status == PendingStatus.needsReview ? 'يحتاج مراجعة' : 'بانتظار المزامنة'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    if (op.error case final error?)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          error,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    if (op.status == PendingStatus.needsReview)
                      Row(
                        children: [
                          TextButton.icon(
                            key: Key('sync.retry.${op.id}'),
                            onPressed: () => ref
                                .read(syncControllerProvider.notifier)
                                .retry(op),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة المحاولة'),
                          ),
                          if (op.errorCode
                              case 'catalog.similar_grade' || 'party.similar')
                            TextButton.icon(
                              key: Key('sync.confirm.${op.id}'),
                              onPressed: () => ref
                                  .read(syncControllerProvider.notifier)
                                  .retry(op, confirmSimilar: true),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('ليس مكررًا، أضفه'),
                            ),
                          TextButton.icon(
                            key: Key('sync.discard.${op.id}'),
                            onPressed: () => _discard(context, ref, op),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.error,
                            ),
                            label: const Text('تجاهل'),
                          ),
                          if (op.partyId case final id?)
                            TextButton(
                              onPressed: () =>
                                  context.push(CrmRoutes.party(id)),
                              child: const Text('فتح السجل'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
