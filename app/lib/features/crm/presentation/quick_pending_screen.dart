import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/document_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/quick_entry.dart';
import 'backup_actions.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';
import 'quick_entry_widgets.dart';

EntryRow _rowOf(PendingEntry e) => EntryRow(
  id: e.id,
  row: e.row,
  kind: e.kind,
  name: e.name,
  phone: e.phone,
  material: e.material,
  grade: e.grade,
  manufacturer: e.manufacturer,
  materialId: e.materialId,
  gradeId: e.gradeId,
  origin: e.origin,
  reviewAcknowledged: e.reviewAcknowledged,
);

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body, {
  String ok = 'تأكيد',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('confirm.ok'),
            onPressed: () => Navigator.pop(d, true),
            child: Text(ok),
          ),
        ],
      ),
    ) ??
    false;

/// «بانتظار الاستكمال»: صفوف الإدخال السريع الناقصة أو المكررة. ليست عملاء ولا موردين
/// (لا تظهر في البحث ولا المطابقة) حتى تكتمل فتصبح بطاقة مرة واحدة.
class QuickPendingScreen extends ConsumerStatefulWidget {
  const QuickPendingScreen({super.key});

  @override
  ConsumerState<QuickPendingScreen> createState() => _QuickPendingScreenState();
}

class _QuickPendingScreenState extends ConsumerState<QuickPendingScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  String? _kind;
  String? _issue;
  List<PendingEntry> _items = [];
  int _total = 0;
  bool _loading = false;
  String? _error;

  /// صفوف محددة للاستبعاد الجماعي (وضع التحديد).
  final _selected = <String>{};

  /// عمليات «الإدخال السريع» على هذا الجهاز لم تصل للسيرفر بعد (للعرض فقط).
  int _localOps = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(crmRepositoryProvider)
          .pendingEntries(
            query: _q.text,
            kind: _kind,
            issue: _issue,
            skip: more ? _items.length : 0,
          );
      final local = await ref
          .read(crmRepositoryProvider)
          .localQuickOps()
          .catchError((_) => 0);
      if (!mounted) return;
      setState(() {
        _items = more ? [..._items, ...page.items] : page.items;
        _total = page.total;
        _localOps = local;
        _selected.retainAll(_items.map((e) => e.id));
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refresh() {
    ref.invalidate(pendingCountProvider);
    ref.invalidate(registryProvider);
    _load();
  }

  Future<List<PendingEntry>> _all() async {
    final repo = ref.read(crmRepositoryProvider);
    final all = <PendingEntry>[];
    while (true) {
      final page = await repo.pendingEntries(
        query: _q.text,
        kind: _kind,
        issue: _issue,
        skip: all.length,
        take: 200,
      );
      all.addAll(page.items);
      if (page.items.isEmpty || all.length >= page.total) return all;
    }
  }

  TableDocument _document(List<PendingEntry> items) => TableDocument(
    title: 'بانتظار الاستكمال',
    subtitle:
        '${items.length} صف · ${CrmFormat.isoDay(ref.read(clockProvider)())}',
    headers: const ['النوع', 'الاسم', 'الموبايل', 'الخامة', 'Grade', 'الناقص'],
    rows: [
      for (final e in items)
        [
          kindLabel(e.kind),
          e.name ?? '',
          e.phone ?? '',
          e.materialCode ?? e.material ?? '',
          e.gradeLabel ?? e.grade ?? '',
          e.status == 'duplicate'
              ? 'مكرر: ${e.duplicateName ?? ''}'
              : e.issues.map(issueLabel).join('، '),
        ],
    ],
  );

  Future<void> _export(String format) async {
    try {
      final name =
          'بانتظار-الاستكمال-${CrmFormat.isoDay(ref.read(clockProvider)())}';
      switch (format) {
        case 'excel':
          final bytes = await ref
              .read(crmRepositoryProvider)
              .pendingExcel(kind: _kind, issue: _issue);
          await shareExcel(ref, bytes, '$name.xlsx');
        case 'pdf':
          final bytes = await ref
              .read(documentServicesProvider)
              .pdf(_document(await _all()));
          await sharePdf(ref, bytes, '$name.pdf');
        default:
          await ref
              .read(documentServicesProvider)
              .print(_document(await _all()), name);
      }
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    }
  }

  /// نتيجة الاستبعاد كما أرسلها السيرفر (لا افتراض للنجاح).
  Future<void> _showResult({
    required int discarded,
    int already = 0,
    List<DiscardOutcome> skipped = const [],
  }) => showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      key: const Key('pending.result'),
      title: const Text('نتيجة الاستبعاد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('استُبعد: $discarded', key: const Key('pending.result.done')),
            if (already > 0) Text('مستبعد سابقًا: $already'),
            if (skipped.isNotEmpty) ...[
              Text(
                'لم يُستبعد (محمي): ${skipped.length}',
                key: const Key('pending.result.skipped'),
              ),
              for (final r in _reasonCounts(skipped).entries)
                Text('• ${discardReasonLabel(r.key)}: ${r.value}'),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('حسنًا'),
        ),
      ],
    ),
  );

  Map<String, int> _reasonCounts(List<DiscardOutcome> items) {
    final m = <String, int>{};
    for (final i in items) {
      m[i.reason ?? ''] = (m[i.reason ?? ''] ?? 0) + 1;
    }
    return m;
  }

  Future<void> _discardOne(PendingEntry e) async {
    final ok = await _confirm(
      context,
      'استبعاد الصف',
      'سيُستبعد «${e.name ?? 'بدون اسم'}» من «بانتظار الاستكمال» (يبقى في سجل الدفعة '
          'ولا تُلمس أي بطاقة). متابعة؟',
      ok: 'استبعاد',
    );
    if (!ok) return;
    try {
      final r = await ref.read(crmRepositoryProvider).discardPending(e.id);
      if (mounted) {
        showSuccessSnack(
          context,
          r.outcome == 'already_discarded' ? 'مستبعد سابقًا' : 'استُبعد الصف',
        );
      }
    } on ApiException catch (err) {
      if (mounted) showErrorSnack(context, err.message);
    }
    _refresh();
  }

  Future<void> _discardSelected() async {
    final ids = _selected.toList();
    final ok = await _confirm(
      context,
      'استبعاد المحدد',
      'سيُستبعد ${ids.length} صف محدد. الصفوف المحمية (مرتبطة ببطاقة أو جارٍ إنشاؤها) '
          'لن تُستبعد. متابعة؟',
      ok: 'استبعاد',
    );
    if (!ok) return;
    try {
      final r = await ref.read(crmRepositoryProvider).discardPendingMany(ids);
      if (!mounted) return;
      setState(_selected.clear);
      await _showResult(
        discarded: r.discarded,
        already: r.alreadyDiscarded,
        skipped: r.skipped,
      );
    } on ApiException catch (err) {
      if (mounted) showErrorSnack(context, err.message);
    }
    _refresh();
  }

  /// حذف كل المؤهل: معاينة السيرفر بالأعداد والأسباب، ثم تأكيد ثانٍ، ثم التنفيذ بنفس رمز المعاينة.
  Future<void> _discardAll() async {
    final repo = ref.read(crmRepositoryProvider);
    try {
      final preview = await repo.discardAllPending(kind: _kind);
      if (!mounted) return;
      final proceed =
          await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              key: const Key('pending.allPreview'),
              title: const Text('استبعاد كل المؤهل'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سيُستبعد: ${preview.eligible}',
                      key: const Key('pending.allEligible'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'محمي ولن يُستبعد: ${preview.protectedCount}',
                      key: const Key('pending.allProtected'),
                    ),
                    for (final r in preview.protectedByReason.entries)
                      Text('• ${discardReasonLabel(r.key)}: ${r.value}'),
                    Text(
                      'العدد بعد الاستبعاد: ${preview.remainingPending}',
                      key: const Key('pending.allRemaining'),
                    ),
                    if (_localOps > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'على هذا الجهاز $_localOps عملية لم تصل للسيرفر بعد: '
                          'لا يشملها الاستبعاد ولن تُحذف.',
                          style: const TextStyle(color: Color(0xFF9A6200)),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'الاستبعاد منطقي: الصفوف تبقى في سجل الدفعات، ولا تُلمس البطاقات '
                        'أو الكتالوج.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('إلغاء'),
                ),
                if (preview.eligible > 0)
                  FilledButton(
                    key: const Key('pending.allNext'),
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('متابعة'),
                  ),
              ],
            ),
          ) ??
          false;
      if (!proceed || !mounted) return;
      final sure = await _confirm(
        context,
        'تأكيد نهائي',
        'استبعاد ${preview.eligible} صف نهائيًا من «بانتظار الاستكمال»؟',
        ok: 'استبعاد ${preview.eligible}',
      );
      if (!sure) return;
      final done = await repo.discardAllPending(
        token: preview.token,
        kind: _kind,
      );
      if (!mounted) return;
      await _showResult(discarded: done.eligible, skipped: done.protectedItems);
    } on ApiException catch (err) {
      if (!mounted) return;
      showErrorSnack(
        context,
        err.code == 'quick.snapshot_changed'
            ? 'تغيرت القائمة منذ المعاينة ولم يُستبعد شيء. افتح المعاينة من جديد.'
            : err.message,
      );
    }
    _refresh();
  }

  Future<void> _open(PendingEntry entry) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PendingEditSheet(entry: entry),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canSuppliers =
        ref.watch(canSeeSuppliersProvider) || quickCan(ref, 'suppliers.create');
    const issues = [
      'name_missing',
      'phone_missing',
      'phone_invalid',
      'material_missing',
      'material_unknown',
      'grade_missing',
      'grade_unknown',
      'grade_ambiguous',
      'kind_missing',
    ];
    final canDiscard =
        quickCan(ref, 'customers.create') || quickCan(ref, 'suppliers.create');
    return CrmScaffold(
      title: 'بانتظار الاستكمال',
      icon: Icons.pending_actions_rounded,
      bottom: _selected.isEmpty
          ? null
          : Row(
              children: [
                Expanded(
                  child: Text(
                    'محدد: ${_selected.length}',
                    key: const Key('pending.selectedCount'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  key: const Key('pending.clearSelection'),
                  onPressed: () => setState(_selected.clear),
                  child: const Text('إلغاء'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  key: const Key('pending.discardSelected'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed: _discardSelected,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('استبعاد المحدد'),
                ),
              ],
            ),
      actions: [
        if (canDiscard)
          IconButton(
            key: const Key('pending.discardAll'),
            tooltip: 'استبعاد كل المؤهل',
            onPressed: _items.isEmpty ? null : _discardAll,
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
          ),
        PopupMenuButton<String>(
          key: const Key('pending.export'),
          icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
          tooltip: 'تصدير',
          onSelected: _export,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'excel', child: Text('Excel')),
            PopupMenuItem(value: 'pdf', child: Text('PDF')),
            PopupMenuItem(value: 'print', child: Text('طباعة')),
          ],
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('pending.search'),
                  controller: _q,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), _load);
                  },
                  decoration: formDecoration(
                    hint: 'بحث بالاسم أو الرقم أو الخامة',
                    prefix: const Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (k, label) in [
                        (null, 'الكل'),
                        ('customer', 'عملاء'),
                        if (canSuppliers) ('supplier', 'موردون'),
                      ]) ...[
                        ChoiceChip(
                          key: Key('pending.kind.${k ?? 'all'}'),
                          label: Text(label),
                          selected: _kind == k,
                          showCheckmark: false,
                          onSelected: (_) {
                            setState(() => _kind = k);
                            _load();
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                      PopupMenuButton<String>(
                        key: const Key('pending.issue'),
                        onSelected: (v) {
                          setState(() => _issue = v.isEmpty ? null : v);
                          _load();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: '',
                            child: Text('كل النواقص'),
                          ),
                          for (final i in issues)
                            PopupMenuItem(value: i, child: Text(issueLabel(i))),
                        ],
                        child: Chip(
                          avatar: const Icon(
                            Icons.filter_list_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _issue == null ? 'الناقص' : issueLabel(_issue!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$_total صف',
                    key: const Key('pending.total'),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                if (_localOps > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'على هذا الجهاز $_localOps عملية إدخال سريع لم تصل للسيرفر بعد '
                      '(تُرسل عند الاتصال). الاستبعاد يشمل ما على السيرفر فقط ولا يحذفها.',
                      key: const Key('pending.localOps'),
                      style: const TextStyle(
                        color: Color(0xFF9A6200),
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty && !_loading
                ? const Center(
                    child: Text(
                      'لا توجد صفوف بانتظار الاستكمال',
                      key: Key('pending.empty'),
                    ),
                  )
                : ListView.builder(
                    key: const Key('pending.list'),
                    // مساحة شريط النظام أسفل القائمة (أزرار أندرويد أو الإيماءات).
                    padding: EdgeInsets.fromLTRB(
                      12,
                      4,
                      12,
                      12 +
                          (_selected.isEmpty
                              ? MediaQuery.viewPaddingOf(context).bottom
                              : 0),
                    ),
                    itemCount: _items.length + (_items.length < _total ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _items.length) {
                        return TextButton(
                          key: const Key('pending.more'),
                          onPressed: _loading ? null : () => _load(more: true),
                          child: const Text('المزيد'),
                        );
                      }
                      final e = _items[i];
                      final selecting = _selected.isNotEmpty;
                      void toggle() => setState(
                        () => _selected.contains(e.id)
                            ? _selected.remove(e.id)
                            : _selected.add(e.id),
                      );
                      return _PendingTile(
                        entry: e,
                        selecting: selecting,
                        selected: _selected.contains(e.id),
                        onTap: selecting ? toggle : () => _open(e),
                        onLongPress: canDiscard ? toggle : null,
                        onDiscard: canDiscard && !selecting
                            ? () => _discardOne(e)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.onDiscard,
    this.selecting = false,
    this.selected = false,
  });

  final PendingEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDiscard;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final detail = [
      kindLabel(e.kind),
      if ((e.phone ?? '').isNotEmpty) e.phone!,
      if ((e.materialCode ?? e.material ?? '').isNotEmpty)
        e.materialCode ?? e.material!,
      if ((e.gradeLabel ?? e.grade ?? '').isNotEmpty) e.gradeLabel ?? e.grade!,
    ].join(' · ');
    return Card(
      key: Key('pending.row.${e.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? const Color(0xFFFDE4E4) : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (selecting)
                    Checkbox(
                      key: Key('pending.select.${e.id}'),
                      value: selected,
                      onChanged: (_) => onTap(),
                    ),
                  Expanded(
                    child: Text(
                      (e.name ?? '').isEmpty ? '— بدون اسم —' : e.name!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusChip(
                    e.status == 'pending' && e.needsReview
                        ? 'needs_review'
                        : e.status,
                  ),
                  if (onDiscard != null)
                    IconButton(
                      key: Key('pending.discard.${e.id}'),
                      tooltip: 'استبعاد',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDiscard,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.error,
                      ),
                    ),
                ],
              ),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (e.status == 'duplicate')
                Text(
                  'رقم مسجل لـ: ${e.duplicateName ?? 'سجل موجود'}',
                  style: const TextStyle(
                    color: Color(0xFF9A6200),
                    fontSize: 12,
                  ),
                )
              else if (e.issues.isNotEmpty)
                Text(
                  'ناقص: ${e.issues.map(issueLabel).join('، ')}',
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              if (e.warnings.isNotEmpty)
                Text(
                  'تنبيه: ${e.warnings.map(issueLabel).join('، ')}',
                  key: Key('pending.warnings.${e.id}'),
                  style: const TextStyle(
                    color: Color(0xFF9A6200),
                    fontSize: 12,
                  ),
                ),
              if (e.unverifiedGrade != null)
                Text(
                  'Grade غير موثق: ${e.unverifiedGrade}',
                  style: const TextStyle(
                    color: Color(0xFF9A6200),
                    fontSize: 12,
                  ),
                ),
              if (e.errorCode != null)
                Text(
                  'خطأ معالجة (${e.errorCode}) — أعد المحاولة',
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              if (e.note != null && e.status != 'duplicate')
                Text(e.note!, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// تصحيح صف وحفظ التقدم، أو إنشاء البطاقة عند الاكتمال، أو (للمكرر) إضافة الخامة للسجل الموجود بتأكيد.
class PendingEditSheet extends ConsumerStatefulWidget {
  const PendingEditSheet({super.key, required this.entry});

  final PendingEntry entry;

  @override
  ConsumerState<PendingEditSheet> createState() => _PendingEditSheetState();
}

class _PendingEditSheetState extends ConsumerState<PendingEditSheet> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done(String message, String? partyId, String? kind) {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.greenDark,
          action: partyId == null
              ? null
              : SnackBarAction(
                  label: 'فتح البطاقة',
                  textColor: Colors.white,
                  onPressed: () => router.push(
                    CrmRoutes.party(partyId, supplier: kind == 'supplier'),
                  ),
                ),
        ),
      );
  }

  Future<void> _save(EntryRow row) => _guard(() async {
    await ref.read(crmRepositoryProvider).updatePending(widget.entry.id, row);
    if (!mounted) return;
    Navigator.pop(context, true);
    showSuccessSnack(context, 'حُفظ التصحيح');
  });

  /// تأكيد صريح لحفظ Grade ملتبس كنص غير موثق (يُرسل للسيرفر ويُسجَّل في التدقيق).
  Future<bool> _confirmReview(EntryRow row) async {
    final e = widget.entry;
    final refs = ref.read(referenceDataProvider).value;
    final check = refs == null ? null : checkRow(row, e.kind ?? 'mixed', refs);
    final needs = check?.needsReview ?? e.needsReview;
    if (!needs || (row.reviewAcknowledged && e.reviewAcknowledged)) {
      return false;
    }
    return _confirm(
      context,
      'تأكيد مراجعة الـ Grade',
      'سيُحفظ «${check?.unverifiedGrade ?? row.grade ?? ''}» كنص Grade غير موثق دون '
          'ربطه بأي شركة مصنعة أو بالكتالوج. متابعة؟',
      ok: 'أؤكد',
    );
  }

  Future<void> _complete(EntryRow row) => _guard(() async {
    final repo = ref.read(crmRepositoryProvider);
    final needs = await _needsAndConfirm(row);
    if (needs == null) return;
    await repo.updatePending(widget.entry.id, row);
    String id;
    try {
      id = await repo.completePending(
        widget.entry.id,
        acknowledgeReview: needs,
      );
    } on ApiException catch (e) {
      if (!mounted) rethrow;
      if (e.code == 'quick.review_required') {
        final ok = await _confirm(
          context,
          'تأكيد مراجعة الـ Grade',
          e.message,
          ok: 'أؤكد',
        );
        if (!ok) return;
        id = await repo.completePending(
          widget.entry.id,
          acknowledgeReview: true,
        );
      } else if (e.code == 'party.similar') {
        final ok = await _confirm(
          context,
          'اسم مشابه موجود',
          '${e.message}\nهل تريد إنشاء بطاقة جديدة رغم ذلك؟',
          ok: 'إنشاء',
        );
        if (!ok) return;
        id = await repo.completePending(
          widget.entry.id,
          confirmSimilar: true,
          acknowledgeReview: needs,
        );
      } else {
        rethrow;
      }
    }
    if (mounted) _done('أُنشئت البطاقة', id, row.kind);
  });

  /// null = ألغى المستخدم؛ true = أكد مراجعة Grade ملتبس؛ false = لا حاجة للمراجعة.
  Future<bool?> _needsAndConfirm(EntryRow row) async {
    final refs = ref.read(referenceDataProvider).value;
    final needs = refs == null
        ? widget.entry.needsReview
        : checkRow(row, widget.entry.kind ?? 'mixed', refs).needsReview;
    if (!needs) return false;
    return await _confirmReview(row) ? true : null;
  }

  Future<void> _merge(EntryRow row) => _guard(() async {
    final e = widget.entry;
    final ok = await _confirm(
      context,
      'إضافة لسجل موجود',
      'ستُضاف الخامة والـ Grade إلى «${e.duplicateName ?? 'السجل الموجود'}» '
          'دون تغيير اسمه أو بياناته. متابعة؟',
      ok: 'إضافة',
    );
    if (!ok) return;
    final needs = await _needsAndConfirm(row);
    if (needs == null) return;
    final repo = ref.read(crmRepositoryProvider);
    await repo.updatePending(e.id, row);
    String id;
    try {
      id = await repo.mergePending(e.id, acknowledgeReview: needs);
    } on ApiException catch (err) {
      if (err.code != 'quick.role_needed' || !mounted) rethrow;
      final again = await _confirm(
        context,
        'إضافة دور',
        err.message,
        ok: 'إضافة الدور',
      );
      if (!again) return;
      id = await repo.mergePending(
        e.id,
        addRole: true,
        acknowledgeReview: needs,
      );
    }
    if (mounted) _done('أُضيفت الخامة للسجل الموجود', id, row.kind);
  });

  Future<void> _discard() => _guard(() async {
    final ok = await _confirm(
      context,
      'استبعاد الصف',
      'لن يُضاف هذا الصف ولن يظهر في القائمة. متابعة؟',
      ok: 'استبعاد',
    );
    if (!ok) return;
    await ref.read(crmRepositoryProvider).discardPending(widget.entry.id);
    if (mounted) Navigator.pop(context, true);
  });

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider).value;
    final e = widget.entry;
    final canAdd =
        quickCan(ref, 'customers.create') || quickCan(ref, 'suppliers.create');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: refs == null
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'صف ${e.row}${e.createdByName == null ? '' : ' · أدخله ${e.createdByName}'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (e.status == 'duplicate')
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1D6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'الرقم مسجل لـ «${e.duplicateName ?? 'سجل موجود'}». '
                        'لن يُدمج تلقائيًا: أضف الخامة له بتأكيدك، أو صحح الرقم.',
                        key: const Key('pending.duplicateNote'),
                      ),
                    ),
                  EntryEditor(
                    row: _rowOf(e),
                    audience: e.kind ?? 'mixed',
                    refs: refs,
                    actions: (row, check) => [
                      FilledButton.icon(
                        key: const Key('pending.complete'),
                        onPressed:
                            _busy ||
                                !check.complete ||
                                !canAdd ||
                                e.status == 'duplicate'
                            ? null
                            : () => _complete(row),
                        icon: const Icon(Icons.badge_rounded),
                        label: const Text('إنشاء البطاقة'),
                      ),
                      if (e.status == 'duplicate' &&
                          e.duplicateOfId != null) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const Key('pending.merge'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF9A6200),
                          ),
                          onPressed: _busy ? null : () => _merge(row),
                          icon: const Icon(Icons.merge_type_rounded),
                          label: const Text('إضافة الخامة للسجل الموجود'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('pending.save'),
                              onPressed: _busy ? null : () => _save(row),
                              child: const Text('حفظ التقدم'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            key: const Key('pending.discard'),
                            onPressed: _busy ? null : _discard,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.error,
                            ),
                            child: const Text('استبعاد'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

/// سجل الدفعات (من، متى، بأي طريقة، والعدادات) والتراجع الآمن للمدير.
class QuickBatchesScreen extends ConsumerStatefulWidget {
  const QuickBatchesScreen({super.key});

  @override
  ConsumerState<QuickBatchesScreen> createState() => _QuickBatchesScreenState();
}

class _QuickBatchesScreenState extends ConsumerState<QuickBatchesScreen> {
  late Future<List<BatchSummary>> _future = ref
      .read(crmRepositoryProvider)
      .quickBatches();

  Future<void> _undo(BatchSummary b) async {
    final ok = await _confirm(
      context,
      'التراجع عن الدفعة',
      'تُحذف (حذفًا قابلًا للاستعادة) البطاقات التي أنشأتها هذه الدفعة ولم تُعدّل أو تُستخدم بعدها، '
          'وتُستبعد صفوفها المعلقة. ما عُدّل أو استُخدم يبقى كما هو.',
      ok: 'تراجع',
    );
    if (!ok || !mounted) return;
    try {
      final r = await ref.read(crmRepositoryProvider).undoBatch(b.id);
      if (!mounted) return;
      final blocked = (r['blocked'] as List? ?? const [])
          .cast<Map<String, Object?>>();
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('نتيجة التراجع'),
          content: SingleChildScrollView(
            child: Column(
              key: const Key('undo.result'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('حُذفت بطاقات: ${r['reversed']}'),
                Text('استُبعدت صفوف معلقة: ${r['discarded']}'),
                if (blocked.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('بقيت دون تغيير (${blocked.length}):'),
                  for (final x in blocked)
                    Text('• ${x['name']}: ${x['reason']}'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('تم'),
            ),
          ],
        ),
      );
      ref.invalidate(registryProvider);
      ref.invalidate(pendingCountProvider);
      setState(() => _future = ref.read(crmRepositoryProvider).quickBatches());
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUndo = ref.watch(canManageProvider);
    return CrmScaffold(
      title: 'سجل الدفعات',
      icon: Icons.history_rounded,
      body: FutureBuilder<List<BatchSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                snap.error is ApiException
                    ? (snap.error! as ApiException).message
                    : 'تعذر التحميل',
              ),
            );
          }
          final list = snap.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) return const Center(child: Text('لا توجد دفعات'));
          return ListView.builder(
            key: const Key('batches.list'),
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final b = list[i];
              final method = b.method == 'excel' ? 'Excel' : 'لصق مباشر';
              final undone = b.status == 'undone';
              return Card(
                key: Key('batch.${b.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '$method${b.fileName == null ? '' : ' · ${b.fileName}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${CrmFormat.isoDay(b.createdAt.toLocal())} · ${b.createdByName ?? ''}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Pill(
                            'صفوف: ${b.rowCount}',
                            color: AppColors.fieldFill,
                            textColor: AppColors.textPrimary,
                          ),
                          Pill('أُضيف: ${b.created}'),
                          Pill(
                            'معلق: ${b.pending}',
                            color: const Color(0xFFE6F0FC),
                            textColor: AppColors.primary,
                          ),
                          Pill(
                            'مكرر: ${b.duplicate}',
                            color: const Color(0xFFFFF1D6),
                            textColor: const Color(0xFF9A6200),
                          ),
                          if (b.status == 'undone' ||
                              b.status == 'partially_undone')
                            Pill(
                              b.status == 'undone'
                                  ? 'تم التراجع'
                                  : 'تراجع جزئي',
                              color: const Color(0xFFFDE4E4),
                              textColor: AppColors.error,
                            ),
                        ],
                      ),
                      if (canUndo && !undone)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            key: Key('batch.undo.${b.id}'),
                            onPressed: () => _undo(b),
                            icon: const Icon(Icons.undo_rounded),
                            label: const Text('تراجع'),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
