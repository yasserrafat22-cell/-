import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/crm_models.dart';
import '../domain/quick_entry.dart';
import 'crm_widgets.dart';

/// صلاحية المستخدم الحالي (للعرض فقط؛ السيرفر هو من يقرر).
bool quickCan(WidgetRef ref, String permission) {
  final auth = ref.watch(authControllerProvider);
  return auth is Authenticated && auth.user.can(permission);
}

/// بطاقة قسم مضغوطة بعنوان (نفس طابع بطاقات التطبيق).
class QuickCard extends StatelessWidget {
  const QuickCard({super.key, required this.child, this.title, this.icon});

  final String? title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE3EAF5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: AppColors.primary, size: 20),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    ),
  );
}

/// اختيار واحد بنقرة (خيارات متجاورة تلتف عند الضيق).
class QuickChoice<T> extends StatelessWidget {
  const QuickChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'choice',
  });

  final List<(T, String, bool)> options;
  final T? selected;
  final ValueChanged<T> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (value, label, enabled) in options)
        ChoiceChip(
          key: Key('$keyPrefix.$value'),
          label: Text(label),
          selected: value == selected,
          onSelected: enabled ? (_) => onChanged(value) : null,
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: value == selected
                ? Colors.white
                : enabled
                ? AppColors.textPrimary
                : AppColors.hint,
            fontWeight: FontWeight.w700,
          ),
          showCheckmark: false,
        ),
    ],
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = switch (status) {
      'ready' => ('جاهز', const Color(0xFFDFF3D3), AppColors.greenDark),
      'completed' => ('أُضيف', const Color(0xFFDFF3D3), AppColors.greenDark),
      'duplicate' => (
        'مكرر محتمل',
        const Color(0xFFFFF1D6),
        const Color(0xFF9A6200),
      ),
      'failed' => ('بلا صلاحية', const Color(0xFFFDE4E4), AppColors.error),
      'excluded' => ('مستبعد', AppColors.fieldFill, AppColors.textSecondary),
      _ => ('بانتظار الاستكمال', const Color(0xFFE6F0FC), AppColors.primary),
    };
    return Pill(text, color: bg, textColor: fg);
  }
}

/// قائمة بحث لاختيار واحد (الخامة أو الـ Grade من الكتالوج الموحد).
Future<String?> pickOne(
  BuildContext context, {
  required String title,
  required List<(String, String, String?)> options,
  String? selected,
  String keyPrefix = 'pick',
  String? noneLabel,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _PickSheet(
    title: title,
    options: options,
    selected: selected,
    keyPrefix: keyPrefix,
    noneLabel: noneLabel,
  ),
);

class _PickSheet extends StatefulWidget {
  const _PickSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.keyPrefix,
    this.noneLabel,
  });

  final String title;
  final List<(String, String, String?)> options;
  final String? selected;
  final String keyPrefix;
  final String? noneLabel;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final shown = [
      for (final o in widget.options)
        if (q.isEmpty ||
            o.$2.toLowerCase().contains(q) ||
            (o.$3 ?? '').toLowerCase().contains(q))
          o,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: Key('${widget.keyPrefix}.search'),
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: formDecoration(
                  hint: 'اكتب للبحث',
                  prefix: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (widget.noneLabel != null)
                    ListTile(
                      key: Key('${widget.keyPrefix}.none'),
                      title: Text(widget.noneLabel!),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  for (final (id, label, sub) in shown)
                    ListTile(
                      key: Key('${widget.keyPrefix}.option.$label'),
                      dense: true,
                      selected: id == widget.selected,
                      title: Text(
                        label,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                      ),
                      subtitle: sub == null ? null : Text(sub),
                      onTap: () => Navigator.pop(context, id),
                    ),
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'لا نتائج في الكتالوج',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String gradeOptionLabel(ReferenceData refs, GradeItem g) {
  final maker = g.manufacturerId == null
      ? null
      : refs.manufacturer(g.manufacturerId!)?.name;
  return maker == null ? g.code : '${g.code} — $maker';
}

/// تعديل صف (في المراجعة أو «بانتظار الاستكمال»): الخامة والـ Grade من الكتالوج الموحد فقط،
/// والنقص يظهر فورًا بنفس قواعد السيرفر. لا شيء يُحفظ حتى «حفظ».
class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.row,
    required this.audience,
    required this.refs,
    this.actions,
  });

  final EntryRow row;

  /// customer أو supplier أو mixed (يظهر اختيار النوع في المختلط فقط).
  final String audience;
  final ReferenceData refs;

  /// أزرار إضافية تحت الحقول (الاستكمال، الاستبعاد...).
  final List<Widget> Function(EntryRow edited, LocalCheck check)? actions;

  @override
  State<EntryEditor> createState() => EntryEditorState();
}

class EntryEditorState extends State<EntryEditor> {
  late final _name = TextEditingController(text: widget.row.name);
  late final _phone = TextEditingController(text: widget.row.phone);
  late String? _kind = widget.row.kind;
  late String? _materialId = widget.row.materialId;
  late String? _gradeId = widget.row.gradeId;

  @override
  void initState() {
    super.initState();
    // ربط النص بالكتالوج إن طابقه تمامًا (دون تخمين)، حتى تظهر القوائم مختارة.
    final check = checkRow(widget.row, widget.audience, widget.refs);
    _materialId ??= check.material?.id;
    _gradeId ??= check.grade?.id;
    if (widget.audience == 'mixed') _kind ??= check.kind;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  EntryRow get edited => EntryRow(
    id: widget.row.id,
    row: widget.row.row,
    kind: widget.audience == 'mixed' ? _kind : widget.audience,
    name: _name.text.trim().isEmpty ? null : _name.text.trim(),
    phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
    material: _materialId == null ? widget.row.material : null,
    grade: _gradeId == null ? widget.row.grade : null,
    manufacturer: _gradeId == null ? widget.row.manufacturer : null,
    materialId: _materialId,
    gradeId: _gradeId,
  );

  Future<void> _pickMaterial() async {
    final refs = widget.refs;
    final id = await pickOne(
      context,
      title: 'الخامة',
      keyPrefix: 'qeMaterial',
      selected: _materialId,
      options: [
        for (final m in refs.materials)
          (m.id, m.code, m.nameAr == m.code ? null : m.nameAr),
      ],
    );
    if (id == null || !mounted) return;
    setState(() {
      // تغيير الخامة يمسح الـ Grade غير التابع لها.
      if (id != _materialId) _gradeId = null;
      _materialId = id;
    });
  }

  Future<void> _pickGrade() async {
    final refs = widget.refs;
    final material = _materialId == null ? null : refs.material(_materialId!);
    if (material == null) {
      showErrorSnack(context, 'اختر الخامة أولًا');
      return;
    }
    final id = await pickOne(
      context,
      title: 'Grade — ${material.code}',
      keyPrefix: 'qeGrade',
      selected: _gradeId,
      options: [
        for (final g in material.grades)
          (g.id, gradeOptionLabel(refs, g), null),
      ],
    );
    if (id != null && mounted) setState(() => _gradeId = id);
  }

  @override
  Widget build(BuildContext context) {
    final refs = widget.refs;
    final row = edited;
    final check = checkRow(row, widget.audience, refs);
    final issues = check.issues.toSet();
    InputDecoration deco(String hint, {bool? ok}) => formDecoration(
      hint: hint,
      suffix: ok == null
          ? null
          : Icon(
              ok ? Icons.check_circle_rounded : Icons.error_rounded,
              color: ok ? AppColors.greenDark : AppColors.error,
            ),
    );
    final material = _materialId == null ? null : refs.material(_materialId!);
    final grade = _gradeId == null ? null : refs.grade(_gradeId!);
    Widget picker(
      String key,
      String label,
      String? value,
      String? raw,
      bool bad,
      VoidCallback onTap,
    ) => InkWell(
      key: Key(key),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: deco(
          label,
          ok: value == null ? (raw == null ? null : false) : !bad,
        ),
        isEmpty: value == null && raw == null,
        child: value == null && raw == null
            ? null
            : Text(
                value ?? '«$raw» غير موجود في الكتالوج — اختر',
                style: TextStyle(color: value == null ? AppColors.error : null),
              ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.audience == 'mixed') ...[
          const FieldLabel('نوع السجل', icon: Icons.category_outlined),
          QuickChoice<String>(
            keyPrefix: 'qeKind',
            options: const [
              ('customer', 'عميل', true),
              ('supplier', 'مورد', true),
            ],
            selected: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
        ],
        const FieldLabel(
          'الاسم',
          icon: Icons.apartment_rounded,
          required: true,
        ),
        TextField(
          key: const Key('qe.name'),
          controller: _name,
          onChanged: (_) => setState(() {}),
          decoration: deco(
            'اسم الشركة',
            ok: _name.text.trim().isEmpty
                ? null
                : !issues.contains('name_invalid'),
          ),
        ),
        const FieldLabel(
          'رقم الموبايل',
          icon: Icons.phone_rounded,
          required: true,
        ),
        TextField(
          key: const Key('qe.phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-٠-٩]')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: deco(
            '01XXXXXXXXX',
            ok: _phone.text.trim().isEmpty
                ? null
                : !issues.contains('phone_invalid'),
          ),
        ),
        const FieldLabel('الخامة', icon: Icons.layers_rounded, required: true),
        picker(
          'qe.material',
          'اختر الخامة',
          material?.code,
          _materialId == null ? widget.row.material : null,
          issues.contains('material_unknown'),
          _pickMaterial,
        ),
        const FieldLabel(
          'Grade',
          icon: Icons.view_in_ar_rounded,
          required: true,
        ),
        picker(
          'qe.grade',
          'اختر الـ Grade',
          grade == null ? null : gradeOptionLabel(refs, grade),
          _gradeId == null ? widget.row.grade : null,
          issues.contains('grade_unknown'),
          _pickGrade,
        ),
        const SizedBox(height: 10),
        if (check.issues.isNotEmpty)
          Text(
            'ناقص: ${check.issues.map(issueLabel).join('، ')}',
            key: const Key('qe.issues'),
            style: const TextStyle(color: AppColors.error, fontSize: 13),
          )
        else
          const Text(
            'مكتمل — جاهز ليصبح بطاقة',
            key: Key('qe.complete'),
            style: TextStyle(color: AppColors.greenDark, fontSize: 13),
          ),
        const SizedBox(height: 10),
        ...?widget.actions?.call(row, check),
      ],
    );
  }
}

/// تعيين الأعمدة: لكل حقل عمود (أو «غير موجود»)؛ العمود لا يُستخدم لحقلين.
class MappingEditor extends StatelessWidget {
  const MappingEditor({
    super.key,
    required this.headers,
    required this.samples,
    required this.mapping,
    required this.onChanged,
    this.fields = const ['name', 'phone', 'material', 'grade', 'manufacturer'],
  });

  final List<String> headers;

  /// أول صف بيانات لكل عمود (لتوضيح العمود).
  final List<String> samples;
  final Map<String, int> mapping;
  final ValueChanged<Map<String, int>> onChanged;
  final List<String> fields;

  String _column(int c) {
    final h = c < headers.length && headers[c].trim().isNotEmpty
        ? headers[c].trim()
        : 'عمود ${c + 1}';
    final s = c < samples.length ? samples[c].trim() : '';
    return s.isEmpty || s == h ? h : '$h — $s';
  }

  @override
  Widget build(BuildContext context) {
    final width = [
      headers.length,
      samples.length,
    ].reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<int>(
              key: Key('map.$f'),
              initialValue: mapping[f] ?? -1,
              isExpanded: true,
              decoration: formDecoration(hint: quickFieldLabels[f])
                  .copyWith(labelText: quickFieldLabels[f]),
              items: [
                const DropdownMenuItem(value: -1, child: Text('— غير موجود —')),
                for (var c = 0; c < width; c++)
                  DropdownMenuItem(
                    value: c,
                    child: Text(
                      _column(c),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (c) {
                final next = {...mapping}..remove(f);
                if (c != null && c >= 0) {
                  next.removeWhere((_, v) => v == c);
                  next[f] = c;
                }
                onChanged(next);
              },
            ),
          ),
      ],
    );
  }
}
