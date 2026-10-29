import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/catalog_models.dart';
import '../domain/crm_models.dart';
import 'crm_widgets.dart';
import 'grade_files.dart';

/// يفتح شاشة «اختيار الخامة» ويعيد الاختيار أو null عند الرجوع.
/// [allowOpen] يُظهر «أي شركة وأي Grade مقبول» (لطلبات واهتمامات العملاء فقط).
Future<SpecChoice?> pickSpec(
  BuildContext context, {
  required bool allowOpen,
  SpecChoice? initial,
}) => Navigator.of(context).push<SpecChoice>(
  MaterialPageRoute(
    builder: (_) =>
        MaterialPickerScreen(allowOpen: allowOpen, initial: initial),
  ),
);

/// نوع الخامة ← الشركة المصنّعة و Grade ← بلد الصنع (اختياري).
class MaterialPickerScreen extends ConsumerStatefulWidget {
  const MaterialPickerScreen({
    super.key,
    required this.allowOpen,
    this.initial,
  });

  final bool allowOpen;
  final SpecChoice? initial;

  @override
  ConsumerState<MaterialPickerScreen> createState() =>
      _MaterialPickerScreenState();
}

class _MaterialPickerScreenState extends ConsumerState<MaterialPickerScreen> {
  final _search = TextEditingController();
  late String? _materialId = widget.initial?.materialId;
  late String? _gradeId = widget.initial?.gradeId;
  late bool _open = widget.initial?.open ?? false;
  late String? _originId = widget.initial?.originId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  SpecChoice? get _choice => _materialId == null
      ? null
      : SpecChoice(
          materialId: _materialId!,
          gradeId: _open ? null : _gradeId,
          originId: _originId,
          open: _open,
        );

  Future<void> _addGrade(ReferenceData refs) async {
    final material = refs.material(_materialId!)!;
    final gradeId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddGradeSheet(material: material, refs: refs),
    );
    if (gradeId == null || !mounted) return;
    ref.invalidate(referenceDataProvider);
    await ref.read(referenceDataProvider.future);
    if (mounted) {
      setState(() {
        _gradeId = gradeId;
        _open = false;
      });
    }
  }

  Future<void> _otherCountry(ReferenceData refs) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        children: [
          for (final c in refs.countries)
            ListTile(
              key: Key('country.${c.code}'),
              title: Text(c.nameAr),
              onTap: () => Navigator.of(context).pop(c.id),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _originId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider);
    final choice = _choice;
    return CrmScaffold(
      title: 'اختيار الخامة',
      icon: Icons.layers_rounded,
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (choice != null && refs.hasValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SpecChip(choice.describe(refs.requireValue)),
                ),
              ),
            ActionPill(
              key: const Key('spec.done'),
              label: 'إضافة الخامة',
              icon: Icons.check_rounded,
              colors: ActionPill.blue,
              onTap: choice == null
                  ? null
                  : () => Navigator.of(context).pop(choice),
            ),
          ],
        ),
      ),
      body: switch (refs) {
        AsyncData(:final value) => _body(value),
        AsyncError() => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(referenceDataProvider),
            child: const Text('تعذر تحميل الخامات — إعادة المحاولة'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(ReferenceData refs) {
    final material = _materialId == null ? null : refs.material(_materialId!);
    final query = _search.text.trim().toLowerCase();
    final grades =
        [
          for (final g in material?.grades ?? const <GradeItem>[])
            if (query.isEmpty ||
                g.code.toLowerCase().contains(query) ||
                (g.manufacturerId != null &&
                    (refs.manufacturer(g.manufacturerId!)?.name ?? '')
                        .toLowerCase()
                        .contains(query)))
              g,
        ]..sort(
          (a, b) => _makerName(refs, a).compareTo(_makerName(refs, b)) != 0
              ? _makerName(refs, a).compareTo(_makerName(refs, b))
              : a.code.compareTo(b.code),
        );
    final grade = _gradeId == null ? null : refs.grade(_gradeId!);
    final suggestedOrigins = {
      ...?grade?.originIds,
      ?_originId,
    }.map(refs.country).nonNulls.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const FieldLabel('1. نوع الخامة', icon: Icons.category_rounded),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in refs.materials)
              _Chip(
                key: Key('spec.material.${m.code}'),
                label: m.code,
                selected: m.id == _materialId,
                onTap: () => setState(() {
                  if (_materialId != m.id) {
                    _materialId = m.id;
                    _gradeId = null;
                  }
                }),
              ),
            _Chip(
              key: const Key('spec.addMaterial'),
              label: '+ نوع خامة',
              selected: false,
              onTap: () async {
                final added = await addMaterialType(context, ref);
                if (added != null && mounted) {
                  setState(() {
                    _materialId = added;
                    _gradeId = null;
                  });
                }
              },
            ),
          ],
        ),
        if (material != null) ...[
          const SizedBox(height: 14),
          const FieldLabel(
            '2. الشركة المصنّعة و Grade',
            icon: Icons.factory_outlined,
          ),
          TextField(
            key: const Key('spec.search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: formDecoration(
              hint: 'ابحث بالـ Grade أو الشركة',
              prefix: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.allowOpen)
            _Option(
              key: const Key('spec.open'),
              selected: _open,
              open: true,
              onTap: () => setState(() {
                _open = true;
                _gradeId = null;
              }),
              title: 'أي شركة وأي Grade مقبول (مواصفات مفتوحة)',
            ),
          _Option(
            key: const Key('spec.unspecified'),
            selected: !_open && _gradeId == null,
            onTap: () => setState(() {
              _open = false;
              _gradeId = null;
            }),
            title: 'النوع فقط — Grade غير محدد بعد',
            muted: true,
          ),
          for (final g in grades)
            _Option(
              key: Key('spec.grade.${g.code}'),
              selected: !_open && g.id == _gradeId,
              onTap: () => setState(() {
                _open = false;
                _gradeId = g.id;
              }),
              code: g.code,
              title: g.manufacturerId == null
                  ? 'الشركة غير محددة'
                  : refs.manufacturer(g.manufacturerId!)?.name ?? '',
              muted: g.manufacturerId == null,
              pending: !g.verified,
              trailing: [for (final o in g.originIds) refs.country(o)?.nameAr]
                  .nonNulls
                  .join(' • '),
            ),
          TextButton.icon(
            key: const Key('spec.addGrade'),
            onPressed: () => _addGrade(refs),
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة Grade غير موجود'),
          ),
          if (grades.where((g) => g.id == _gradeId).firstOrNull
              case final selected?)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('صورة الـ Grade وملف المواصفات')),
                  GradeFilesBar(
                    gradeId: selected.id,
                    photoFileId: selected.photoFileId,
                    dataSheetFileId: selected.dataSheetFileId,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          const FieldLabel(
            '3. بلد الصنع (اختياري)',
            icon: Icons.public_rounded,
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(
                key: const Key('spec.origin.none'),
                label: 'غير محدد',
                selected: _originId == null,
                onTap: () => setState(() => _originId = null),
              ),
              for (final c in suggestedOrigins)
                _Chip(
                  key: Key('spec.origin.${c.code}'),
                  label: c.nameAr,
                  selected: c.id == _originId,
                  onTap: () => setState(() => _originId = c.id),
                ),
              _Chip(
                key: const Key('spec.origin.other'),
                label: 'بلد آخر',
                icon: Icons.add_rounded,
                selected: false,
                onTap: () => _otherCountry(refs),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _makerName(ReferenceData refs, GradeItem g) =>
      g.manufacturerId == null
      ? '\u{10FFFF}'
      : refs.manufacturer(g.manufacturerId!)?.name ?? '';
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.primary : Colors.white,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.fieldBorder,
      ),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.selected,
    required this.onTap,
    required this.title,
    this.code,
    this.open = false,
    this.muted = false,
    this.pending = false,
    this.trailing = '',
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? code;
  final bool open;
  final bool muted;
  final bool pending;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final border = open
        ? const Color(0xFFF5C46B)
        : selected
        ? AppColors.primary
        : AppColors.fieldBorder;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: open
            ? const Color(0xFFFFF7E8)
            : selected
            ? const Color(0xFFE5F0FC)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  open
                      ? Icons.all_inclusive_rounded
                      : selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: open ? SpecChip.openText : AppColors.primary,
                ),
                const SizedBox(width: 10),
                if (code != null) ...[
                  Text(
                    code!,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: code == null
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: muted ? AppColors.hint : AppColors.textSecondary,
                      fontStyle: muted && code != null
                          ? FontStyle.italic
                          : null,
                    ),
                  ),
                ),
                if (pending) const Pill('بانتظار التحقق'),
                if (trailing.isNotEmpty)
                  Text(
                    trailing,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// إضافة Grade غير موجود: الشركة المصنّعة (من القائمة أو جديدة) والكود.
/// يُحفظ «بانتظار التحقق» للمندوب، ويعيد معرف الـ Grade.
class _AddGradeSheet extends ConsumerStatefulWidget {
  const _AddGradeSheet({required this.material, required this.refs});

  final MaterialItem material;
  final ReferenceData refs;

  @override
  ConsumerState<_AddGradeSheet> createState() => _AddGradeSheetState();
}

class _AddGradeSheetState extends ConsumerState<_AddGradeSheet> {
  final _maker = TextEditingController();
  final _makerFocus = FocusNode();
  final _code = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _maker.dispose();
    _makerFocus.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save({bool confirmSimilar = false}) async {
    final makerName = _maker.text.trim();
    final code = _code.text.trim();
    if (makerName.isEmpty || code.isEmpty) {
      setState(() => _error = 'اكتب الشركة المصنّعة وكود الـ Grade');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(crmRepositoryProvider);
    try {
      final maker = await repo.createManufacturer(makerName);
      final grade = await repo.createGrade(
        materialId: widget.material.id,
        manufacturerId: maker.id,
        code: code,
        confirmSimilar: confirmSimilar,
      );
      if (mounted) Navigator.of(context).pop(grade.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.code == 'catalog.similar_grade' && e.data is List) {
        final similar = (e.data! as List)
            .cast<Json>()
            .map(CatalogGrade.fromJson)
            .toList();
        final use = await _askSimilar(similar);
        if (!mounted || use == null) return;
        if (use.isEmpty) {
          await _save(confirmSimilar: true);
        } else {
          Navigator.of(context).pop(use);
        }
        return;
      }
      setState(() => _error = e.message);
    }
  }

  /// يعيد معرف Grade موجود لاستخدامه، أو '' لإضافة الجديد، أو null للإلغاء.
  Future<String?> _askSimilar(List<CatalogGrade> similar) => showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('يوجد Grade بنفس الكود'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in similar)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(g.code, textDirection: TextDirection.ltr),
              subtitle: Text(g.manufacturerName ?? 'الشركة غير محددة'),
              trailing: TextButton(
                onPressed: () => Navigator.of(context).pop(g.id),
                child: const Text('استخدامه'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('grade.confirmNew'),
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('إضافة كـ Grade مختلف'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final names = widget.refs.manufacturers.map((m) => m.name).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'إضافة Grade لخامة ${widget.material.code}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'يُحفظ بانتظار تحقق المدير، ويمكن استخدامه الآن.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          const FieldLabel('الشركة المصنّعة', icon: Icons.factory_outlined),
          RawAutocomplete<String>(
            textEditingController: _maker,
            focusNode: _makerFocus,
            optionsBuilder: (v) => v.text.trim().isEmpty
                ? const Iterable<String>.empty()
                : names.where(
                    (n) =>
                        n.toLowerCase().contains(v.text.trim().toLowerCase()),
                  ),
            fieldViewBuilder: (context, controller, focus, onSubmit) =>
                TextField(
                  key: const Key('grade.maker'),
                  controller: controller,
                  focusNode: focus,
                  decoration: formDecoration(hint: 'مثال: SABIC'),
                ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: AlignmentDirectional.topStart,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 220,
                    maxWidth: 320,
                  ),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final o in options)
                        ListTile(title: Text(o), onTap: () => onSelected(o)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const FieldLabel('كود الـ Grade', icon: Icons.qr_code_rounded),
          TextField(
            key: const Key('grade.code'),
            controller: _code,
            textDirection: TextDirection.ltr,
            decoration: formDecoration(hint: 'مثال: PP500'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('grade.save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('إضافة'),
          ),
        ],
      ),
    );
  }
}

/// «إضافة نوع خامة» أساسي (PP، ABS، PA...) دون مصنع أو Grade؛ يعمل دون اتصال.
/// يعيد معرف الخامة (الجديدة أو الموجودة بنفس الاختصار).
Future<String?> addMaterialType(BuildContext context, WidgetRef ref) async {
  final values = await askFields(
    context,
    title: 'إضافة نوع خامة',
    fields: const [
      DialogField('الاختصار (مثل ABS أو PA)', ltr: true, maxLength: 32),
      DialogField('الاسم بالعربي (اختياري)', maxLength: 80, optional: true),
    ],
  );
  if (values == null || values[0].trim().isEmpty || !context.mounted) {
    return null;
  }
  try {
    final material = await ref
        .read(crmRepositoryProvider)
        .createMaterialType(
          values[0],
          nameAr: values[1].trim().isEmpty ? null : values[1].trim(),
        );
    ref.invalidate(referenceDataProvider);
    await ref.read(referenceDataProvider.future);
    return material.id;
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
    return null;
  }
}
