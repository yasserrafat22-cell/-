import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';
import 'quick_add_party_screen.dart' show AsyncBody;

/// جرس الرئيسية: عدد متابعات اليوم والمتأخرة.
class FollowUpBell extends ConsumerWidget {
  const FollowUpBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(followUpsProvider).value ?? const [];
    final due = items.where((f) => f.status != FollowUpStatus.upcoming).length;
    return IconButton(
      key: const Key('home.bell'),
      tooltip: 'المتابعات',
      onPressed: () => context.push(CrmRoutes.followUps),
      icon: Badge(
        isLabelVisible: due > 0,
        label: Text('$due', key: const Key('home.bellCount')),
        child: const Icon(Icons.notifications_rounded, color: Colors.white),
      ),
    );
  }
}

/// متابعات اليوم والمتأخرة والقادمة؛ الضغط يفتح ملف السجل.
class FollowUpsScreen extends ConsumerWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(followUpsProvider);
    return CrmScaffold(
      title: 'المتابعات',
      icon: Icons.notifications_rounded,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(followUpsProvider.future),
        child: AsyncBody(
          value: items,
          onRetry: () => ref.invalidate(followUpsProvider),
          data: (list) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'لا توجد متابعات مستحقة',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              for (final (status, title, color) in [
                (FollowUpStatus.overdue, 'متأخرة', AppColors.error),
                (FollowUpStatus.today, 'اليوم', AppColors.primary),
                (FollowUpStatus.upcoming, 'القادمة', AppColors.textSecondary),
              ])
                if (list.where((f) => f.status == status).toList()
                    case final group when group.isNotEmpty) ...[
                  FieldLabel(
                    '$title (${group.length})',
                    icon: Icons.event_note,
                  ),
                  for (final f in group)
                    Card(
                      key: Key('followUp.${f.interactionId}'),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: color.withValues(alpha: 0.4)),
                      ),
                      child: ListTile(
                        onTap: () => context.push(
                          CrmRoutes.party(f.partyId, supplier: !f.isCustomer),
                        ),
                        leading: Icon(
                          f.remind
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_off_outlined,
                          color: color,
                        ),
                        title: Text(
                          f.partyName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            CrmFormat.dateTime(f.dueAt),
                            if (f.representativeName case final r? when !f.mine)
                              'المندوب: $r',
                            ?f.notes,
                          ].join(' • '),
                        ),
                      ),
                    ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

/// «موردون مناسبون» لاحتياجات العميل (للإدارة فقط): المطابقات الدقيقة ثم البدائل
/// منفصلة، مع سبب كل نتيجة وآخر سعر مسجل فقط.
class SupplierMatchesSection extends ConsumerStatefulWidget {
  const SupplierMatchesSection({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<SupplierMatchesSection> createState() =>
      _SupplierMatchesSectionState();
}

class _SupplierMatchesSectionState
    extends ConsumerState<SupplierMatchesSection> {
  bool _open = false;

  Widget _tile(SupplierMatch m) => Card(
    key: Key(
      'match.${m.supplierId}.${m.product.gradeId ?? m.product.materialId}',
    ),
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.fieldBorder),
    ),
    child: ListTile(
      onTap: () => context.push(CrmRoutes.party(m.supplierId, supplier: true)),
      title: Text(
        m.supplierName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SpecChip(m.product),
          ),
          for (final r in m.reasons)
            Text('• $r', style: const TextStyle(fontSize: 12.5)),
          if (m.price case final p?)
            Text(
              'آخر سعر مسجل: ${p.toStringAsFixed(0)} ${m.currency} '
              '(${CrmFormat.date(m.quoteDate)})${m.priceExpired ? ' — منتهي' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
        ],
      ),
      trailing: Text(
        '${m.score}',
        style: const TextStyle(color: AppColors.primary),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const Key('profile.matches'),
          onPressed: () => setState(() => _open = true),
          icon: const Icon(Icons.manage_search_rounded),
          label: const Text('الموردون المناسبون لاحتياجات العميل'),
        ),
      );
    }
    final matches = ref.watch(supplierMatchesProvider(widget.customerId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel(
          'الموردون المناسبون',
          icon: Icons.manage_search_rounded,
        ),
        switch (matches) {
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.exact.isEmpty && value.alternatives.isEmpty)
                const Text(
                  'لا توجد منتجات موردين مسجلة لهذه الخامات',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              if (value.exact.isNotEmpty) ...[
                const Text(
                  'مطابقة دقيقة',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                for (final m in value.exact) _tile(m),
              ],
              if (value.alternatives.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'بدائل محتملة (مع سبب الاختلاف)',
                  key: Key('matches.alternatives'),
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                for (final m in value.alternatives) _tile(m),
              ],
            ],
          ),
          AsyncError(:final error) => Text(
            error.toString(),
            style: const TextStyle(color: AppColors.error),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ],
    );
  }
}
