import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_models.dart';
import '../domain/quick_entry.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';
import 'quick_entry_widgets.dart';

/// مراجعة الصفوف قبل الحفظ (مشتركة بين اللصق المباشر وExcel):
/// العدادات والتصفية، تعديل أي صف أو استبعاده، ثم حفظ الدفعة مرة واحدة بمعرف ثابت.
/// السيرفر يحكم على كل صف؛ دون اتصال يُعرض التحقق المحلي بنفس القواعد.
class QuickReviewScreen extends ConsumerStatefulWidget {
  const QuickReviewScreen({
    super.key,
    required this.method,
    required this.audience,
    required this.rows,
    this.fileName,
  });

  final String method;
  final String audience;
  final List<EntryRow> rows;
  final String? fileName;

  @override
  ConsumerState<QuickReviewScreen> createState() => _QuickReviewScreenState();
}

class _QuickReviewScreenState extends ConsumerState<QuickReviewScreen> {
  /// معرف الدفعة ثابت لهذه المراجعة: إعادة الإرسال لا تكرر الحفظ.
  final _batchId = const Uuid().v7();
  Map<String, RowResult> _server = {};
  bool _validating = false;
  bool _offline = false;
  bool _saving = false;
  String? _filter;
  BatchResult? _result;
  bool _queued = false;

  /// أرقام في عمليات محفوظة على الجهاز لم تُرسل بعد (السيرفر لا يراها).
  Set<String> _queuedPhones = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _validate());
  }

  List<EntryRow> get _included => [
    for (final r in widget.rows)
      if (!r.excluded) r,
  ];

  static void _phones(Object? v, Set<String> out, [String? key]) {
    if (v is Map) {
      v.forEach((k, x) => _phones(x, out, '$k'));
    } else if (v is List) {
      for (final x in v) {
        _phones(x, out, key);
      }
    } else if (v is String && const {'phone', 'e164', 'mobile'}.contains(key)) {
      final m = normalizeMobile(v);
      if (m.length == 11) out.add(m);
    }
  }

  Future<void> _loadQueued() async {
    try {
      final out = <String>{};
      for (final op in await ref.read(crmRepositoryProvider).pendingOps()) {
        final body = op.body;
        if (body is Map && body['id'] == _batchId) continue;
        _phones(body, out);
      }
      if (mounted) setState(() => _queuedPhones = out);
    } on Object {
      // القراءة المحلية اختيارية؛ السيرفر يكشف المكرر عند الإرسال.
    }
  }

  Future<void> _validate() async {
    if (_queuedPhones.isEmpty) await _loadQueued();
    final rows = _included;
    if (rows.isEmpty) {
      setState(() => _server = {});
      return;
    }
    setState(() => _validating = true);
    try {
      final r = await ref
          .read(crmRepositoryProvider)
          .quickValidate(
            _batchId,
            widget.method,
            widget.audience,
            rows,
            fileName: widget.fileName,
          );
      if (!mounted) return;
      setState(() {
        _server = {for (final x in r.rows) x.id: x};
        _offline = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _server = {};
        _offline = e.isNetwork;
      });
      if (!e.isNetwork) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  /// حكم الصف: من السيرفر عند الاتصال، وإلا التحقق المحلي بنفس قواعده.
  _Verdict _status(EntryRow r, ReferenceData refs) {
    if (r.excluded) return const _Verdict('excluded');
    final s = _server[r.id];
    final local = checkRow(r, widget.audience, refs);
    final v = s == null
        ? _Verdict(
            local.status(acknowledged: r.reviewAcknowledged),
            issues: local.issues,
            warnings: local.warnings,
            unverified: local.unverifiedGrade,
          )
        : _Verdict(
            s.status,
            issues: s.issues,
            warnings: s.warnings,
            unverified: s.unverifiedGrade,
            note: s.status == 'duplicate'
                ? (s.duplicateName == null
                      ? s.note
                      : 'مكرر مع: ${s.duplicateName}')
                : s.status == 'failed'
                ? s.note
                : null,
          );
    if (v.status == 'ready' &&
        _queuedPhones.contains(normalizeMobile(r.phone ?? ''))) {
      return _Verdict(
        'duplicate',
        issues: v.issues,
        warnings: v.warnings,
        unverified: v.unverified,
        note: 'الرقم في عملية محفوظة على الجهاز بانتظار المزامنة',
      );
    }
    return v;
  }

  /// تأكيد صريح لحفظ Grade ملتبس كنص غير موثق (لا ربط بالكتالوج ولا تخمين للشركة).
  Future<void> _acknowledge(EntryRow row, _Verdict v) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            key: const Key('qr.ackDialog'),
            title: const Text('تأكيد مراجعة الـ Grade'),
            content: Text(
              '${v.warnings.where(reviewWarnings.contains).map(issueLabel).join('\n')}\n\n'
              'سيُحفظ «${v.unverified ?? row.grade ?? ''}» كنص Grade غير موثق، دون ربطه '
              'بأي شركة مصنعة أو بالكتالوج. يمكنك بدلًا من ذلك تعديل الصف واختيار '
              'الـ Grade الصحيح من الكتالوج.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: const Key('qr.ackOk'),
                onPressed: () => Navigator.pop(d, true),
                child: const Text('أؤكد الحفظ كنص غير موثق'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    setState(() => row.reviewAcknowledged = true);
    await _validate();
  }

  /// الخروج قبل الحفظ: تجاهل البيانات المؤقتة (على الجهاز فقط) أو متابعة المراجعة.
  Future<void> _confirmLeave() async {
    final leave =
        await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            key: const Key('qr.leaveDialog'),
            title: const Text('لم تُحفظ الدفعة'),
            content: Text(
              'لديك ${widget.rows.length} صف لم يُحفظ بعد. تجاهل البيانات المؤقتة؟ '
              'لن يُحذف أي شيء محفوظ على السيرفر أو بانتظار المزامنة على الجهاز.',
            ),
            actions: [
              TextButton(
                key: const Key('qr.leaveStay'),
                onPressed: () => Navigator.pop(d, false),
                child: const Text('متابعة المراجعة'),
              ),
              FilledButton(
                key: const Key('qr.leaveDiscard'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(d, true),
                child: const Text('تجاهل البيانات المؤقتة'),
              ),
            ],
          ),
        ) ??
        false;
    if (leave && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _edit(EntryRow row) async {
    final refs = ref.read(referenceDataProvider).value;
    if (refs == null) return;
    final key = GlobalKey<EntryEditorState>();
    final saved = await showModalBottomSheet<EntryRow>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: SingleChildScrollView(
          child: EntryEditor(
            key: key,
            row: row,
            audience: widget.audience,
            refs: refs,
            actions: (edited, check) => [
              FilledButton(
                key: const Key('qe.saveRow'),
                onPressed: () => Navigator.pop(sheet, edited),
                child: const Text('حفظ التعديل'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('qe.excludeRow'),
                onPressed: () {
                  row.excluded = !row.excluded;
                  Navigator.pop(sheet);
                  setState(() {});
                  _validate();
                },
                child: Text(
                  row.excluded ? 'إعادة الصف للدفعة' : 'استبعاد الصف',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == null) return;
    row
      ..kind = saved.kind
      ..name = saved.name
      ..phone = saved.phone
      ..material = saved.material
      ..grade = saved.grade
      ..manufacturer = saved.manufacturer
      ..materialId = saved.materialId
      ..gradeId = saved.gradeId
      ..origin = saved.origin
      ..reviewAcknowledged = saved.reviewAcknowledged;
    setState(() {});
    await _validate();
  }

  Future<void> _commit() async {
    final rows = _included;
    if (rows.isEmpty) return;
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(crmRepositoryProvider)
          .quickCommit(
            _batchId,
            widget.method,
            widget.audience,
            rows,
            fileName: widget.fileName,
          );
      if (!mounted) return;
      ref.invalidate(registryProvider);
      ref.invalidate(pendingCountProvider);
      setState(() {
        _result = r;
        _queued = r == null;
      });
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider).value;
    if (_result != null || _queued) {
      return QuickResultView(
        result: _result,
        queued: _queued,
        rows: widget.rows,
      );
    }
    final statuses = {
      for (final r in widget.rows)
        r.id: refs == null ? const _Verdict('pending') : _status(r, refs),
    };
    int count(String s) => statuses.values.where((x) => x.status == s).length;
    final counts = [
      ('all', 'الكل', widget.rows.length),
      ('ready', 'جاهز', count('ready')),
      if (count('needs_review') > 0)
        ('needs_review', 'يحتاج مراجعة', count('needs_review')),
      ('pending', 'ناقص', count('pending')),
      ('duplicate', 'مكرر', count('duplicate')),
      if (count('failed') > 0) ('failed', 'بلا صلاحية', count('failed')),
      if (count('excluded') > 0) ('excluded', 'مستبعد', count('excluded')),
    ];
    final shown = [
      for (final r in widget.rows)
        if (_filter == null || statuses[r.id]!.status == _filter) r,
    ];
    final included = _included.length;

    return PopScope(
      canPop: widget.rows.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: _screen(refs, counts, shown, statuses, included),
    );
  }

  Widget _screen(
    ReferenceData? refs,
    List<(String, String, int)> counts,
    List<EntryRow> shown,
    Map<String, _Verdict> statuses,
    int included,
  ) {
    return CrmScaffold(
      title: 'مراجعة الصفوف',
      icon: Icons.fact_check_outlined,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.fileName != null)
                  Text(
                    widget.fileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (key, label, n) in counts)
                      FilterChip(
                        key: Key('qr.count.$key'),
                        label: Text('$label: $n'),
                        selected:
                            (key == 'all' && _filter == null) || key == _filter,
                        onSelected: (_) => setState(
                          () => _filter = key == 'all' || key == _filter
                              ? null
                              : key,
                        ),
                        showCheckmark: false,
                      ),
                  ],
                ),
                if (_validating)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(),
                  ),
                if (_offline)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'لا يوجد اتصال: التحقق محلي، والمكرر يُكتشف عند الإرسال.',
                      key: Key('qr.offline'),
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: refs == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    key: const Key('qr.list'),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final r = shown[i];
                      final v = statuses[r.id]!;
                      return _ReviewTile(
                        row: r,
                        verdict: v,
                        showKind: widget.audience == 'mixed',
                        refs: refs,
                        onTap: () => _edit(r),
                        onAcknowledge: v.status == 'needs_review'
                            ? () => _acknowledge(r, v)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
      bottom: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'المكتمل يُضاف بطاقة، والناقص يُحفظ في «بانتظار الاستكمال»، '
                'والمكرر لا يُدمج إلا بموافقتك.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                key: const Key('qr.commit'),
                onPressed: _saving || included == 0 ? null : _commit,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text('حفظ الدفعة ($included صف)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حكم صف في المراجعة: الحالة، والعوائق، والتحذيرات، ونص الـ Grade غير الموثق.
class _Verdict {
  const _Verdict(
    this.status, {
    this.issues = const [],
    this.warnings = const [],
    this.unverified,
    this.note,
  });

  final String status;
  final List<String> issues;
  final List<String> warnings;
  final String? unverified;
  final String? note;
}

const _amber = Color(0xFF9A6200);

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.row,
    required this.verdict,
    required this.showKind,
    required this.refs,
    required this.onTap,
    this.onAcknowledge,
  });

  final EntryRow row;
  final _Verdict verdict;
  final bool showKind;
  final ReferenceData refs;
  final VoidCallback onTap;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final status = verdict.status;
    final issues = verdict.issues;
    final note = verdict.note;
    final material = row.materialId == null
        ? row.material
        : refs.material(row.materialId!)?.code;
    final grade = row.gradeId == null
        ? row.grade
        : refs.grade(row.gradeId!)?.code;
    final detail = [
      if (showKind) kindLabel(row.kind ?? parseKind(row.kind)),
      if ((row.phone ?? '').isNotEmpty) row.phone!,
      if ((material ?? '').isNotEmpty) material!,
      if ((grade ?? '').isNotEmpty) grade!,
    ].join(' · ');
    return Card(
      key: Key('qr.row.${row.row}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '${row.row}',
                    style: const TextStyle(color: AppColors.hint, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (row.name ?? '').isEmpty ? '— بدون اسم —' : row.name!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusChip(status),
                ],
              ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              if (issues.isNotEmpty && status != 'excluded')
                Text(
                  'ناقص: ${issues.map(issueLabel).join('، ')}',
                  key: Key('qr.issues.${row.row}'),
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              if (verdict.warnings.isNotEmpty && status != 'excluded')
                Text(
                  'تنبيه: ${verdict.warnings.map(issueLabel).join('، ')}',
                  key: Key('qr.warnings.${row.row}'),
                  style: const TextStyle(color: _amber, fontSize: 12),
                ),
              if (verdict.unverified != null && status != 'excluded')
                Text(
                  'Grade غير موثق: ${verdict.unverified}'
                  '${(row.manufacturer ?? '').isEmpty ? '' : ' — ${row.manufacturer} (غير موثق)'}',
                  key: Key('qr.unverified.${row.row}'),
                  style: const TextStyle(color: _amber, fontSize: 12),
                ),
              if (row.flags.isNotEmpty && status != 'excluded')
                Text(
                  'راجع: ${row.flags.map(flagLabel).join('، ')}',
                  key: Key('qr.flags.${row.row}'),
                  style: const TextStyle(color: _amber, fontSize: 12),
                ),
              if (note != null)
                Text(note, style: const TextStyle(color: _amber, fontSize: 12)),
              if (onAcknowledge != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: Key('qr.ack.${row.row}'),
                    onPressed: onAcknowledge,
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('مراجعة وتأكيد الحفظ كنص غير موثق'),
                  ),
                ),
              if (row.reviewAcknowledged && status != 'excluded')
                Text(
                  'تم تأكيد المراجعة',
                  key: Key('qr.acked.${row.row}'),
                  style: const TextStyle(
                    color: AppColors.greenDark,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ملخص الدفعة بعد الحفظ: ما أُضيف (مع رابط البطاقة)، وما ذهب لـ«بانتظار الاستكمال».
class QuickResultView extends StatelessWidget {
  const QuickResultView({
    super.key,
    required this.result,
    required this.queued,
    required this.rows,
  });

  final BatchResult? result;
  final bool queued;
  final List<EntryRow> rows;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final names = {for (final x in rows) x.id: x.name};
    return CrmScaffold(
      title: 'نتيجة الدفعة',
      icon: Icons.task_alt_rounded,
      body: ListView(
        key: const Key('qr.result'),
        padding: const EdgeInsets.all(12),
        children: [
          if (queued)
            const QuickCard(
              icon: Icons.cloud_off_rounded,
              title: 'حُفظت الدفعة على الجهاز',
              child: Text(
                'ستُرسل تلقائيًا عند عودة الاتصال بنفس المعرف دون تكرار، '
                'وتظهر نتيجتها في «بانتظار الاستكمال».',
              ),
            ),
          if (r != null) ...[
            QuickCard(
              icon: Icons.summarize_outlined,
              title: 'الملخص',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill(
                    'الإجمالي: ${r.total}',
                    color: AppColors.fieldFill,
                    textColor: AppColors.textPrimary,
                  ),
                  Pill('أُضيف: ${r.created}', key: const Key('qr.created')),
                  Pill(
                    'بانتظار الاستكمال: ${r.pending}',
                    key: const Key('qr.pending'),
                    color: const Color(0xFFE6F0FC),
                    textColor: AppColors.primary,
                  ),
                  Pill(
                    'مكرر محتمل: ${r.duplicate}',
                    key: const Key('qr.duplicate'),
                    color: const Color(0xFFFFF1D6),
                    textColor: const Color(0xFF9A6200),
                  ),
                  if (r.failed > 0)
                    Pill(
                      'بلا صلاحية: ${r.failed}',
                      color: const Color(0xFFFDE4E4),
                      textColor: AppColors.error,
                    ),
                ],
              ),
            ),
            if (r.created > 0)
              QuickCard(
                title: 'البطاقات المضافة',
                icon: Icons.badge_outlined,
                child: Column(
                  children: [
                    for (final x in r.rows)
                      if (x.status == 'completed' && x.partyId != null)
                        ListTile(
                          key: Key('qr.open.${x.row}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(names[x.id] ?? ''),
                          subtitle: Text(
                            '${kindLabel(x.kind)} · ${x.materialCode ?? ''} ${x.gradeLabel ?? ''}',
                          ),
                          trailing: const Icon(Icons.chevron_left_rounded),
                          onTap: () => context.push(
                            CrmRoutes.party(
                              x.partyId!,
                              supplier: x.kind == 'supplier',
                            ),
                          ),
                        ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 8),
          if (queued || (r != null && r.pending + r.duplicate + r.failed > 0))
            FilledButton.icon(
              key: const Key('qr.toPending'),
              onPressed: () => context.push(CrmRoutes.quickPending),
              icon: const Icon(Icons.pending_actions_rounded),
              label: const Text('فتح «بانتظار الاستكمال»'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('qr.done'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }
}
