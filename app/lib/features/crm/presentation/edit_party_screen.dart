import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../application/crm_providers.dart';
import '../data/crm_repository.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'crm_widgets.dart';
import 'quick_add_party_screen.dart' show AsyncBody;

/// استكمال بيانات العميل أو المورد لاحقًا (حقول ص7: البريد والموقع
/// والملاحظات). تحديد الموقع على الخريطة يُضاف مع خدمة الخرائط.
class EditPartyScreen extends ConsumerWidget {
  const EditPartyScreen({super.key, required this.partyId});

  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider(partyId));
    final refs = ref.watch(referenceDataProvider);
    if ((party.value, refs.value) case (final p?, final r?)) {
      return _EditForm(party: p, refs: r);
    }
    return CrmScaffold(
      title: 'تعديل واستكمال البيانات',
      icon: Icons.edit_note_rounded,
      body: party.hasError
          ? AsyncBody(
              value: party,
              onRetry: () => ref.invalidate(partyProvider(partyId)),
              data: (_) => const SizedBox(),
            )
          : AsyncBody(
              value: refs,
              onRetry: () => ref.invalidate(referenceDataProvider),
              data: (_) => const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.party, required this.refs});

  final PartyDetail party;
  final ReferenceData refs;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.party.name);
  late final _phone = TextEditingController(
    text: widget.party.primaryPhone == null
        ? ''
        : CrmFormat.phone(widget.party.primaryPhone!.e164),
  );
  late final _email = TextEditingController(text: widget.party.email);
  late final _region = TextEditingController(text: widget.party.region);
  late final _address = TextEditingController(text: widget.party.addressLine);
  late final _notes = TextEditingController(text: widget.party.notes);
  late String? _governorateId = widget.party.governorateId;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _region, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _clean(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(crmRepositoryProvider)
          .updateDetails(
            widget.party,
            PartyDetailsUpdate(
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              email: _clean(_email),
              governorateId: _governorateId,
              region: _clean(_region),
              addressLine: _clean(_address),
              notes: _clean(_notes),
            ),
          );
      if (!mounted) return;
      refreshParty(ref, widget.party.id);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e.message);
      // تعديل من جهاز آخر: تُحمّل أحدث نسخة بدل الكتابة فوقها.
      if (e.code == 'concurrency.stale') refreshParty(ref, widget.party.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.party.isCustomer;
    return CrmScaffold(
      title: 'تعديل واستكمال البيانات',
      icon: Icons.edit_note_rounded,
      bottom: SaveButton(
        label: 'حفظ التعديلات',
        busy: _saving,
        onPressed: _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            FieldLabel(
              customer ? 'اسم العميل' : 'اسم المورد',
              icon: Icons.person_outline_rounded,
              required: true,
            ),
            TextFormField(
              key: const Key('edit.name'),
              controller: _name,
              decoration: formDecoration(),
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'الاسم مطلوب' : null,
            ),
            const FieldLabel(
              'رقم الهاتف',
              icon: Icons.phone_rounded,
              required: true,
            ),
            TextFormField(
              key: const Key('edit.phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: formDecoration(hint: '01xxxxxxxxx'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'رقم الهاتف مطلوب' : null,
            ),
            const FieldLabel('البريد الإلكتروني', icon: Icons.email_outlined),
            TextFormField(
              key: const Key('edit.email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: formDecoration(hint: 'example@company.com'),
            ),
            FieldLabel(
              customer ? 'موقع العميل' : 'موقع المورد',
              icon: Icons.location_on_rounded,
            ),
            DropdownButtonFormField<String>(
              key: const Key('edit.governorate'),
              initialValue: _governorateId,
              isExpanded: true,
              decoration: formDecoration(hint: 'المحافظة'),
              items: [
                for (final g in widget.refs.governorates)
                  DropdownMenuItem(value: g.id, child: Text(g.nameAr)),
              ],
              onChanged: (v) => setState(() => _governorateId = v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('edit.region'),
              controller: _region,
              decoration: formDecoration(hint: 'المنطقة'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('edit.address'),
              controller: _address,
              decoration: formDecoration(hint: 'العنوان التفصيلي'),
            ),
            const FieldLabel('ملاحظات إضافية', icon: Icons.notes_rounded),
            TextFormField(
              key: const Key('edit.notes'),
              controller: _notes,
              maxLines: 4,
              maxLength: 500,
              decoration: formDecoration(hint: 'أي تفاصيل أخرى (اختياري)'),
            ),
          ],
        ),
      ),
    );
  }
}
