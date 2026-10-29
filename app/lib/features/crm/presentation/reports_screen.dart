import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/document_services.dart';
import '../../../core/device/file_services.dart';
import '../../../core/device/share_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'backup_actions.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';
import 'quick_add_party_screen.dart' show AsyncBody;

/// أقسام التقرير القابلة للاختيار عند المشاركة أو التصدير.
const reportSections = {
  'kpis': 'المؤشرات',
  'pipeline': 'مراحل الطلبات',
  'materials': 'أعلى الخامات',
  'grades': 'أعلى الـ Grades',
  'customers': 'أعلى العملاء',
  'representatives': 'المندوبون والمديرون',
  'suppliers': 'الموردون',
  'trend': 'الاتجاه الشهري',
  'demand': 'الطلب مقابل المبيعات',
  'activity': 'نشاط العملاء',
  'dormant': 'عملاء خاملون',
  'followUps': 'المتابعات',
  'quality': 'جودة البيانات',
};

String _stage(String name) => CrmFormat.stage(
  OrderStage.values.firstWhere(
    (s) => s.name.toLowerCase() == name.toLowerCase(),
    orElse: () => OrderStage.inquiry,
  ),
);

String _kg(double kg) => CrmFormat.quantityKg(kg);

/// صفوف كل قسم (للنص وPDF والطباعة) — نفس ما يظهر على الشاشة.
List<(String, List<List<String>>)> reportTables(
  ReportDashboard d,
  Set<String> sections,
) {
  List<List<String>> ranked(List<RankRow> rows) => [
    for (final (i, r) in rows.indexed)
      ['${i + 1}', r.label, '${r.orders}', _kg(r.kg), r.extra ?? ''],
  ];
  final k = d.kpis;
  final (n, active, follow, stopped) = d.activity;
  final all = <String, List<List<String>>>{
    'kpis': [
      [
        '',
        'مكتمل (مبيعات محققة)',
        '${k.completedOrders}',
        _kg(k.completedKg),
        '',
      ],
      ['', 'مفتوح', '${k.openOrders}', _kg(k.openKg), ''],
      ['', 'ملغى', '${k.cancelledOrders}', _kg(k.cancelledKg), ''],
      ['', 'عملاء اشتروا', '${k.activeCustomers}', '', ''],
      ['', 'عملاء جدد', '${k.newCustomers}', '', ''],
      ['', 'تواصلات', '${k.contacts}', '', ''],
      [
        '',
        'نسبة التحويل',
        k.conversionRate == null
            ? '—'
            : '${(k.conversionRate! * 100).toStringAsFixed(0)}%',
        '',
        '',
      ],
      ['', 'قيمة المبيعات', 'غير متاحة', '', 'الطلبات لا تحمل أسعارًا'],
    ],
    'pipeline': [
      for (final p in d.pipeline)
        ['', _stage(p.label), '${p.orders}', _kg(p.kg), ''],
    ],
    'materials': ranked(d.materials),
    'grades': ranked(d.grades),
    'customers': ranked(d.customers),
    'representatives': ranked(d.representatives),
    if (d.suppliers case final s?) 'suppliers': ranked(s),
    'trend': [
      for (final t in d.trend) ['', t.label, '${t.orders}', _kg(t.kg), ''],
    ],
    'demand': [
      for (final x in d.demand)
        [
          '',
          x.material,
          '${x.demandCustomers} عميل',
          _kg(x.soldKg),
          x.suppliers == null ? '' : '${x.suppliers} مورد',
        ],
    ],
    'activity': [
      ['', 'جديد', '$n', '', ''],
      ['', 'نشط', '$active', '', ''],
      ['', 'يحتاج متابعة', '$follow', '', ''],
      ['', 'متوقف', '$stopped', '', ''],
    ],
    'dormant': ranked(d.dormant),
    'followUps': [
      ['', 'متأخرة', '${d.overdue}', '', ''],
      ['', 'اليوم', '${d.today}', '', ''],
    ],
    'quality': [
      ['', 'سجلات تحتاج استكمال', '${d.incomplete}', '', ''],
      if (d.quality case final q?) ...[
        ['', 'بدون نوع نشاط', '${q.missingActivity}', '', ''],
        ['', 'بدون محافظة', '${q.missingGovernorate}', '', ''],
        ['', 'بدون موقع', '${q.withoutLocation}', '', ''],
        ['', 'بدون جهات اتصال', '${q.withoutContacts}', '', ''],
        ['', 'تكرارات محتملة', '${q.duplicates.length}', '', ''],
      ],
    ],
  };
  return [
    for (final MapEntry(:key, :value) in all.entries)
      if (sections.contains(key)) (reportSections[key]!, value),
  ];
}

String reportPeriod(ReportDashboard d) =>
    '${CrmFormat.isoDay(d.from)} — ${CrmFormat.isoDay(d.to)}';

/// نص التقرير للمشاركة (واتساب وغيره من قائمة المشاركة).
String reportText(ReportDashboard d, Set<String> sections) {
  final b = StringBuffer('تقرير القادسية • ${reportPeriod(d)}\n');
  for (final (title, rows) in reportTables(d, sections)) {
    b.write('\n*$title*\n');
    if (rows.isEmpty) b.write('لا توجد بيانات\n');
    for (final r in rows) {
      b.write(
        '${[r[0], r[1]].where((x) => x.isNotEmpty).join('. ')}: '
        '${[r[2], r[3], r[4]].where((x) => x.isNotEmpty).join(' • ')}\n',
      );
    }
  }
  return b.toString().trim();
}

/// لوحة التقارير: الشهر الحالي افتراضيًا مع فلاتر الفترة والمندوب والخامة، والمؤشرات
/// والترتيب والاتجاه والطلب مقابل المبيعات وجودة البيانات — ضمن صلاحيات المستخدم.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportFilter _filter = const ReportFilter();
  String _periodLabel = 'هذا الشهر';

  Future<void> _pickPeriod() async {
    final now = ref.read(clockProvider)();
    final month = DateTime(now.year, now.month);
    final options = <(String, DateTime?, DateTime?)>[
      ('هذا الشهر', null, null),
      (
        'الشهر الماضي',
        DateTime(now.year, now.month - 1),
        month.subtract(const Duration(days: 1)),
      ),
      ('آخر 3 أشهر', DateTime(now.year, now.month - 2), now),
      ('هذه السنة', DateTime(now.year), now),
    ];
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final o in options)
              ListTile(
                key: Key('report.period.${o.$1}'),
                title: Text(o.$1),
                onTap: () => Navigator.pop(context, o),
              ),
            ListTile(
              key: const Key('report.period.custom'),
              leading: const Icon(Icons.date_range_rounded),
              title: const Text('فترة مخصصة'),
              onTap: () => Navigator.pop(context, 'custom'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked case (
      final String label,
      final DateTime? from,
      final DateTime? to,
    )) {
      return _apply(label, from, to);
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(start: month, end: now),
    );
    if (range != null) {
      _apply(
        '${CrmFormat.isoDay(range.start)} — ${CrmFormat.isoDay(range.end)}',
        range.start,
        range.end,
      );
    }
  }

  void _apply(String label, DateTime? from, DateTime? to) => setState(() {
    _periodLabel = label;
    _filter = ReportFilter(
      from: from,
      to: to,
      representativeId: _filter.representativeId,
      materialId: _filter.materialId,
    );
  });

  Future<void> _pickFrom(
    String title,
    List<(String, String)> options,
    ReportFilter Function(String?) apply,
  ) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text('كل $title'),
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final (id, label) in options)
                ListTile(
                  key: Key('report.option.$id'),
                  title: Text(label),
                  onTap: () => Navigator.pop(context, id),
                ),
            ],
          ),
        ),
      ),
    );
    if (id != null) setState(() => _filter = apply(id.isEmpty ? null : id));
  }

  Future<void> _export(ReportDashboard d, String format) async {
    final available = {
      for (final k in reportSections.keys)
        if (k != 'suppliers' || d.suppliers != null) k,
    };
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (_) =>
          _ShareDialog(dashboard: d, available: available, format: format),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    final repo = ref.read(crmRepositoryProvider);
    final name = 'تقرير-${CrmFormat.isoDay(d.from)}-${CrmFormat.isoDay(d.to)}';
    try {
      switch (format) {
        case 'excel':
          final bytes = await repo.reportExcel(_filter, chosen.toList());
          await shareExcel(ref, bytes, '$name.xlsx');
        case 'text':
          await repo.authorizeShare('report.text', chosen.length);
          await ref.read(shareServiceProvider).text(reportText(d, chosen));
        case 'pdf' || 'print':
          await repo.authorizeShare('report.$format', chosen.length);
          final doc = TableDocument(
            title: 'تقرير القادسية',
            subtitle: reportPeriod(d),
            headers: const ['#', 'البند', 'عدد', 'الكمية', 'ملاحظة'],
            rows: const [],
            sections: reportTables(d, chosen),
          );
          final documents = ref.read(documentServicesProvider);
          if (format == 'print') {
            await documents.print(doc, name);
          } else {
            final path = await ref
                .read(fileServicesProvider)
                .writeTemp('report', '$name.pdf', await documents.pdf(doc));
            await ref
                .read(shareServiceProvider)
                .file(path, mimeType: 'application/pdf');
          }
      }
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(reportDashboardProvider(_filter));
    final refs = ref.watch(referenceDataProvider).value;
    final canExport = ref.watch(canShareBulkProvider);
    final d = value.value;
    return CrmScaffold(
      title: 'التقارير',
      icon: Icons.bar_chart_rounded,
      actions: [
        if (canExport && d != null)
          PopupMenuButton<String>(
            key: const Key('report.export'),
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
            onSelected: (f) => _export(d, f),
            itemBuilder: (_) => const [
              PopupMenuItem(
                key: Key('report.export.text'),
                value: 'text',
                child: Text('مشاركة نصية (واتساب...)'),
              ),
              PopupMenuItem(
                key: Key('report.export.pdf'),
                value: 'pdf',
                child: Text('مشاركة PDF'),
              ),
              PopupMenuItem(
                key: Key('report.export.excel'),
                value: 'excel',
                child: Text('تصدير Excel'),
              ),
              PopupMenuItem(
                key: Key('report.export.print'),
                value: 'print',
                child: Text('طباعة'),
              ),
            ],
          ),
      ],
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                ActionChip(
                  key: const Key('report.period'),
                  avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(_periodLabel),
                  onPressed: _pickPeriod,
                ),
                const SizedBox(width: 6),
                if (refs != null && refs.representatives.length > 1)
                  ActionChip(
                    key: const Key('report.rep'),
                    label: Text(
                      refs.representatives
                              .where((r) => r.id == _filter.representativeId)
                              .firstOrNull
                              ?.name ??
                          'كل المندوبين',
                    ),
                    onPressed: () => _pickFrom(
                      'المندوبين',
                      [for (final r in refs.representatives) (r.id, r.name)],
                      (id) => ReportFilter(
                        from: _filter.from,
                        to: _filter.to,
                        representativeId: id,
                        materialId: _filter.materialId,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                if (refs != null)
                  ActionChip(
                    key: const Key('report.material'),
                    label: Text(
                      refs.materials
                              .where((m) => m.id == _filter.materialId)
                              .firstOrNull
                              ?.code ??
                          'كل الخامات',
                    ),
                    onPressed: () => _pickFrom(
                      'الخامات',
                      [for (final m in refs.materials) (m.id, m.code)],
                      (id) => ReportFilter(
                        from: _filter.from,
                        to: _filter.to,
                        representativeId: _filter.representativeId,
                        materialId: id,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: value,
              onRetry: () => ref.invalidate(reportDashboardProvider(_filter)),
              data: (d) => _Dashboard(d),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard(this.d);

  final ReportDashboard d;

  @override
  Widget build(BuildContext context) {
    final k = d.kpis;
    final (n, active, follow, stopped) = d.activity;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          reportPeriod(d),
          key: const Key('report.range'),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.9,
          children: [
            _Stat(
              key: const Key('report.completed'),
              label: 'مبيعات محققة (مكتمل)',
              value: _kg(k.completedKg),
              detail: '${k.completedOrders} طلب',
              color: AppColors.greenDark,
            ),
            _Stat(
              key: const Key('report.open'),
              label: 'طلبات مفتوحة',
              value: _kg(k.openKg),
              detail: '${k.openOrders} طلب',
              color: AppColors.primary,
            ),
            _Stat(
              key: const Key('report.cancelled'),
              label: 'ملغى',
              value: _kg(k.cancelledKg),
              detail: '${k.cancelledOrders} طلب',
              color: AppColors.error,
            ),
            _Stat(
              key: const Key('report.conversion'),
              label: 'نسبة التحويل',
              value: k.conversionRate == null
                  ? '—'
                  : '${(k.conversionRate! * 100).toStringAsFixed(0)}%',
              detail: 'مكتمل ÷ (مكتمل + ملغى)',
              color: AppColors.navy,
            ),
            _Stat(
              label: 'عملاء اشتروا',
              value: '${k.activeCustomers}',
              detail: 'جدد ${k.newCustomers} • تواصل ${k.contacts}',
              color: AppColors.primary,
            ),
            const _Stat(
              key: Key('report.value'),
              label: 'قيمة المبيعات',
              value: 'غير متاحة',
              detail: 'الطلبات لا تحمل أسعارًا',
              color: AppColors.textSecondary,
            ),
          ],
        ),
        const FieldLabel('مراحل الطلبات', icon: Icons.filter_alt_rounded),
        SectionCard(
          key: const Key('report.pipeline'),
          child: _Bars([
            for (final p in d.pipeline) (_stage(p.label), p.kg, '${p.orders}'),
          ]),
        ),
        const FieldLabel(
          'الاتجاه الشهري (مكتمل)',
          icon: Icons.show_chart_rounded,
        ),
        SectionCard(
          key: const Key('report.trend'),
          child: _Bars([
            for (final t in d.trend) (t.label, t.kg, '${t.orders}'),
          ]),
        ),
        _Ranked('أعلى الخامات', 'materials', d.materials),
        _Ranked('أعلى الـ Grades', 'grades', d.grades, ltr: true),
        _Ranked('أعلى العملاء', 'customers', d.customers, open: true),
        _Ranked('المندوبون والمديرون', 'representatives', d.representatives),
        if (d.suppliers case final s?)
          _Ranked('الموردون (توريد مستلم)', 'suppliers', s, open: true),
        const FieldLabel('الطلب مقابل المبيعات', icon: Icons.compare_arrows),
        SectionCard(
          key: const Key('report.demand'),
          child: Column(
            children: [
              if (d.demand.isEmpty) const Text('لا توجد بيانات'),
              for (final x in d.demand)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(x.material, textDirection: TextDirection.ltr),
                  subtitle: Text(
                    [
                      'مهتمون: ${x.demandCustomers} عميل',
                      'مبيع: ${_kg(x.soldKg)}',
                      if (x.suppliers case final s?) 'موردون: $s',
                    ].join(' • '),
                  ),
                ),
            ],
          ),
        ),
        const FieldLabel('نشاط العملاء', icon: Icons.groups_rounded),
        Row(
          children: [
            for (final (label, count, color) in [
              ('جديد', n, AppColors.primary),
              ('نشط', active, AppColors.greenDark),
              ('متابعة', follow, AppColors.reportsAccent),
              ('متوقف', stopped, AppColors.error),
            ])
              Expanded(
                child: _Stat(label: label, value: '$count', color: color),
              ),
          ],
        ),
        _Ranked('عملاء خاملون', 'dormant', d.dormant, open: true),
        const FieldLabel('المتابعات', icon: Icons.alarm_rounded),
        Row(
          children: [
            Expanded(
              child: _Stat(
                key: const Key('report.overdue'),
                label: 'متابعات متأخرة',
                value: '${d.overdue}',
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                label: 'متابعات اليوم',
                value: '${d.today}',
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const FieldLabel('جودة البيانات', icon: Icons.rule_rounded),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                key: const Key('report.incomplete'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('سجلات تحتاج استكمال: ${d.incomplete}'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => context.push(CrmRoutes.incomplete),
              ),
              if (d.quality case final q?)
                Column(
                  key: const Key('report.quality'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بلا نوع نشاط: ${q.missingActivity}'),
                    Text('بلا محافظة: ${q.missingGovernorate}'),
                    Text('بلا موقع: ${q.withoutLocation}'),
                    Text('بلا جهة اتصال: ${q.withoutContacts}'),
                    const Divider(),
                    if (q.duplicates.isEmpty)
                      const Text('لا توجد تكرارات محتملة'),
                    for (final g in q.duplicates)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.copy_all_rounded,
                          color: AppColors.error,
                        ),
                        title: Text(g.names.join(' / ')),
                        onTap: () =>
                            context.push(CrmRoutes.party(g.partyIds.first)),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// أعمدة أفقية بسيطة نسبةً لأكبر قيمة (رسم بياني دون مكتبات).
class _Bars extends StatelessWidget {
  const _Bars(this.items);

  final List<(String, double, String)> items;

  @override
  Widget build(BuildContext context) {
    final max = items.fold<double>(0, (m, i) => i.$2 > m ? i.$2 : m);
    return Column(
      children: [
        for (final (label, value, count) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  child: Text(label, style: const TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : value / max,
                      minHeight: 12,
                      backgroundColor: AppColors.fieldFill,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 92,
                  child: Text(
                    '${_kg(value)} ($count)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Ranked extends StatelessWidget {
  const _Ranked(
    this.title,
    this.id,
    this.rows, {
    this.open = false,
    this.ltr = false,
  });

  final String title;
  final String id;
  final List<RankRow> rows;
  final bool open;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(title, icon: Icons.leaderboard_rounded),
      SectionCard(
        key: Key('report.$id'),
        child: Column(
          children: [
            if (rows.isEmpty) const Text('لا توجد بيانات في الفترة'),
            for (final (i, r) in rows.indexed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
                title: Text(
                  r.label,
                  textDirection: ltr ? TextDirection.ltr : null,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if (r.orders > 0) '${r.orders} طلب',
                    _kg(r.kg),
                    ?r.extra,
                  ].join(' • '),
                ),
                onTap: open && r.id != null
                    ? () => context.push(CrmRoutes.party(r.id!))
                    : null,
              ),
          ],
        ),
      ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;
  final Color color;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        Text(label, textAlign: TextAlign.center),
        if (detail case final t?)
          Text(
            t,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    ),
  );
}

/// اختيار الأقسام ومعاينة النص قبل المشاركة أو التصدير.
class _ShareDialog extends StatefulWidget {
  const _ShareDialog({
    required this.dashboard,
    required this.available,
    required this.format,
  });

  final ReportDashboard dashboard;
  final Set<String> available;
  final String format;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late final Set<String> _chosen = {...widget.available};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(switch (widget.format) {
      'excel' => 'تصدير Excel',
      'print' => 'طباعة التقرير',
      'pdf' => 'مشاركة PDF',
      _ => 'مشاركة التقرير',
    }),
    content: SizedBox(
      width: double.maxFinite,
      child: ListView(
        shrinkWrap: true,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final key in widget.available)
                FilterChip(
                  key: Key('report.section.$key'),
                  label: Text(reportSections[key]!),
                  selected: _chosen.contains(key),
                  onSelected: (on) => setState(
                    () => on ? _chosen.add(key) : _chosen.remove(key),
                  ),
                ),
            ],
          ),
          const Divider(),
          const Text('معاينة', style: TextStyle(fontWeight: FontWeight.w700)),
          Container(
            key: const Key('report.preview'),
            padding: const EdgeInsets.all(8),
            color: AppColors.fieldFill,
            child: Text(
              reportText(widget.dashboard, _chosen),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const Key('report.confirm'),
        onPressed: _chosen.isEmpty
            ? null
            : () => Navigator.pop(context, _chosen),
        child: const Text('متابعة'),
      ),
    ],
  );
}
