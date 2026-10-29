import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: FieldLabel(
                'الموظفون وجهات الاتصال',
                icon: Icons.groups_2_outlined,
              ),
            ),
            if (party.canAdd)
              TextButton.icon(
                key: const Key('contact.add'),
                onPressed: () => _edit(context, ref, first: list.isEmpty),
                icon: const Icon(Icons.add_rounded),
                label: const Text('موظف'),
              ),
          ],
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
          Card(
            key: Key('contact.${c.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.fieldBorder),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.fieldFill,
                child: Icon(
                  c.isPrimary ? Icons.star_rounded : Icons.person_rounded,
                  color: c.isPrimary
                      ? AppColors.reportsAccent
                      : AppColors.primary,
                ),
              ),
              title: Text(
                c.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  ?c.jobTitle,
                  if (c.isPrimary) 'جهة الاتصال الأساسية',
                  if (c.mobile case final m?) CrmFormat.phone(m),
                ].join(' • '),
              ),
              onLongPress: party.canEdit
                  ? () => _edit(context, ref, existing: c, first: false)
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.mobile case final m?) ...[
                    IconButton(
                      key: Key('contact.call.${c.id}'),
                      tooltip: 'اتصال',
                      onPressed: () => ContactLauncher.call(m),
                      icon: const Icon(
                        Icons.call_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    IconButton(
                      key: Key('contact.whatsapp.${c.id}'),
                      tooltip: 'واتساب',
                      onPressed: () => ContactLauncher.whatsApp(m),
                      icon: const Icon(
                        Icons.chat_rounded,
                        color: AppColors.greenDark,
                      ),
                    ),
                  ],
                  if (party.canEdit)
                    IconButton(
                      key: Key('contact.delete.${c.id}'),
                      tooltip: 'حذف',
                      onPressed: () => _remove(context, ref, c),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({
    this.existing,
    required this.canChoosePrimary,
    required this.first,
  });

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
                  ContactLauncher.phoneError,
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? null
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
