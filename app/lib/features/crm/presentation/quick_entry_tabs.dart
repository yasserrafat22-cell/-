import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/device/document_services.dart';
import '../../../core/device/file_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import '../domain/quick_entry.dart';
import 'backup_actions.dart';
import 'crm_widgets.dart';
import 'quick_entry_review.dart';
import 'quick_entry_widgets.dart';

String _newId() => const Uuid().v7();

/// هامش التبويبات مع مسافة شريط النظام السفلي؛ لوحة المفاتيح تعالجها الشاشة (resize).
EdgeInsets _safePadding(BuildContext context) => EdgeInsets.fromLTRB(
  12,
  12,
  12,
  12 + MediaQuery.viewPaddingOf(context).bottom,
);

Future<bool?> _openReview(
  BuildContext context, {
  required String method,
  required String audience,
  required List<EntryRow> rows,
  String? fileName,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(
    builder: (_) => QuickReviewScreen(
      method: method,
      audience: audience,
      rows: rows,
      fileName: fileName,
    ),
  ),
);

Widget _notice(
  String text, {
  Key? key,
  Color color = AppColors.textSecondary,
}) => Padding(
  padding: const EdgeInsets.only(top: 6),
  child: Text(
    text,
    key: key,
    style: TextStyle(color: color, fontSize: 13),
  ),
);

/// ١) اللصق المباشر: أسطر من واتساب أو Excel أو أي نص، بأعمدة (Tab/فواصل) أو نص حر.
class PasteTab extends ConsumerStatefulWidget {
  const PasteTab({super.key});

  @override
  ConsumerState<PasteTab> createState() => _PasteTabState();
}

class _PasteTabState extends ConsumerState<PasteTab> {
  final _text = TextEditingController();
  String? _audience;
  PasteParse? _parse;
  Map<String, int> _mapping = {};
  bool _header = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _analyze(ReferenceData refs) {
    final p = parsePaste(_text.text, refs);
    // السطر الأول عناوين إن لم يكن فيه رقم موبايل وكان بعده أسطر.
    final phoneCol = p.mapping['phone'];
    final first = p.cells.isEmpty ? const <String>[] : p.cells.first;
    final header =
        !p.free &&
        p.cells.length > 1 &&
        (phoneCol == null ||
            phoneCol >= first.length ||
            normalizeMobile(first[phoneCol]).length != 11);
    setState(() {
      _parse = p;
      _header = header;
      _mapping = header
          ? suggestMapping(p.cells.skip(1).toList(), refs)
          : {...p.mapping};
    });
  }

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider).value;
    final canCustomer = quickCan(ref, 'customers.create');
    final canSupplier = quickCan(ref, 'suppliers.create');
    _audience ??= canCustomer ? 'customer' : (canSupplier ? 'supplier' : null);
    final p = _parse;
    final data = p == null
        ? const <List<String>>[]
        : (_header ? p.cells.skip(1).toList() : p.cells);
    final missing = [
      for (final f in const ['name', 'phone'])
        if (!_mapping.containsKey(f)) quickFieldLabels[f]!,
    ];

    return SingleChildScrollView(
      key: const Key('paste.view'),
      // مسافة شريط النظام (أزرار أندرويد الثلاثة أو الإيماءات) أسفل آخر زر.
      padding: _safePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuickCard(
            title: 'نوع السجلات',
            icon: Icons.people_alt_outlined,
            child: QuickChoice<String>(
              keyPrefix: 'paste.audience',
              options: [
                ('customer', 'عملاء', canCustomer),
                ('supplier', 'موردون', canSupplier),
              ],
              selected: _audience,
              onChanged: (v) => setState(() => _audience = v),
            ),
          ),
          QuickCard(
            title: 'الصق البيانات',
            icon: Icons.content_paste_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('paste.text'),
                  controller: _text,
                  minLines: 5,
                  maxLines: 10,
                  onChanged: (_) {
                    setState(() => _parse = null);
                  },
                  decoration: formDecoration(
                    hint:
                        'كل سطر سجل: الاسم، الرقم، الخامة، Grade\n'
                        'من Excel أو واتساب أو مفصول بفواصل',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('paste.analyze'),
                        onPressed:
                            refs == null ||
                                _audience == null ||
                                _text.text.trim().isEmpty
                            ? null
                            : () => _analyze(refs),
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('تحليل'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: const Key('paste.clear'),
                      onPressed: () => setState(() {
                        _text.clear();
                        _parse = null;
                      }),
                      child: const Text('مسح'),
                    ),
                  ],
                ),
                if (_audience == null)
                  _notice(
                    'ليست لديك صلاحية إضافة عملاء أو موردين.',
                    color: AppColors.error,
                  ),
              ],
            ),
          ),
          if (p != null && refs != null) ...[
            if (p.cells.isEmpty)
              _notice('لا توجد أسطر.')
            else ...[
              QuickCard(
                title: p.free
                    ? 'نص حر: ${p.cells.length} سطر'
                    : 'تعيين الأعمدة: ${data.length} صف',
                icon: Icons.view_column_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.free)
                      const Text(
                        'استُخرج الرقم من كل سطر، والخامة والـ Grade إن طابقا الكتالوج، '
                        'والباقي اسم. راجع كل صف قبل الحفظ.',
                      )
                    else ...[
                      CheckboxListTile(
                        key: const Key('paste.header'),
                        contentPadding: EdgeInsets.zero,
                        value: _header,
                        title: const Text('السطر الأول عناوين أعمدة'),
                        onChanged: (v) => setState(() {
                          _header = v ?? false;
                          _mapping = _header
                              ? suggestMapping(p.cells.skip(1).toList(), refs)
                              : suggestMapping(p.cells, refs);
                        }),
                      ),
                      const Text(
                        'تأكد من أن كل حقل على العمود الصحيح:',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      MappingEditor(
                        headers: _header
                            ? p.cells.first
                            : [
                                for (var c = 0; c < p.columns; c++)
                                  'عمود ${c + 1}',
                              ],
                        samples: data.isEmpty ? const [] : data.first,
                        mapping: _mapping,
                        onChanged: (m) => setState(() => _mapping = m),
                      ),
                      if (missing.isNotEmpty)
                        _notice(
                          'لم يُحدد عمود: ${missing.join('، ')} — ستذهب الصفوف لـ«بانتظار الاستكمال».',
                          key: const Key('paste.missing'),
                          color: const Color(0xFF9A6200),
                        ),
                    ],
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('paste.review'),
                onPressed: data.isEmpty
                    ? null
                    : () async {
                        final rows = rowsFrom(
                          data,
                          p.free ? p.mapping : _mapping,
                          newId: _newId,
                          kind: _audience,
                          firstRow: _header ? 2 : 1,
                          flags: p.free ? p.flags : null,
                        );
                        final done = await _openReview(
                          context,
                          method: 'paste',
                          audience: _audience!,
                          rows: rows,
                        );
                        if (done == true && mounted) {
                          setState(() {
                            _text.clear();
                            _parse = null;
                          });
                        }
                      },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('مراجعة الصفوف'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// ٢) استيراد Excel على 4 مراحل: الملف والورقة ← تعيين الأعمدة ← المراجعة ← الملخص.
class ExcelTab extends ConsumerStatefulWidget {
  const ExcelTab({super.key});

  @override
  ConsumerState<ExcelTab> createState() => _ExcelTabState();
}

class _ExcelTabState extends ConsumerState<ExcelTab> {
  PickedFile? _file;
  List<ExcelSheetData> _sheets = const [];
  int _sheet = 0;
  String? _audience;
  Map<String, int> _mapping = {};
  bool _loading = false;
  String? _error;

  Future<void> _pick() async {
    final file = await ref.read(fileServicesProvider).pickDocument(const [
      'xlsx',
      'xls',
    ]);
    if (file == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sheets = await ref
          .read(crmRepositoryProvider)
          .quickReadExcel(file.path, file.name);
      if (!mounted) return;
      setState(() {
        _file = file;
        _sheets = sheets;
        _sheet = 0;
        _mapping = sheets.isEmpty ? {} : {...sheets.first.mapping};
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!quickCan(ref, 'import.run')) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'استيراد Excel للسكرتارية والإدارة فقط.',
            key: Key('excel.denied'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final canCustomer = quickCan(ref, 'customers.create');
    final canSupplier = quickCan(ref, 'suppliers.create');
    final sheet = _sheets.isEmpty ? null : _sheets[_sheet];
    final stage = sheet == null ? 1 : (_audience == null ? 2 : 3);
    final needKind = _audience == 'mixed' && !_mapping.containsKey('kind');

    return SingleChildScrollView(
      key: const Key('excel.view'),
      // مسافة شريط النظام (أزرار أندرويد الثلاثة أو الإيماءات) أسفل آخر زر.
      padding: _safePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Stages(current: stage),
          QuickCard(
            title: '١. الملف',
            icon: Icons.upload_file_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  key: const Key('excel.pick'),
                  onPressed: _loading ? null : _pick,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_rounded),
                  label: Text(
                    _file == null ? 'اختيار ملف Excel (xlsx)' : 'تغيير الملف',
                  ),
                ),
                if (_error != null)
                  _notice(
                    _error!,
                    key: const Key('excel.error'),
                    color: AppColors.error,
                  ),
                if (_file != null && sheet != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _file!.name,
                    key: const Key('excel.fileName'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (_sheets.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DropdownButtonFormField<int>(
                        key: const Key('excel.sheet'),
                        initialValue: _sheet,
                        isExpanded: true,
                        decoration: formDecoration().copyWith(
                          labelText: 'الورقة',
                        ),
                        items: [
                          for (final (i, s) in _sheets.indexed)
                            DropdownMenuItem(value: i, child: Text(s.name)),
                        ],
                        onChanged: (i) => setState(() {
                          _sheet = i ?? 0;
                          _mapping = {..._sheets[_sheet].mapping};
                        }),
                      ),
                    ),
                  _notice(
                    'الورقة «${sheet.name}»: ${sheet.rows.length} صف',
                    key: const Key('excel.rowCount'),
                  ),
                ],
              ],
            ),
          ),
          if (sheet != null) ...[
            QuickCard(
              title: '٢. نوع السجلات وتعيين الأعمدة',
              icon: Icons.view_column_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QuickChoice<String>(
                    keyPrefix: 'excel.audience',
                    options: [
                      ('customer', 'العملاء فقط', canCustomer),
                      ('supplier', 'الموردون فقط', canSupplier),
                      (
                        'mixed',
                        'العملاء والموردون معًا',
                        canCustomer && canSupplier,
                      ),
                    ],
                    selected: _audience,
                    onChanged: (v) => setState(() => _audience = v),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'ترتيب الأعمدة لا يهم؛ تأكد من العمود الصحيح لكل حقل:',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  MappingEditor(
                    headers: sheet.headers,
                    samples: sheet.rows.isEmpty ? const [] : sheet.rows.first,
                    mapping: _mapping,
                    fields: [
                      'name',
                      'phone',
                      'material',
                      'grade',
                      'manufacturer',
                      'origin',
                      if (_audience == 'mixed') 'kind',
                    ],
                    onChanged: (m) => setState(() => _mapping = m),
                  ),
                  if (needKind)
                    _notice(
                      'الاستيراد المختلط يحتاج عمود «نوع السجل» (عميل/مورد)؛ '
                      'لا يُخمَّن النوع.',
                      key: const Key('excel.needKind'),
                      color: AppColors.error,
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              key: const Key('excel.review'),
              onPressed: _audience == null || needKind || sheet.rows.isEmpty
                  ? null
                  : () async {
                      final rows = rowsFrom(
                        sheet.rows,
                        _mapping,
                        newId: _newId,
                        kind: _audience == 'mixed' ? null : _audience,
                        // رقم الصف في الملف الأصلي (بعد صفوف العنوان والصفوف الفارغة).
                        firstRow: sheet.headerRow + 1,
                        sourceRows: sheet.sourceRows,
                      );
                      final done = await _openReview(
                        context,
                        method: 'excel',
                        audience: _audience!,
                        rows: rows,
                        // اسم الملف والورقة لتتبع مصدر الصفوف في سجل الدفعات.
                        fileName: _file == null
                            ? null
                            : _sheets.length > 1
                            ? '${_file!.name} — ${sheet.name}'
                            : _file!.name,
                      );
                      if (done == true && mounted) {
                        setState(() {
                          _file = null;
                          _sheets = const [];
                          _audience = null;
                        });
                      }
                    },
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('٣. مراجعة الصفوف'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stages extends StatelessWidget {
  const _Stages({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    const labels = ['الملف', 'الأعمدة', 'المراجعة', 'الملخص'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          for (final (i, l) in labels.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: i + 1 <= current
                        ? AppColors.primary
                        : AppColors.fieldBorder,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ٣) التصدير الذكي: الجمهور ← النطاق (الكل أو خامة وGrade) ← Excel أو PDF أو طباعة،
/// كلها من نفس الاستعلام، صف لكل خامة/Grade، والأرقام نصًا بالصفر.
class ExportTab extends ConsumerStatefulWidget {
  const ExportTab({super.key});

  @override
  ConsumerState<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends ConsumerState<ExportTab> {
  String _audience = 'customer';
  bool _byMaterial = false;
  String? _materialId;
  String? _gradeId;
  ExportData? _preview;
  bool _busy = false;

  void _changed(VoidCallback f) => setState(() {
    f();
    _preview = null;
  });

  String? get _mid => _byMaterial ? _materialId : null;
  String? get _gid => _byMaterial ? _gradeId : null;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fileBase() {
    final who = switch (_audience) {
      'supplier' => 'الموردون',
      'mixed' => 'العملاء-والموردون',
      _ => 'العملاء',
    };
    return '$who-${CrmFormat.isoDay(ref.read(clockProvider)())}';
  }

  TableDocument _document(ExportData d, ReferenceData? refs) {
    const headers = ['الاسم', 'الموبايل', 'الخامة', 'Grade', 'الشركة المصنعة'];
    List<List<String>> rows(String kind) => [
      for (final r in d.rows)
        if (r.kind == kind)
          [
            r.name,
            r.phone ?? '',
            r.material ?? '',
            r.grade ?? '',
            r.manufacturer ?? '',
          ],
    ];
    final material = _mid == null ? null : refs?.material(_mid!)?.code;
    final grade = _gid == null ? null : refs?.grade(_gid!)?.code;
    final scope = material == null
        ? 'كل البيانات'
        : '$material — ${grade ?? 'جميع الجريدات'}';
    return TableDocument(
      title: 'تصدير البيانات',
      subtitle: '$scope · ${CrmFormat.isoDay(ref.read(clockProvider)())}',
      headers: headers,
      rows: const [],
      sections: [
        if (_audience != 'supplier')
          ('العملاء (${d.customers})', rows('customer')),
        if (_audience != 'customer')
          ('الموردون (${d.suppliers})', rows('supplier')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!quickCan(ref, 'reports.export')) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'التصدير لمن لديه صلاحية التقارير والتصدير.',
            key: Key('export.denied'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final canSuppliers = ref.watch(canSeeSuppliersProvider);
    final refs = ref.watch(referenceDataProvider).value;
    final material = _materialId == null ? null : refs?.material(_materialId!);
    final grade = _gradeId == null ? null : refs?.grade(_gradeId!);
    final ready = !_byMaterial || _materialId != null;
    final d = _preview;

    return SingleChildScrollView(
      key: const Key('export.view'),
      // مسافة شريط النظام (أزرار أندرويد الثلاثة أو الإيماءات) أسفل آخر زر.
      padding: _safePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuickCard(
            title: 'أ. الجمهور',
            icon: Icons.groups_2_outlined,
            child: QuickChoice<String>(
              keyPrefix: 'export.audience',
              options: [
                ('customer', 'العملاء', true),
                ('supplier', 'الموردون', canSuppliers),
                ('mixed', 'العملاء والموردون', canSuppliers),
              ],
              selected: _audience,
              onChanged: (v) => _changed(() => _audience = v),
            ),
          ),
          QuickCard(
            title: 'ب. النطاق',
            icon: Icons.filter_alt_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QuickChoice<bool>(
                  keyPrefix: 'export.scope',
                  options: const [
                    (false, 'كل البيانات', true),
                    (true, 'حسب الخامة', true),
                  ],
                  selected: _byMaterial,
                  onChanged: (v) => _changed(() => _byMaterial = v),
                ),
                if (_byMaterial && refs != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('export.material'),
                    icon: const Icon(Icons.layers_rounded),
                    label: Text(material?.code ?? 'اختر الخامة'),
                    onPressed: () async {
                      final id = await pickOne(
                        context,
                        title: 'الخامة',
                        keyPrefix: 'exMaterial',
                        selected: _materialId,
                        options: [
                          for (final m in refs.materials)
                            (
                              m.id,
                              m.code,
                              m.nameAr == m.code ? null : m.nameAr,
                            ),
                        ],
                      );
                      if (id != null && id.isNotEmpty) {
                        _changed(() {
                          if (id != _materialId) _gradeId = null;
                          _materialId = id;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('export.grade'),
                    icon: const Icon(Icons.view_in_ar_rounded),
                    label: Text(
                      grade == null
                          ? 'جميع الجريدات'
                          : gradeOptionLabel(refs, grade),
                    ),
                    onPressed: material == null
                        ? null
                        : () async {
                            final id = await pickOne(
                              context,
                              title: 'Grade — ${material.code}',
                              keyPrefix: 'exGrade',
                              selected: _gradeId,
                              noneLabel: 'جميع الجريدات',
                              options: [
                                for (final g in material.grades)
                                  (g.id, gradeOptionLabel(refs, g), null),
                              ],
                            );
                            if (id != null) {
                              _changed(() => _gradeId = id.isEmpty ? null : id);
                            }
                          },
                  ),
                ],
              ],
            ),
          ),
          FilledButton.icon(
            key: const Key('export.preview'),
            onPressed: _busy || !ready
                ? null
                : () => _run(() async {
                    final r = await ref
                        .read(crmRepositoryProvider)
                        .exportData(_audience, materialId: _mid, gradeId: _gid);
                    if (mounted) setState(() => _preview = r);
                  }),
            icon: const Icon(Icons.preview_rounded),
            label: const Text('معاينة'),
          ),
          if (d != null) ...[
            const SizedBox(height: 10),
            QuickCard(
              title: 'المعاينة',
              icon: Icons.table_rows_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (_audience != 'supplier')
                        Pill(
                          'عملاء: ${d.customers}',
                          key: const Key('export.customers'),
                        ),
                      if (_audience != 'customer')
                        Pill(
                          'موردون: ${d.suppliers}',
                          key: const Key('export.suppliers'),
                          color: const Color(0xFFE6F0FC),
                          textColor: AppColors.primary,
                        ),
                      Pill(
                        'صفوف: ${d.rows.length}',
                        key: const Key('export.rows'),
                        color: AppColors.fieldFill,
                        textColor: AppColors.textPrimary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final r in d.rows.take(20))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '${kindLabel(r.kind)} · ${r.name} · ${r.phone ?? ''} · ${r.material ?? ''} ${r.grade ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  if (d.rows.length > 20)
                    _notice('… و${d.rows.length - 20} صف آخر في الملف'),
                  if (d.rows.isEmpty) _notice('لا توجد نتائج لهذا النطاق.'),
                ],
              ),
            ),
            QuickCard(
              title: 'ج. الإخراج',
              icon: Icons.ios_share_rounded,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('export.excel'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.spreadsheetGreen,
                    ),
                    onPressed: _busy || d.rows.isEmpty
                        ? null
                        : () => _run(() async {
                            final bytes = await ref
                                .read(crmRepositoryProvider)
                                .exportExcel(
                                  _audience,
                                  materialId: _mid,
                                  gradeId: _gid,
                                );
                            await shareExcel(ref, bytes, '${_fileBase()}.xlsx');
                          }),
                    icon: const Icon(Icons.table_view_rounded),
                    label: const Text('Excel'),
                  ),
                  FilledButton.icon(
                    key: const Key('export.pdf'),
                    onPressed: _busy || d.rows.isEmpty
                        ? null
                        : () => _run(() async {
                            final bytes = await ref
                                .read(documentServicesProvider)
                                .pdf(_document(d, refs));
                            await sharePdf(ref, bytes, '${_fileBase()}.pdf');
                          }),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('PDF'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('export.print'),
                    onPressed: _busy || d.rows.isEmpty
                        ? null
                        : () => _run(
                            () => ref
                                .read(documentServicesProvider)
                                .print(_document(d, refs), _fileBase()),
                          ),
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('طباعة'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
