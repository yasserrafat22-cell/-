import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import '../domain/phone_rules.dart';
import 'contact_launcher.dart';
import 'crm_widgets.dart';

/// قسم «الموظفون وجهات الاتصال»: الإضافة لمن يرى السجل، والتعديل والحذف للمدير.
class ContactsSection extends ConsumerWidget {
  const ContactsSection({super.key, required this.party});

  final PartyDetail party;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    PartyContact? existing,
    required bool first,
  }) async {
    final result = await showDialog<PartyContact>(
      context: context,
      builder: (_) => _ContactDialog(
        existing: existing,
        // الأساسية تلقائيًا لأول جهة؛ تغييرها بعد ذلك للمدير.
        canChoosePrimary: party.canEdit,
        first: first,
        customerRule: party.isCustomer && !party.isSupplier,
      ),
    );
    if (result == null) return;
    final repo = ref.read(crmRepositoryProvider);
    try {
      if (existing == null) {
        await repo.addContact(party.id, result);
      } else {
        await repo.updateContact(result);
      }
      ref.invalidate(contactsProvider(party.id));
    } on ApiException catch (e) {
      if (context.mounted) showErrorSnack(context, e.message);
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    PartyContact contact,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف جهة الاتصال؟'),
        content: Text(contact.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('contact.confirmDelete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(crmRepositoryProvider).removeContact(contact.id);
      ref.invalidate(contactsProvider(party.id));
    } on ApiException catch (e) {
      if (context.mounted) showErrorSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider(party.id));
    final list = contacts.value ?? const <PartyContact>[];
    // موظفو العميل: نفس قاعدة الرقم الأساسي؛ الرقم القديم غير المطابق يظهر مع تنبيه
    // ولا يُعدّل تلقائيًا. جهات اتصال الموردين قد تكون دولية.
    final customerRule = party.isCustomer && !party.isSupplier;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // العنوان وزر الإضافة في سطر واحد كما في التصميم إن اتسع، وإلا يلتف العنوان
        // بحجمه الطبيعي وينزل الزر تحته (بدل قص العنوان وتجاوز العرض).
        LayoutBuilder(
          builder: (context, box) {
            const title = 'الموظفون وجهات الاتصال';
            const style = TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            );
            final scaler = MediaQuery.textScalerOf(context);
            final titleWidth =
                (TextPainter(
                  text: TextSpan(
                    text: title,
                    style: DefaultTextStyle.of(context).style.merge(style),
                  ),
                  textDirection: TextDirection.rtl,
                  textScaler: scaler,
                )..layout()).width +
                32;
            final add = party.canAdd
                ? TextButton.icon(
                    key: const Key('contact.add'),
                    onPressed: () => _edit(context, ref, first: list.isEmpty),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('موظف'),
                  )
                : null;
            final addWidth = add == null ? 0 : scaler.scale(40) + 56;
            if (titleWidth + addWidth <= box.maxWidth) {
              return Row(
                children: [
                  const Expanded(
                    child: FieldLabel(title, icon: Icons.groups_2_outlined),
                  ),
                  ?add,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 14, bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.groups_2_outlined,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      Flexible(child: Text(title, style: style)),
                    ],
                  ),
                ),
                if (add != null)
                  Align(alignment: AlignmentDirectional.centerEnd, child: add),
              ],
            );
          },
        ),
        if (contacts.hasError)
          TextButton(
            onPressed: () => ref.invalidate(contactsProvider(party.id)),
            child: const Text('تعذر التحميل. إعادة المحاولة'),
          )
        else if (contacts.hasValue && list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'لا توجد جهات اتصال مسجلة',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        for (final c in list)
          _ContactCard(
            contact: c,
            invalidMobile:
                customerRule &&
                c.mobile != null &&
                !isEgyptianMobile(c.mobile!),
            canEdit: party.canEdit,
            onEdit: () => _edit(context, ref, existing: c, first: false),
            onRemove: () => _remove(context, ref, c),
          ),
      ],
    );
  }
}

/// بطاقة موظف: الاسم بعرض البطاقة ويلتف عند حدود الكلمات، ثم الوظيفة والرقم، والأزرار
/// بجوار البيانات إن اتسعت وإلا تنزل تحتها. الارتفاع حسب المحتوى.
class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.invalidMobile,
    required this.canEdit,
    required this.onEdit,
    required this.onRemove,
  });

  final PartyContact contact;
  final bool invalidMobile;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    final actions = [
      if (c.mobile case final m?) ...[
        IconButton(
          key: Key('contact.call.${c.id}'),
          tooltip: 'اتصال',
          onPressed: () => ContactLauncher.call(m),
          icon: const Icon(Icons.call_rounded, color: AppColors.primary),
        ),
        IconButton(
          key: Key('contact.whatsapp.${c.id}'),
          tooltip: 'واتساب',
          onPressed: () => ContactLauncher.whatsApp(m),
          icon: const Icon(Icons.chat_rounded, color: AppColors.greenDark),
        ),
      ],
      if (canEdit)
        IconButton(
          key: Key('contact.delete.${c.id}'),
          tooltip: 'حذف',
          onPressed: onRemove,
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: AppColors.error,
          ),
        ),
    ];
    const nameStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      color: AppColors.textPrimary,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(c.name, style: nameStyle),
        if (c.jobTitle case final t? when t.trim().isNotEmpty)
          Text(t, style: const TextStyle(color: AppColors.textSecondary)),
        if (c.isPrimary)
          const Text(
            'جهة الاتصال الأساسية',
            style: TextStyle(color: AppColors.reportsAccent, fontSize: 12.5),
          ),
        if (c.mobile case final m?)
          Text(
            CrmFormat.phone(m),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: invalidMobile ? AppColors.error : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (invalidMobile)
          const Text(
            'رقم غير صالح — يحتاج تصحيح (11 رقمًا يبدأ بـ 010/011/012/015)',
            key: Key('contact.invalidMobile'),
            style: TextStyle(color: AppColors.error, fontSize: 12),
          ),
      ],
    );
    final avatar = CircleAvatar(
      backgroundColor: AppColors.fieldFill,
      child: Icon(
        c.isPrimary ? Icons.star_rounded : Icons.person_rounded,
        color: c.isPrimary ? AppColors.reportsAccent : AppColors.primary,
      ),
    );
    return Card(
      key: Key('contact.${c.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.fieldBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: canEdit ? onEdit : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 6),
          child: LayoutBuilder(
            builder: (context, box) {
              final scaler = MediaQuery.textScalerOf(context);
              final longest = c.name
                  .split(RegExp(r'\s+'))
                  .map(
                    (w) => (TextPainter(
                      text: TextSpan(
                        text: w,
                        style: DefaultTextStyle.of(context).style
                            .merge(nameStyle),
                      ),
                      textDirection: TextDirection.rtl,
                      textScaler: scaler,
                    )..layout()).width,
                  )
                  .fold<double>(0, (a, b) => a > b ? a : b);
              // عرض البيانات إذا كانت الأزرار بجوارها (الصورة 40 + مسافة 12).
              final beside = box.maxWidth - 52 - actions.length * 48;
              final row = beside >= longest && beside >= scaler.scale(140);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(child: details),
                      if (row) ...actions,
                    ],
                  ),
                  if (!row && actions.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({
    this.existing,
    required this.canChoosePrimary,
    required this.first,
    this.customerRule = false,
  });

  /// موظف عميل: موبايل مصري كامل فقط (نفس قاعدة الرقم الأساسي).
  final bool customerRule;
  final PartyContact? existing;
  final bool canChoosePrimary;
  final bool first;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _job = TextEditingController(text: widget.existing?.jobTitle);
  late final _mobile = TextEditingController(
    text: widget.existing?.mobile == null
        ? ''
        : CrmFormat.phone(widget.existing!.mobile!),
  );
  late bool _primary = widget.existing?.isPrimary ?? widget.first;

  @override
  void dispose() {
    _name.dispose();
    _job.dispose();
    _mobile.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final mobile = _mobile.text.trim();
    Navigator.pop(
      context,
      PartyContact(
        id: widget.existing?.id ?? const Uuid().v7(),
        name: _name.text.trim(),
        jobTitle: _job.text.trim().isEmpty ? null : _job.text.trim(),
        mobile: mobile.isEmpty ? null : mobile,
        isPrimary: _primary,
        version: widget.existing?.version ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'إضافة موظف' : 'تعديل جهة الاتصال'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('contact.name'),
              controller: _name,
              decoration: formDecoration(hint: 'الاسم'),
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'اكتب الاسم' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('contact.job'),
              controller: _job,
              decoration: formDecoration(hint: 'الوظيفة (اختياري)'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('contact.mobile'),
              controller: _mobile,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
              decoration: formDecoration(
                hint: 'رقم الموبايل',
                suffix: phoneStatusIcon(
                  _mobile.text,
                  widget.customerRule
                      ? employeeMobileError
                      : ContactLauncher.phoneError,
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? null
                  : widget.customerRule
                  ? employeeMobileError(v)
                  : ContactLauncher.phoneError(v),
            ),
            CheckboxListTile(
              key: const Key('contact.primary'),
              contentPadding: EdgeInsets.zero,
              value: _primary,
              onChanged: widget.canChoosePrimary && !widget.first
                  ? (v) => setState(() => _primary = v ?? false)
                  : null,
              title: const Text('جهة الاتصال الأساسية'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const Key('contact.save'),
        onPressed: _save,
        child: const Text('حفظ'),
      ),
    ],
  );
}
