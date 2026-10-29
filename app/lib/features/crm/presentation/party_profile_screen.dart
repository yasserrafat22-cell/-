import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/share_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'attachments_section.dart';
import 'contact_launcher.dart';
import 'contacts_section.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';
import 'insights_screens.dart';
import 'location_screens.dart';
import 'material_picker.dart';
import 'quick_add_party_screen.dart' show AsyncBody;
import 'sync_screen.dart';

/// ملف العميل (ص8) أو المورد (ص9). للشركة المسجلة بالدورين يحدد [asSupplier]
/// أي ملف يُعرض.
class PartyProfileScreen extends ConsumerStatefulWidget {
  const PartyProfileScreen({super.key, required this.partyId, this.asSupplier});

  final String partyId;
  final bool? asSupplier;

  @override
  ConsumerState<PartyProfileScreen> createState() => _PartyProfileScreenState();
}

class _PartyProfileScreenState extends ConsumerState<PartyProfileScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(partyProvider(widget.partyId));
    final supplier =
        widget.asSupplier ?? (party.value != null && !party.value!.isCustomer);
    return CrmScaffold(
      title: supplier ? 'بيانات المورد' : 'بيانات العميل',
      icon: supplier ? Icons.local_shipping_rounded : Icons.groups_rounded,
      body: AsyncBody(
        value: party,
        onRetry: () => refreshParty(ref, widget.partyId),
        data: (p) => RefreshIndicator(
          onRefresh: () async {
            refreshParty(ref, p.id);
            await ref.read(partyProvider(p.id).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _Header(party: p, supplier: supplier),
              const SizedBox(height: 14),
              SegmentTabs(
                labels: supplier
                    ? const ['نظرة عامة', 'التوريدات', 'التواصل', 'التفاصيل']
                    : const ['نظرة عامة', 'الطلبات', 'التواصل', 'التفاصيل'],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 14),
              ..._tabContent(p, supplier),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _tabContent(PartyDetail p, bool supplier) {
    final tabs = supplier
        ? ['overview', 'supplies', 'contacts', 'details']
        : ['overview', 'orders', 'contacts', 'details'];
    return switch (tabs[_tab.clamp(0, tabs.length - 1)]) {
      'overview' => [_Overview(party: p, supplier: supplier)],
      'orders' => [_OrdersTab(party: p)],
      'supplies' => [_SuppliesTab(party: p)],
      'contacts' => [_ContactsTab(party: p)],
      _ => [_DetailsTab(party: p, supplier: supplier)],
    };
  }
}

/// يفتح الاتصال أو واتساب ثم شاشة تسجيل النتيجة: الضغط وحده لا يُعد تواصلًا.
Future<void> contactAndLog(
  BuildContext context,
  PartyDetail party,
  ContactChannel channel,
) async {
  final phone = party.primaryPhone;
  if (phone == null) return;
  if (channel == ContactChannel.call) {
    await ContactLauncher.call(phone.e164);
  } else {
    await ContactLauncher.whatsApp(phone.whatsAppNumber);
  }
  if (context.mounted && party.canAdd) {
    await context.push(CrmRoutes.newContact(party.id, channel: channel));
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.party, required this.supplier});

  final PartyDetail party;
  final bool supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refs = ref.watch(referenceDataProvider).value;
    final activity = refs?.lookup(
      supplier ? party.supplierActivityId : party.customerActivityId,
    );
    final summary = supplier ? party.supplierSummary : party.customerSummary;
    final governorate = refs?.lookup(party.governorateId)?.nameAr;
    final address = [
      governorate,
      party.region,
      party.addressLine,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' - ');

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.fieldBorder),
          ),
          child: Row(
            children: [
              LogoAvatar(party: party),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      party.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (activity != null)
                          Pill(
                            activity.nameAr,
                            color: supplier
                                ? const Color(0xFFDCEBFA)
                                : const Color(0xFFDFF3D3),
                            textColor: supplier
                                ? AppColors.primary
                                : AppColors.greenDark,
                          ),
                        if (summary != null)
                          _StatusPill(summary.status, supplier),
                        SyncPill(partyId: party.id),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    key: const Key('profile.favorite'),
                    tooltip: party.isFavorite
                        ? 'إزالة من المفضلة'
                        : 'إضافة للمفضلة',
                    onPressed: () async {
                      try {
                        await ref
                            .read(crmRepositoryProvider)
                            .setFavorite(party.id, !party.isFavorite);
                        refreshParty(ref, party.id);
                      } on ApiException catch (e) {
                        if (context.mounted) showErrorSnack(context, e.message);
                      }
                    },
                    icon: Icon(
                      party.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: party.isFavorite
                          ? AppColors.reportsAccent
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (party.canEdit)
                    IconButton.filledTonal(
                      key: const Key('profile.menu'),
                      tooltip: 'تعديل البيانات',
                      onPressed: () =>
                          context.push(CrmRoutes.editDetails(party.id)),
                      icon: const Icon(
                        Icons.edit_rounded,
                        color: AppColors.navy,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (address.isNotEmpty) ...[
          InfoRow(icon: Icons.location_on_rounded, text: address),
          const SizedBox(height: 8),
        ],
        InfoRow(
          icon: Icons.person_rounded,
          text: 'المندوب: ${party.representativeName ?? '—'}',
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status, this.supplier, {this.short = false});

  final PartyStatus status;
  final bool supplier;

  /// صف «حالة العميل» يعرض الحالة وحدها («نشط») كما في التصميم.
  final bool short;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      PartyStatus.active when !short => supplier ? 'مورد نشط' : 'عميل نشط',
      _ => CrmFormat.status(status, supplier: supplier),
    };
    return Pill.forStatusColor(
      text,
      status == PartyStatus.active || status == PartyStatus.newParty,
      status == PartyStatus.needsFollowUp,
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.party, required this.supplier});

  final PartyDetail party;
  final bool supplier;

  @override
  Widget build(BuildContext context) {
    final summary = (supplier ? party.supplierSummary : party.customerSummary)!;
    final materials = supplier
        ? party.products.map((p) => p.materialCode).toSet().join(' , ')
        : party.interests.map((i) => i.materialCode).toSet().join(' , ');
    final hasPhone = party.primaryPhone != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.calendar_month_rounded,
                label: supplier ? 'آخر توريد' : 'آخر طلب',
                value: CrmFormat.date(summary.lastDealDate),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: Icons.inventory_2_outlined,
                label: supplier ? 'كمية آخر توريد' : 'كمية آخر طلب',
                value: CrmFormat.quantityKg(summary.lastDealQuantityKg),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.layers_outlined,
                label: supplier
                    ? 'الخامات المتاحة الرئيسية'
                    : 'الخامات الرئيسية',
                value: materials.isEmpty ? '—' : materials,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: Icons.phone_in_talk_rounded,
                label: 'آخر تواصل',
                value: CrmFormat.date(summary.lastContactAt),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(
              Icons.assignment_turned_in_outlined,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              supplier ? 'حالة المورد' : 'حالة العميل',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const Spacer(),
            _StatusPill(summary.status, supplier, short: true),
          ],
        ),
        if (summary.nextFollowUpAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'المتابعة القادمة: ${CrmFormat.date(summary.nextFollowUpAt)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ActionPill(
                key: const Key('profile.call'),
                label: 'اتصال',
                icon: Icons.call_rounded,
                colors: ActionPill.blue,
                onTap: hasPhone
                    ? () => contactAndLog(context, party, ContactChannel.call)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionPill(
                key: const Key('profile.whatsapp'),
                label: 'واتساب',
                icon: Icons.chat_rounded,
                colors: ActionPill.green,
                onTap: hasPhone
                    ? () =>
                          contactAndLog(context, party, ContactChannel.whatsApp)
                    : null,
              ),
            ),
          ],
        ),
        if (party.canAdd) ...[
          const SizedBox(height: 10),
          ActionPill(
            key: const Key('profile.newRecord'),
            label: supplier ? 'تسجيل توريد جديد' : 'تسجيل طلب جديد',
            icon: Icons.add_rounded,
            colors: ActionPill.blue,
            onTap: () => context.push(
              supplier
                  ? CrmRoutes.newSupply(party.id)
                  : CrmRoutes.newOrder(party.id),
            ),
          ),
          const SizedBox(height: 10),
          ActionPill(
            key: const Key('profile.newContact'),
            label: 'تسجيل تواصل جديد',
            icon: Icons.chat_bubble_rounded,
            colors: ActionPill.blue,
            outlined: true,
            onTap: () => context.push(CrmRoutes.newContact(party.id)),
          ),
        ],
      ],
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(ordersProvider(party.id)),
      onRetry: () => ref.invalidate(ordersProvider(party.id)),
      data: (orders) => orders.isEmpty
          ? const _Empty('لا توجد طلبات أو استفسارات مسجلة بعد')
          : Column(
              children: [
                for (final o in orders)
                  _RecordCard(
                    date: o.orderDate,
                    status: CrmFormat.stage(o.stage),
                    statusTone: switch (o.stage) {
                      OrderStage.completed || OrderStage.confirmed => 1,
                      OrderStage.cancelled => -1,
                      _ => 0,
                    },
                    flag: o.onHold ? 'معلق' : null,
                    lines: o.lines,
                    totalKg: o.totalKg,
                    notes: o.notes,
                    actions: party.canAdd
                        ? [
                            for (final next in orderTransitions[o.stage]!)
                              (
                                CrmFormat.stage(next),
                                () => ref
                                    .read(crmRepositoryProvider)
                                    .changeOrderStage(o, next),
                              ),
                          ]
                        : const [],
                    onChanged: () => refreshParty(ref, party.id),
                  ),
              ],
            ),
    );
  }
}

class _SuppliesTab extends ConsumerWidget {
  const _SuppliesTab({required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(suppliesProvider(party.id)),
      onRetry: () => ref.invalidate(suppliesProvider(party.id)),
      data: (supplies) => supplies.isEmpty
          ? const _Empty('لا توجد توريدات مسجلة بعد')
          : Column(
              children: [
                for (final s in supplies)
                  _RecordCard(
                    date: s.supplyDate,
                    status: CrmFormat.supplyStatus(s.status),
                    statusTone: switch (s.status) {
                      SupplyStatus.received => 1,
                      SupplyStatus.cancelled => -1,
                      SupplyStatus.expected => 0,
                    },
                    lines: s.lines,
                    totalKg: s.totalKg,
                    notes: s.notes,
                    actions: party.canAdd && s.status == SupplyStatus.expected
                        ? [
                            for (final next in [
                              SupplyStatus.received,
                              SupplyStatus.cancelled,
                            ])
                              (
                                CrmFormat.supplyStatus(next),
                                () => ref
                                    .read(crmRepositoryProvider)
                                    .changeSupplyStatus(s, next),
                              ),
                          ]
                        : const [],
                    onChanged: () => refreshParty(ref, party.id),
                  ),
              ],
            ),
    );
  }
}

/// بطاقة طلب أو توريد: التاريخ والحالة والخامات والكميات وتغيير الحالة.
class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.date,
    required this.status,
    required this.statusTone,
    required this.lines,
    required this.totalKg,
    required this.actions,
    required this.onChanged,
    this.flag,
    this.notes,
  });

  final DateTime date;
  final String status;
  final int statusTone;
  final String? flag;
  final List<LineItem> lines;
  final double totalKg;
  final String? notes;
  final List<(String, Future<void> Function())> actions;
  final VoidCallback onChanged;

  Future<void> _run(
    BuildContext context,
    (String, Future<void> Function()) action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغيير الحالة'),
        content: Text('تغيير الحالة إلى «${action.$1}»؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await action.$2();
    } on ApiException catch (e) {
      if (context.mounted) showErrorSnack(context, e.message);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_rounded, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  CrmFormat.date(date),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (flag != null) ...[
                  Pill(
                    flag!,
                    color: const Color(0xFFFFF1D6),
                    textColor: const Color(0xFF9A6200),
                  ),
                  const SizedBox(width: 6),
                ],
                Pill.forStatusColor(status, statusTone > 0, statusTone == 0),
                if (actions.isNotEmpty)
                  PopupMenuButton<int>(
                    tooltip: 'تغيير الحالة',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (i) => _run(context, actions[i]),
                    itemBuilder: (_) => [
                      for (final (i, a) in actions.indexed)
                        PopupMenuItem(
                          value: i,
                          child: Text('تغيير إلى: ${a.$1}'),
                        ),
                    ],
                  ),
              ],
            ),
            const Divider(),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SpecChip(l.spec),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${CrmFormat.number(l.quantity)} ${CrmFormat.unitName(l.unitCode)}',
                    ),
                  ],
                ),
              ),
            if (lines.length > 1) ...[
              const Divider(),
              Row(
                children: [
                  const Text(
                    'الإجمالي',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    CrmFormat.quantityKg(totalKg),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
            if (notes != null) ...[
              const SizedBox(height: 4),
              Text(
                notes!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// بطاقة تواصل نصية للمشاركة (واتساب أو غيره): الاسم، الهواتف، البريد،
/// العنوان، ورابط الموقع الافتراضي إن وُجد.
String contactCard(
  PartyDetail party,
  ReferenceData? refs,
  List<PartyLocation>? locations,
) {
  final address = [
    refs?.lookup(party.governorateId)?.nameAr,
    party.region,
    party.addressLine,
  ].nonNulls.where((s) => s.isNotEmpty).join(' - ');
  final place = locations?.where((l) => l.isDefault).firstOrNull;
  return [
    party.name,
    for (final p in party.phones) 'هاتف: ${CrmFormat.phone(p.e164)}',
    if (party.email case final e? when e.isNotEmpty) 'بريد: $e',
    if (address.isNotEmpty) 'العنوان: $address',
    if (place?.link case final link?) 'الموقع: $link',
  ].join('\n');
}

/// إسناد السجل لمندوب آخر (يُسجل في سجل التدقيق؛ لا يعدّل بيانات الشركة).
Future<void> _assign(
  BuildContext context,
  WidgetRef ref,
  PartyDetail party,
  ReferenceData refs,
) async {
  final repId = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final r in refs.representatives)
            ListTile(
              key: Key('assign.${r.id}'),
              leading: Icon(
                r.id == party.representativeId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(r.name),
              onTap: () => Navigator.pop(context, r.id),
            ),
        ],
      ),
    ),
  );
  if (repId == null || repId == party.representativeId || !context.mounted) {
    return;
  }
  try {
    await ref.read(crmRepositoryProvider).assignParty(party.id, repId);
    refreshParty(ref, party.id);
    if (context.mounted) showSuccessSnack(context, 'تم الإسناد');
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}

/// حذف آمن للمدير العام: يختفي السجل ويبقى قابلًا للاستعادة من «المحذوفات».
Future<void> _deleteParty(
  BuildContext context,
  WidgetRef ref,
  PartyDetail party,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('حذف السجل؟'),
      content: Text('${party.name}\nيمكن استعادته لاحقًا من المحذوفات.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('party.confirmDelete'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(crmRepositoryProvider).deleteParty(party.id);
    ref.invalidate(registryProvider);
    if (context.mounted) context.pop();
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}

/// يضيف خامة للعميل (ضمن اهتماماته) أو للمورد (منتج) دون تكرار الموجود.
Future<void> _addMaterial(
  BuildContext context,
  WidgetRef ref,
  PartyDetail party, {
  required bool supplier,
}) async {
  final picked = await pickSpec(context, allowOpen: !supplier);
  if (picked == null || !context.mounted) return;
  final repo = ref.read(crmRepositoryProvider);
  try {
    if (supplier) {
      await repo.addProduct(party.id, picked);
    } else {
      await repo.addInterest(party.id, picked);
    }
    refreshParty(ref, party.id);
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}

class _ProductsSection extends StatelessWidget {
  const _ProductsSection({required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context) {
    if (party.products.isEmpty) {
      return const _Empty('لا توجد منتجات مسجلة لهذا المورد');
    }
    return Column(
      children: [
        for (final p in party.products)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SpecChip(p.spec),
                        if (p.latestPrice case final price?)
                          Text(
                            'آخر سعر: ${CrmFormat.number(price.price)} ${price.currency}/'
                            '${CrmFormat.unitName(price.unitCode)} — ${CrmFormat.date(price.quoteDate)}'
                            '${price.expired ? ' (انتهت صلاحيته)' : ''}',
                            style: TextStyle(
                              color: price.expired
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ContactsTab extends ConsumerWidget {
  const _ContactsTab({required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(interactionsProvider(party.id)),
      onRetry: () => ref.invalidate(interactionsProvider(party.id)),
      data: (items) => items.isEmpty
          ? const _Empty('لم يُسجل أي تواصل بعد')
          : Column(
              children: [
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SectionCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(switch (i.channel) {
                            ContactChannel.call => Icons.call_rounded,
                            ContactChannel.whatsApp => Icons.chat_rounded,
                            ContactChannel.visit =>
                              Icons.directions_walk_rounded,
                            ContactChannel.other => Icons.more_horiz_rounded,
                          }, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${CrmFormat.channel(i.channel)} — ${i.outcomeName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${CrmFormat.dateTime(i.occurredAt)}'
                                  '${i.createdByName.isEmpty ? '' : ' • ${i.createdByName}'}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                if (i.notes != null) Text(i.notes!),
                                if (i.nextFollowUpAt != null)
                                  Text(
                                    'متابعة: ${CrmFormat.date(i.nextFollowUpAt)}'
                                    '${i.followUpDone ? ' (تمت)' : ''}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
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

class _DetailsTab extends ConsumerWidget {
  const _DetailsTab({required this.party, required this.supplier});

  final PartyDetail party;

  /// ملف المورد أو ملف العميل لنفس الشركة (إن كانت الاثنين).
  final bool supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refs = ref.watch(referenceDataProvider).value;
    String? lookup(String? id) => refs?.lookup(id)?.nameAr;
    final rows = <(IconData, String, String?)>[
      for (final p in party.phones) (Icons.phone_rounded, 'الهاتف', p.e164),
      (Icons.email_outlined, 'البريد الإلكتروني', party.email),
      (Icons.map_outlined, 'المحافظة', lookup(party.governorateId)),
      (Icons.location_city_rounded, 'المنطقة', party.region),
      (Icons.location_on_outlined, 'العنوان', party.addressLine),
      if (party.isCustomer)
        (
          Icons.factory_outlined,
          'نشاط العميل',
          lookup(party.customerActivityId),
        ),
      if (party.isSupplier)
        (
          Icons.local_shipping_outlined,
          'نوع المورد',
          lookup(party.supplierActivityId),
        ),
      (Icons.notes_rounded, 'ملاحظات', party.notes),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            children: [
              for (final (i, (icon, label, value)) in rows.indexed)
                // الضغط على رقم الهاتف يتصل مباشرة.
                // والبريد يفتح تطبيق البريد برسالة جديدة.
                InkWell(
                  key: switch (icon) {
                    Icons.phone_rounded => Key('details.phone.$i'),
                    Icons.email_outlined => const Key('details.email'),
                    _ => null,
                  },
                  onTap: value == null || value.isEmpty
                      ? null
                      : switch (icon) {
                          Icons.phone_rounded => () => ContactLauncher.call(
                            value,
                          ),
                          Icons.email_outlined => () => ContactLauncher.email(
                            value,
                          ),
                          _ => null,
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: icon == Icons.phone_rounded && value != null
                              ? Text(
                                  CrmFormat.phone(value),
                                  textDirection: TextDirection.ltr,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : Text(
                                  value == null || value.isEmpty ? '—' : value,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('profile.shareContact'),
            onPressed: () => ref
                .read(shareServiceProvider)
                .text(
                  contactCard(
                    party,
                    refs,
                    ref.read(locationsProvider(party.id)).value,
                  ),
                ),
            icon: const Icon(Icons.share_rounded),
            label: const Text('مشاركة بيانات التواصل'),
          ),
        ),
        if (ref.watch(canTeamAssignProvider) && refs != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('profile.assign'),
              onPressed: () => _assign(context, ref, party, refs),
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('إسناد لمندوب'),
            ),
          ),
        if (party.isCustomer && !supplier && ref.watch(canSeeSuppliersProvider))
          SupplierMatchesSection(customerId: party.id),
        ContactsSection(party: party),
        const SizedBox(height: 12),
        LocationsSection(party: party),
        const SizedBox(height: 12),
        AttachmentsSection(party: party, supplier: supplier),
        if (!supplier) ...[
          const SizedBox(height: 16),
          const FieldLabel('الخامات المهتم بها', icon: Icons.layers_outlined),
          if (party.interests.isEmpty)
            const _Empty('لا توجد خامات مسجلة لهذا العميل')
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final i in party.interests) SpecChip(i.spec)],
            ),
        ],
        if (supplier) ...[
          const SizedBox(height: 16),
          const FieldLabel('المنتجات والأسعار', icon: Icons.sell_outlined),
          _ProductsSection(party: party),
        ],
        if (party.canAdd)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('profile.addMaterial'),
              onPressed: () =>
                  _addMaterial(context, ref, party, supplier: supplier),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة خامة'),
            ),
          ),
        const SizedBox(height: 16),
        const FieldLabel('آخر التعديلات', icon: Icons.manage_history_rounded),
        _History(party: party),
        if (party.canEdit) ...[
          const SizedBox(height: 12),
          ActionPill(
            key: const Key('profile.edit'),
            label: 'تعديل البيانات واستكمالها',
            icon: Icons.edit_rounded,
            colors: ActionPill.blue,
            outlined: true,
            onTap: () => context.push(CrmRoutes.editDetails(party.id)),
          ),
          const SizedBox(height: 8),
          ActionPill(
            key: const Key('profile.delete'),
            label: 'حذف السجل',
            icon: Icons.delete_outline_rounded,
            colors: ActionPill.red,
            outlined: true,
            onTap: () => _deleteParty(context, ref, party),
          ),
        ],
      ],
    );
  }
}

/// سجل مختصر للتعديلات المهمة: من عدّل، ومتى، وماذا.
class _History extends ConsumerWidget {
  const _History({required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider(party.id));
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'أُنشئ: ${party.createdAt == null ? '—' : CrmFormat.dateTime(party.createdAt!)}'
            '\nآخر تعديل: ${party.updatedAt == null ? '—' : CrmFormat.dateTime(party.updatedAt!)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
          const Divider(height: 18),
          ...switch (history) {
            AsyncData(:final value) when value.isEmpty => [
              const Text('لا توجد تعديلات مسجلة'),
            ],
            AsyncData(:final value) => [
              for (final h in value.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: AppColors.hint,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${h.description}\n',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${h.userName ?? '—'} • ${CrmFormat.dateTime(h.at)}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            AsyncError() => [
              TextButton(
                onPressed: () => ref.invalidate(historyProvider(party.id)),
                child: const Text('تعذر التحميل — إعادة المحاولة'),
              ),
            ],
            _ => [const LinearProgressIndicator()],
          },
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textSecondary),
    ),
  );
}

/// للاستخدام في التوجيه: يحدد عرض المورد عند `?role=supplier`.
bool? roleFromQuery(String? role) => switch (role) {
  'supplier' => true,
  'customer' => false,
  _ => null,
};
