import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/material_spec.dart';

/// هيكل شاشات التسجيل والملفات (ص8، ص9): شريط أزرق داكن بعنوان وأيقونة
/// وسهم رجوع، ومحتوى أبيض بحواف علوية دائرية، وزر حفظ ثابت أسفل الشاشة.
class CrmScaffold extends StatelessWidget {
  const CrmScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    this.bottom,
    this.actions = const [],
  });

  final String title;
  final IconData icon;
  final Widget body;
  final Widget? bottom;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B3C78),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [AppColors.navy, AppColors.primary],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(icon, color: Colors.white, size: 30),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ...actions,
                    IconButton(
                      key: const Key('crm.back'),
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                      // التصميم يضع سهم الرجوع يسار الشريط متجهًا لليسار.
                      icon: const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              clipBehavior: Clip.antiAlias,
              child: body,
            ),
          ),
          if (bottom != null)
            ColoredBox(
              color: AppColors.background,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: bottom,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// عنوان الحقل: أيقونة وعنوان عريض ونجمة حمراء للحقول الإلزامية.
class FieldLabel extends StatelessWidget {
  const FieldLabel(
    this.text, {
    super.key,
    required this.icon,
    this.required = false,
  });

  final String text;
  final IconData icon;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (required)
            const Text(
              ' *',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

InputDecoration formDecoration({String? hint, Widget? suffix, Widget? prefix}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.fieldBorder),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.hint, fontSize: 15),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
    ),
    suffixIcon: suffix,
    prefixIcon: prefix,
  );
}

/// شريط معلومات ملون (تسجيل سريع / استكمال لاحق).
class InfoStrip extends StatelessWidget {
  const InfoStrip({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.green = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool green;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = green ? const Color(0xFFE8F6DF) : const Color(0xFFEAF3FC);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: green ? const Color(0xFFF2B01E) : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (subtitle != null) TextSpan(text: ' $subtitle'),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, this.icon);

  final T value;
  final String label;
  final IconData icon;
}

/// اختيار واحد بمربعات أيقونات (نوع النشاط، نوع التواصل).
class ChoiceTiles<T> extends StatelessWidget {
  const ChoiceTiles({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'choice',
  });

  final List<ChoiceOption<T>> options;
  final T? selected;
  final ValueChanged<T> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, option) in options.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _Tile(
              key: Key('$keyPrefix.${option.value}'),
              option: option,
              selected: option.value == selected,
              onTap: () => onChanged(option.value),
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile<T> extends StatelessWidget {
  const _Tile({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.navy;
    return Semantics(
      selected: selected,
      button: true,
      label: option.label,
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            height: 74,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.navy : AppColors.fieldBorder,
              ),
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.primary, AppColors.navy],
                    )
                  : const LinearGradient(
                      colors: [Colors.white, Color(0xFFF3F6FA)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(option.icon, color: fg, size: 26),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// حقل اختيار متعدد بشرائح (الخامات المهتم بها / المتاحة).
/// حقل الخامات المختارة كشرائح كاملة المواصفات، والضغط عليه يضيف خامة.
class SpecsField extends StatelessWidget {
  const SpecsField({
    super.key,
    required this.specs,
    required this.onRemove,
    required this.onAdd,
    this.hint = 'اختر الخامات',
  });

  final List<MaterialSpec> specs;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('chips.add'),
      borderRadius: BorderRadius.circular(12),
      onTap: onAdd,
      child: InputDecorator(
        decoration: formDecoration(
          suffix: const Icon(Icons.add_rounded, color: AppColors.navy),
        ),
        isEmpty: specs.isEmpty,
        child: specs.isEmpty
            ? Text(hint, style: const TextStyle(color: AppColors.hint))
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (i, spec) in specs.indexed)
                    SpecChip(spec, onRemove: () => onRemove(i)),
                ],
              ),
      ),
    );
  }
}

/// زر حفظ بعرض الشاشة (أزرق داكن متدرج بأيقونة حفظ).
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary, AppColors.navy],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('crm.save'),
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : onPressed,
          child: SizedBox(
            height: 56,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.save_rounded, color: Colors.white),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زر إجراء ملون (اتصال أزرق، واتساب أخضر) كما في ملف العميل.
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.outlined = false,
    this.height = 50,
  });

  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;
  final bool outlined;
  final double height;

  static const blue = [AppColors.primary, AppColors.navy];
  static const green = [Color(0xFF3FBF3F), Color(0xFF1E8E2A)];
  static const red = [AppColors.error, Color(0xFFB3261E)];

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? AppColors.navy : Colors.white;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: outlined ? Colors.white : null,
          border: outlined ? Border.all(color: AppColors.fieldBorder) : null,
          gradient: outlined
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: outlined ? AppColors.primary : fg),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// مربع مؤشر في «نظرة عامة» (آخر طلب، الكمية، آخر تواصل، الخامات).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF5FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4E5F7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// شارة صغيرة (نوع النشاط، الحالة).
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.color = const Color(0xFFDFF3D3),
    this.textColor = AppColors.greenDark,
    this.icon,
  });

  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;

  static Pill forStatusColor(String text, bool good, bool warn) => Pill(
    text,
    color: good
        ? const Color(0xFFDFF3D3)
        : warn
        ? const Color(0xFFFFF1D6)
        : const Color(0xFFFDE2E2),
    textColor: good
        ? AppColors.greenDark
        : warn
        ? const Color(0xFF9A6200)
        : AppColors.error,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// صف معلومات بإطار (العنوان، المندوب).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// تبويبات الملف (نظرة عامة/الطلبات/التواصل/التفاصيل).
class SegmentTabs extends StatelessWidget {
  const SegmentTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: GestureDetector(
                key: Key('tab.$i'),
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: i == selected
                        ? const LinearGradient(
                            colors: [AppColors.primary, AppColors.navy],
                          )
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: i == selected
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة قسم بإطار خفيف (جدول خامات الطلب، نتائج التواصل).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // Material (لا Container) حتى تظهر تأثيرات اللمس للعناصر داخل البطاقة.
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.fieldBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

void showSuccessSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.greenDark),
    );
}

void showErrorSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
}

/// شريحة خامة بالترتيب المعتمد: النوع · الشركة المصنّعة · Grade · بلد الصنع.
/// الأجزاء من اليسار لليمين وكل جزء نص مستقل، فلا يختلط اتجاه العربي
/// والإنجليزي، وتلتف لسطر ثانٍ على الشاشات الضيقة بدل قص المعلومات.
class SpecChip extends StatelessWidget {
  const SpecChip(this.spec, {super.key, this.onRemove});

  final MaterialSpec spec;
  final VoidCallback? onRemove;

  static const openColor = Color(0xFFFFF1D6);
  static const openText = Color(0xFF9A6200);

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AppColors.navy,
    );
    final maker = switch (spec.precision) {
      SpecPrecision.open => ('أي شركة', base.copyWith(color: openText)),
      SpecPrecision.unknownManufacturer => (
        'الشركة غير محددة',
        base.copyWith(
          color: AppColors.hint,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
        ),
      ),
      _ =>
        spec.manufacturerName == null ? null : (spec.manufacturerName!, base),
    };
    final parts = <(String, TextStyle)>[
      (spec.materialCode, base.copyWith(fontWeight: FontWeight.w900)),
      ?maker,
      if (spec.gradeCode case final g?) (g, base),
      if (spec.originName case final o?) (o, base),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: spec.isOpen ? openColor : AppColors.fieldFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        textDirection: TextDirection.ltr,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: [
          for (final (i, (text, style)) in parts.indexed) ...[
            if (i > 0)
              const Text(
                '·',
                style: TextStyle(color: AppColors.hint, fontSize: 12.5),
              ),
            Text(text, style: style),
          ],
          if (!spec.gradeVerified)
            const Tooltip(
              message: 'بانتظار التحقق',
              child: Icon(
                Icons.hourglass_top_rounded,
                size: 14,
                color: openText,
              ),
            ),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// حقل في [askFields].
class DialogField {
  const DialogField(
    this.hint, {
    this.initial = '',
    this.ltr = false,
    this.maxLength,
  });

  final String hint;
  final String initial;
  final bool ltr;
  final int? maxLength;
}

/// نافذة بحقول نصية تعيد القيم بعد «حفظ» أو null عند الإلغاء. تملك
/// المتحكمات بنفسها فلا تُغلق قبل انتهاء حركة الإغلاق.
Future<List<String>?> askFields(
  BuildContext context, {
  required String title,
  required List<DialogField> fields,
  String confirm = 'حفظ',
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => _FieldsDialog(title: title, fields: fields, confirm: confirm),
);

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({
    required this.title,
    required this.fields,
    required this.confirm,
  });

  final String title;
  final List<DialogField> fields;
  final String confirm;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final _controllers = [
    for (final f in widget.fields) TextEditingController(text: f.initial),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, f) in widget.fields.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: Key('dialog.field.$i'),
              controller: _controllers[i],
              autofocus: i == 0,
              maxLength: f.maxLength,
              textDirection: f.ltr ? TextDirection.ltr : null,
              decoration: formDecoration(hint: f.hint),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const Key('dialog.confirm'),
        onPressed: () {
          final values = [for (final c in _controllers) c.text.trim()];
          if (values.every((v) => v.isNotEmpty)) Navigator.pop(context, values);
        },
        child: Text(widget.confirm),
      ),
    ],
  );
}

/// علامة فورية بجانب رقم الهاتف: أخضر إن كان صحيحًا وأحمر إن لم يكن.
Widget? phoneStatusIcon(String text, String? Function(String) check) {
  if (text.trim().isEmpty) return null;
  final ok = check(text) == null;
  return Icon(
    ok ? Icons.check_circle_rounded : Icons.error_rounded,
    key: Key(ok ? 'phone.valid' : 'phone.invalid'),
    color: ok ? const Color(0xFF1E8E2A) : AppColors.error,
  );
}
