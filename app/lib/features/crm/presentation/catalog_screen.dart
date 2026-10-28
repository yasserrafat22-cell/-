import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/catalog_models.dart';
import '../domain/crm_models.dart';
import 'crm_widgets.dart';
import 'quick_add_party_screen.dart' show AsyncBody;

final catalogGradesProvider = FutureProvider.autoDispose
    .family<List<CatalogGrade>, (String?, bool)>(
      (ref, key) => ref
          .watch(crmRepositoryProvider)
          .catalogGrades(materialId: key.$1, pendingOnly: key.$2),
    );

final catalogManufacturersProvider =
    FutureProvider.autoDispose<List<CatalogManufacturer>>(
      (ref) => ref.watch(crmRepositoryProvider).catalogManufacturers(),
    );

/// كتالوج الخامات للإدارة: الخامات ← الشركات ← الـ Grades وبلدانها، ومراجعة
/// ما أضافه المندوبون «بانتظار التحقق». لا حذف؛ الإيقاف فقط.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  int _tab = 0;
  String? _materialId;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    ref
      ..invalidate(catalogGradesProvider)
      ..invalidate(catalogManufacturersProvider)
      ..invalidate(referenceDataProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider);
    final pending = ref.watch(catalogGradesProvider((null, true))).value;
    return CrmScaffold(
      title: 'كتالوج الخامات',
      icon: Icons.inventory_2_rounded,
      body: AsyncBody(
        value: refs,
        onRetry: _refresh,
        data: (refs) {
          _materialId ??= refs.materials.firstOrNull?.id;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              SegmentTabs(
                labels: [
                  'الخامات',
                  'الشركات',
                  'بانتظار التحقق (${pending?.length ?? 0})',
                ],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 12),
              ...switch (_tab) {
                0 => _materials(refs),
                1 => _manufacturers(),
                _ => _pending(refs),
              },
            ],
          );
        },
      ),
    );
  }

  List<Widget> _materials(ReferenceData refs) {
    final grades = ref.watch(catalogGradesProvider((_materialId, false)));
    final query = _search.text.trim().toLowerCase();
    return [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final m in refs.materials)
            ChoiceChip(
              key: Key('catalog.material.${m.code}'),
              label: Text(m.code),
              selected: m.id == _materialId,
              showCheckmark: false,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: m.id == _materialId
                    ? Colors.white
                    : AppColors.textPrimary,
              ),
              onSelected: (_) => setState(() => _materialId = m.id),
            ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: formDecoration(
          hint: 'ابحث بالشركة أو Grade',
          prefix: const Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 10),
      grades.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => TextButton(
          onPressed: _refresh,
          child: const Text('تعذر التحميل — إعادة المحاولة'),
        ),
        data: (list) {
          final visible = list.where(
            (g) =>
                query.isEmpty ||
                g.code.toLowerCase().contains(query) ||
                (g.manufacturerName ?? '').toLowerCase().contains(query),
          );
          final groups = <String?, List<CatalogGrade>>{};
          for (final g in visible) {
            (groups[g.manufacturerId] ??= []).add(g);
          }
          final keys = groups.keys.toList()
            ..sort((a, b) {
              if (a == null) return 1;
              if (b == null) return -1;
              return groups[a]!.first.manufacturerName!.compareTo(
                groups[b]!.first.manufacturerName!,
              );
            });
          if (keys.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'لا توجد Grades مسجلة لهذه الخامة بعد',
                textAlign: TextAlign.center,
              ),
            );
          }
          return Column(
            children: [
              for (final k in keys)
                _MakerGroup(
                  name: k == null
                      ? 'الشركة غير محددة (بيانات سابقة)'
                      : groups[k]!.first.manufacturerName!,
                  grades: groups[k]!,
                  refs: refs,
                  onEdit: (g) => _editGrade(g, refs),
                  onVerify: (g) => _run(
                    () => ref.read(crmRepositoryProvider).verifyGrade(g.id),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _manufacturers() {
    final makers = ref.watch(catalogManufacturersProvider);
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const Key('catalog.addMaker'),
          onPressed: () async {
            final name = await _askText('شركة مصنّعة جديدة', '');
            if (name != null) {
              await _run(
                () => ref.read(crmRepositoryProvider).createManufacturer(name),
              );
            }
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة شركة'),
        ),
      ),
      ...makers.when(
        loading: () => [const Center(child: CircularProgressIndicator())],
        error: (_, _) => [
          TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
        ],
        data: (list) => [
          for (final m in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SectionCard(
                child: Row(
                  children: [
                    Icon(
                      Icons.factory_rounded,
                      color: m.active ? AppColors.primary : AppColors.hint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.active ? m.name : '${m.name} (موقوفة)',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${m.gradeCount} Grade',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    IconButton(
                      tooltip: 'تعديل',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final name = await _askText('تعديل اسم الشركة', m.name);
                        if (name != null) {
                          await _run(
                            () => ref
                                .read(crmRepositoryProvider)
                                .updateManufacturer(
                                  m.id,
                                  name,
                                  active: m.active,
                                ),
                          );
                        }
                      },
                    ),
                    Switch(
                      value: m.active,
                      onChanged: (v) => _run(
                        () => ref
                            .read(crmRepositoryProvider)
                            .updateManufacturer(m.id, m.name, active: v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _pending(ReferenceData refs) {
    final pending = ref.watch(catalogGradesProvider((null, true)));
    return pending.when(
      loading: () => [const Center(child: CircularProgressIndicator())],
      error: (_, _) => [
        TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
      ],
      data: (list) => list.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد إضافات بانتظار التحقق',
                  textAlign: TextAlign.center,
                ),
              ),
            ]
          : [
              for (final g in list)
                _MakerGroup(
                  name:
                      '${g.materialCode} · ${g.manufacturerName ?? 'الشركة غير محددة'}',
                  grades: [g],
                  refs: refs,
                  onEdit: (g) => _editGrade(g, refs),
                  onVerify: (g) => _run(
                    () => ref.read(crmRepositoryProvider).verifyGrade(g.id),
                  ),
                ),
            ],
    );
  }

  Future<String?> _askText(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('catalog.text'),
          controller: controller,
          autofocus: true,
          decoration: formDecoration(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('catalog.textSave'),
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _editGrade(CatalogGrade grade, ReferenceData refs) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GradeEditor(grade: grade, refs: refs),
    );
    if (saved == true) _refresh();
  }
}

class _MakerGroup extends StatelessWidget {
  const _MakerGroup({
    required this.name,
    required this.grades,
    required this.refs,
    required this.onEdit,
    required this.onVerify,
  });

  final String name;
  final List<CatalogGrade> grades;
  final ReferenceData refs;
  final ValueChanged<CatalogGrade> onEdit;
  final ValueChanged<CatalogGrade> onVerify;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.factory_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ],
          ),
          for (final g in grades)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const SizedBox(width: 26),
                  Text(
                    g.code,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      decoration: g.active ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      g.verified
                          ? [
                              for (final o in g.originIds)
                                refs.country(o)?.nameAr,
                            ].nonNulls.join(' • ')
                          : 'بانتظار التحقق${g.createdByName == null ? '' : ' • أضافه ${g.createdByName}'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  if (!g.verified && g.manufacturerId != null)
                    TextButton.icon(
                      key: Key('catalog.verify.${g.code}'),
                      onPressed: () => onVerify(g),
                      icon: const Icon(Icons.verified_rounded, size: 18),
                      label: const Text('اعتماد'),
                    ),
                  IconButton(
                    key: Key('catalog.edit.${g.code}'),
                    tooltip: 'تعديل',
                    onPressed: () => onEdit(g),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// تعديل Grade: الشركة (ومنها ربط Grade قديم بشركته يدويًا)، الكود، بلدان
/// الصنع، والإيقاف.
class _GradeEditor extends ConsumerStatefulWidget {
  const _GradeEditor({required this.grade, required this.refs});

  final CatalogGrade grade;
  final ReferenceData refs;

  @override
  ConsumerState<_GradeEditor> createState() => _GradeEditorState();
}

class _GradeEditorState extends ConsumerState<_GradeEditor> {
  late final _code = TextEditingController(text: widget.grade.code);
  late String? _makerId = widget.grade.manufacturerId;
  late final _origins = {...widget.grade.originIds};
  late bool _active = widget.grade.active;
  late List<LookupItem> _countries = widget.refs.countries;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _addCountry() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة بلد صنع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: formDecoration(hint: 'الاسم بالعربية'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: code,
              textDirection: TextDirection.ltr,
              maxLength: 2,
              decoration: formDecoration(hint: 'الكود الدولي (مثل SA)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final added = await ref
            .read(crmRepositoryProvider)
            .createCountry(code.text.trim(), name.text.trim());
        setState(() {
          _countries = [..._countries, added];
          _origins.add(added.id);
        });
      } on ApiException catch (e) {
        setState(() => _error = e.message);
      }
    }
    code.dispose();
    name.dispose();
  }

  Future<void> _save() async {
    try {
      await ref
          .read(crmRepositoryProvider)
          .updateGrade(
            widget.grade.id,
            manufacturerId: _makerId,
            code: _code.text.trim(),
            originIds: _origins.toList(),
            description: widget.grade.description,
            active: _active,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'تعديل ${widget.grade.materialCode} · ${widget.grade.code}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const FieldLabel('الشركة المصنّعة', icon: Icons.factory_outlined),
          DropdownButtonFormField<String?>(
            key: const Key('catalog.maker'),
            initialValue: _makerId,
            isExpanded: true,
            decoration: formDecoration(),
            items: [
              if (widget.grade.manufacturerId == null)
                const DropdownMenuItem(
                  value: null,
                  child: Text('الشركة غير محددة'),
                ),
              for (final m in widget.refs.manufacturers)
                DropdownMenuItem(value: m.id, child: Text(m.name)),
            ],
            onChanged: (v) => setState(() => _makerId = v),
          ),
          const SizedBox(height: 12),
          const FieldLabel('كود الـ Grade', icon: Icons.qr_code_rounded),
          TextField(
            controller: _code,
            textDirection: TextDirection.ltr,
            decoration: formDecoration(),
          ),
          const SizedBox(height: 12),
          const FieldLabel('بلدان الصنع', icon: Icons.public_rounded),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _countries)
                FilterChip(
                  label: Text(c.nameAr),
                  selected: _origins.contains(c.id),
                  onSelected: (v) => setState(
                    () => v ? _origins.add(c.id) : _origins.remove(c.id),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('بلد آخر'),
                onPressed: _addCountry,
              ),
            ],
          ),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('مفعّل (يظهر في الاختيار)'),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('catalog.saveGrade'),
            onPressed: _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}
