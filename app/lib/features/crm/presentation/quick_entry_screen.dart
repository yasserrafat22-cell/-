import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/device/file_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'backup_actions.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';
import 'material_picker.dart';

bool _can(WidgetRef ref, String permission) {
  final auth = ref.watch(authControllerProvider);
  return auth is Authenticated && auth.user.can(permission);
}

/// «الإدخال السريع»: إضافة نوع خامة، استيراد Excel للعملاء/الموردين والكتالوج،
/// القوالب، تصدير الكتالوج، والسجلات التي تحتاج استكمال — كلٌ حسب الصلاحية.
class QuickEntryScreen extends ConsumerWidget {
  const QuickEntryScreen({super.key});

  Future<void> _template(
    BuildContext context,
    WidgetRef ref,
    String kind,
  ) async {
    try {
      final bytes = await ref.read(crmRepositoryProvider).importTemplate(kind);
      await shareExcel(
        ref,
        bytes,
        kind == 'parties'
            ? 'قالب-العملاء-والموردين.xlsx'
            : 'قالب-الكتالوج.xlsx',
      );
    } on ApiException catch (e) {
      if (context.mounted) showErrorSnack(context, e.message);
    }
  }

  Future<void> _exportCatalog(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(crmRepositoryProvider).exportCatalog();
      await shareExcel(
        ref,
        bytes,
        'الكتالوج-${CrmFormat.isoDay(ref.read(clockProvider)())}.xlsx',
      );
    } on ApiException catch (e) {
      if (context.mounted) showErrorSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canImport = _can(ref, 'import.run');
    final canAdd =
        _can(ref, 'customers.create') || _can(ref, 'suppliers.create');
    final canExport =
        _can(ref, 'reports.export') || _can(ref, 'masterdata.manage');

    Widget tile(
      String key,
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap,
    ) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        key: Key('quick.$key'),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('الإدخال السريع')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (canAdd)
            tile(
              'addMaterial',
              Icons.category_outlined,
              'إضافة نوع خامة',
              'خامة جديدة باختصارها (مثل ABS) دون Grade',
              () async {
                final id = await addMaterialType(context, ref);
                if (id != null && context.mounted) {
                  showSuccessSnack(context, 'أُضيف نوع الخامة');
                }
              },
            ),
          if (canImport) ...[
            tile(
              'importParties',
              Icons.upload_file_rounded,
              'استيراد عملاء وموردين من Excel',
              'الاسم، الهاتف، Grade، النوع — يكفي حقلان في كل صف',
              () => context.push(CrmRoutes.importFile('parties')),
            ),
            tile(
              'importCatalog',
              Icons.inventory_2_outlined,
              'استيراد الكتالوج من Excel',
              'الخامة، الشركة المصنعة، Grade، بلد الصنع',
              () => context.push(CrmRoutes.importFile('catalog')),
            ),
            tile(
              'template.parties',
              Icons.download_rounded,
              'قالب العملاء والموردين',
              'ملف Excel جاهز بالأعمدة المطلوبة',
              () => _template(context, ref, 'parties'),
            ),
            tile(
              'template.catalog',
              Icons.download_rounded,
              'قالب الكتالوج',
              'ملف Excel جاهز بالأعمدة المطلوبة',
              () => _template(context, ref, 'catalog'),
            ),
          ],
          if (canExport)
            tile(
              'exportCatalog',
              Icons.table_view_rounded,
              'تصدير الكتالوج Excel',
              'كل الخامات والشركات والـ Grades وبلدان الصنع',
              () => _exportCatalog(context, ref),
            ),
          if (canAdd)
            tile(
              'incomplete',
              Icons.pending_actions_rounded,
              'سجلات تحتاج استكمال',
              'غير مصنف، بدون اسم، أو بدون رقم',
              () => context.push(CrmRoutes.incomplete),
            ),
          if (_can(ref, 'masterdata.manage'))
            tile(
              'catalog',
              Icons.settings_outlined,
              'كتالوج الخامات',
              'مراجعة وتعديل الشركات والـ Grades',
              () => context.push(CrmRoutes.catalog),
            ),
        ],
      ),
    );
  }
}

/// معاينة ملف Excel ثم استيراد الصفوف السليمة فقط. تعيين الأعمدة يدويًا يعيد المعاينة.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({required this.kind, super.key});

  /// parties أو catalog.
  final String kind;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  Uint8List? _file;
  ImportResult? _result;
  Map<String, int>? _mapping;
  ImportStatus? _filter;
  bool _busy = false;

  /// معرف ثابت للعملية: إعادة الضغط بعد انقطاع لا تكرر البيانات.
  String? _importId;

  Map<String, String> get _fields => importFields[widget.kind]!;

  Future<void> _run(Future<ImportResult> Function() action) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final bytes = await ref.read(fileServicesProvider).pickAnyBytes();
    if (bytes == null) return;
    setState(() {
      _file = bytes;
      _mapping = null;
      _importId = null;
      _filter = null;
    });
    await _preview();
  }

  Future<void> _preview() => _run(
    () => ref
        .read(crmRepositoryProvider)
        .importPreview(widget.kind, _file!, mapping: _mapping),
  );

  Future<void> _commit() async {
    _importId ??= const Uuid().v7();
    await _run(
      () => ref
          .read(crmRepositoryProvider)
          .importCommit(widget.kind, _importId!, _file!, mapping: _mapping),
    );
    if (_result?.committed ?? false) {
      ref.invalidate(registryProvider);
      ref.invalidate(referenceDataProvider);
      if (mounted) showSuccessSnack(context, 'تم الاستيراد');
    }
  }

  void _remap(String field, int column) {
    final mapping = {...?_mapping ?? _result?.mapping};
    mapping.removeWhere((k, v) => k == field || v == column);
    if (column >= 0) mapping[field] = column;
    // الحقل غير المعين يُرسل -1 حتى لا يعيد السيرفر تخمينه.
    for (final f in _fields.keys) {
      mapping.putIfAbsent(f, () => -1);
    }
    setState(() {
      _mapping = mapping;
      _importId = null;
    });
    _preview();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final title = widget.kind == 'parties'
        ? 'استيراد عملاء وموردين'
        : 'استيراد الكتالوج';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            Text(
              widget.kind == 'parties'
                  ? 'يكفي حقلان من: الاسم، الهاتف، Grade، النوع. الصف بلا نوع يُسجل «غير مصنف» '
                        'ويُحدد لاحقًا. الرقم غير الصحيح والسجل الموجود لدى غيرك يذهبان للمراجعة ولا يُستوردان.'
                  : 'الخامة والشركة المصنعة والـ Grade وبلد الصنع. الموجود يُعاد استخدامه، ونفس الكود '
                        'لشركة أخرى مسموح، والصف الغامض يُعلَّم للمراجعة دون تخمين.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('import.pick'),
              onPressed: _pick,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(
                _file == null ? 'اختيار ملف Excel' : 'اختيار ملف آخر',
              ),
            ),
            if (result != null) ...[
              if (result.previousImportAt case final at?)
                Card(
                  color: AppColors.reportsAccent.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      key: const Key('import.previous'),
                      'هذا الملف استُورد من قبل بتاريخ ${CrmFormat.isoDay(at)}. '
                      'الموجود لن يتكرر.',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in ImportStatus.values)
                    FilterChip(
                      key: Key('import.count.${s.name}'),
                      label: Text('${s.label}: ${result.counts[s]}'),
                      selected: _filter == s,
                      onSelected: (on) =>
                          setState(() => _filter = on ? s : null),
                    ),
                ],
              ),
              if (!result.committed)
                ExpansionTile(
                  key: const Key('import.mapping'),
                  title: const Text('تعيين الأعمدة'),
                  children: [
                    for (final MapEntry(key: field, value: label)
                        in _fields.entries)
                      ListTile(
                        title: Text(label),
                        trailing: DropdownButton<int>(
                          key: Key('import.map.$field'),
                          value: (_mapping ?? result.mapping)[field] ?? -1,
                          items: [
                            const DropdownMenuItem(value: -1, child: Text('—')),
                            for (final (i, h) in result.headers.indexed)
                              DropdownMenuItem(
                                value: i,
                                child: Text(h.isEmpty ? 'عمود ${i + 1}' : h),
                              ),
                          ],
                          onChanged: (v) => _remap(field, v ?? -1),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              for (final row in result.rows.where(
                (r) => _filter == null || r.status == _filter,
              ))
                _RowTile(row: row, fields: _fields),
              const SizedBox(height: 80),
            ],
          ],
        ),
      ),
      bottomNavigationBar: result == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: result.committed
                    ? FilledButton(
                        key: const Key('import.done'),
                        onPressed: () => context.pop(),
                        child: const Text('تم — رجوع'),
                      )
                    : FilledButton.icon(
                        key: const Key('import.commit'),
                        onPressed: result.importable == 0 || _busy
                            ? null
                            : _commit,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          'استيراد الصفوف السليمة (${result.importable})',
                        ),
                      ),
              ),
            ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.fields});

  final ImportRow row;
  final Map<String, String> fields;

  Color get _color => switch (row.status) {
    ImportStatus.newRow => AppColors.greenDark,
    ImportStatus.existing || ImportStatus.duplicate => AppColors.primary,
    ImportStatus.invalid || ImportStatus.review => AppColors.error,
  };

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final MapEntry(:key, value: label) in fields.entries)
        if (row.values[key] case final v? when v.isNotEmpty) '$label: $v',
    ].join(' • ');
    return Card(
      key: Key('import.row.${row.row}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: _color.withValues(alpha: 0.15),
          child: Text(
            '${row.row}',
            style: TextStyle(color: _color, fontSize: 12),
          ),
        ),
        title: Text(
          '${row.status.label}  $values',
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: row.notes.isEmpty ? null : Text(row.notes.join('\n')),
      ),
    );
  }
}

/// «استكمال البيانات»: يملأ الفارغ فقط (الاسم المفقود، أول رقم، نوع غير المصنف).
Future<void> completePartyData(
  BuildContext context,
  WidgetRef ref,
  PartyDetail party,
) async {
  final auth = ref.read(authControllerProvider);
  final user = auth is Authenticated ? auth.user : null;
  final values = await showDialog<(String?, String?, bool, bool)>(
    context: context,
    builder: (_) => _CompleteDialog(
      party: party,
      canCustomer: user?.can('customers.create') ?? false,
      canSupplier: user?.can('suppliers.create') ?? false,
    ),
  );
  if (values == null || !context.mounted) return;
  final (name, phone, customer, supplier) = values;
  try {
    await ref
        .read(crmRepositoryProvider)
        .completeParty(
          party.id,
          name: name,
          phone: phone,
          isCustomer: customer,
          isSupplier: supplier,
        );
    refreshParty(ref, party.id);
    ref.invalidate(registryProvider);
    if (context.mounted) showSuccessSnack(context, 'تم استكمال البيانات');
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({
    required this.party,
    required this.canCustomer,
    required this.canSupplier,
  });

  final PartyDetail party;
  final bool canCustomer;
  final bool canSupplier;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _customer = false;
  bool _supplier = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.party;
    String? clean(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return AlertDialog(
      title: const Text('استكمال البيانات'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.nameMissing)
              TextField(
                key: const Key('complete.name'),
                controller: _name,
                decoration: formDecoration(hint: 'اسم الشركة'),
              ),
            if (p.phones.isEmpty) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('complete.phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: formDecoration(hint: 'رقم الهاتف'),
              ),
            ],
            if (p.unclassified) ...[
              const SizedBox(height: 12),
              Text(
                p.pendingGrade == null
                    ? 'حدد النوع'
                    : 'حدد النوع (Grade المعلق: ${p.pendingGrade})',
              ),
              if (widget.canCustomer)
                CheckboxListTile(
                  key: const Key('complete.customer'),
                  value: _customer,
                  title: const Text('عميل'),
                  onChanged: (v) => setState(() => _customer = v ?? false),
                ),
              if (widget.canSupplier)
                CheckboxListTile(
                  key: const Key('complete.supplier'),
                  value: _supplier,
                  title: const Text('مورد'),
                  onChanged: (v) => setState(() => _supplier = v ?? false),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('complete.save'),
          onPressed: () {
            final result = (clean(_name), clean(_phone), _customer, _supplier);
            if (result.$1 == null &&
                result.$2 == null &&
                !_customer &&
                !_supplier) {
              return;
            }
            Navigator.pop(context, result);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
