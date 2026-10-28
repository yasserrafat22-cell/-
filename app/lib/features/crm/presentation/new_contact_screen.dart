import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'crm_widgets.dart';
import 'quick_add_party_screen.dart' show AsyncBody;

/// تسجيل تواصل بنتيجته (ص8، ص9). «آخر تواصل» في الملف يُحسب من هذه السجلات.
class NewContactScreen extends ConsumerStatefulWidget {
  const NewContactScreen({super.key, required this.partyId, this.channel});

  final String partyId;
  final ContactChannel? channel;

  @override
  ConsumerState<NewContactScreen> createState() => _NewContactScreenState();
}

class _NewContactScreenState extends ConsumerState<NewContactScreen> {
  final _id = const Uuid().v7();
  final _notes = TextEditingController();
  late ContactChannel _channel = widget.channel ?? ContactChannel.call;
  String? _outcomeId;
  DateTime? _nextFollowUp;
  bool _remind = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickFollowUp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextFollowUp ?? now.add(const Duration(days: 1)),
      firstDate: DateUtils.dateOnly(now).add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    // موعد المتابعة الساعة 10 صباحًا من اليوم المختار.
    if (picked != null) {
      setState(() => _nextFollowUp = picked.add(const Duration(hours: 10)));
    }
  }

  Future<void> _save() async {
    if (_outcomeId == null) {
      setState(() => _error = 'اختر نتيجة التواصل');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref
          .read(crmRepositoryProvider)
          .addInteraction(
            widget.partyId,
            id: _id,
            channel: _channel,
            outcomeId: _outcomeId!,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            nextFollowUpAt: _nextFollowUp,
            remind: _nextFollowUp != null && _remind,
          );
      if (!mounted) return;
      refreshParty(ref, widget.partyId);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider);
    final party = ref.watch(partyProvider(widget.partyId));
    return CrmScaffold(
      title: 'تسجيل تواصل',
      icon: Icons.how_to_reg_rounded,
      bottom: SaveButton(label: 'حفظ التواصل', busy: _saving, onPressed: _save),
      body: AsyncBody(
        value: refs,
        onRetry: () => ref.invalidate(referenceDataProvider),
        data: (r) => _form(r, party.value),
      ),
    );
  }

  Widget _form(ReferenceData refs, PartyDetail? party) {
    final supplierOnly = party != null && party.isSupplier && !party.isCustomer;
    final customerOnly = party != null && party.isCustomer && !party.isSupplier;
    final outcomes = refs.contactOutcomes
        .where(
          (o) => supplierOnly
              ? o.appliesToSupplier()
              : customerOnly
              ? o.appliesToCustomer()
              : true,
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const FieldLabel(
          'نوع التواصل',
          icon: Icons.phone_in_talk_outlined,
          required: true,
        ),
        ChoiceTiles<ContactChannel>(
          keyPrefix: 'channel',
          options: const [
            ChoiceOption(ContactChannel.call, 'اتصال', Icons.call_rounded),
            ChoiceOption(
              ContactChannel.visit,
              'زيارة',
              Icons.directions_walk_rounded,
            ),
            ChoiceOption(ContactChannel.whatsApp, 'واتساب', Icons.chat_rounded),
            ChoiceOption(
              ContactChannel.other,
              'أخرى',
              Icons.more_horiz_rounded,
            ),
          ],
          selected: _channel,
          onChanged: (v) => setState(() => _channel = v),
        ),
        const FieldLabel(
          'نتيجة التواصل',
          icon: Icons.edit_note_rounded,
          required: true,
        ),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: RadioGroup<String>(
            groupValue: _outcomeId,
            onChanged: (v) => setState(() => _outcomeId = v),
            child: Column(
              children: [
                for (final o in outcomes)
                  RadioListTile<String>(
                    key: Key('outcome.${o.code}'),
                    value: o.id,
                    dense: true,
                    title: Text(
                      o.nameAr,
                      style: TextStyle(
                        fontWeight: _outcomeId == o.id
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const FieldLabel('ملاحظات', icon: Icons.notes_rounded),
        TextField(
          key: const Key('contact.notes'),
          controller: _notes,
          maxLines: 3,
          maxLength: 300,
          decoration: formDecoration(hint: 'اكتب ملاحظات مختصرة...'),
        ),
        const FieldLabel('تاريخ المتابعة القادمة', icon: Icons.event_rounded),
        InkWell(
          key: const Key('contact.followUp'),
          onTap: _pickFollowUp,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: formDecoration(
              prefix: const Icon(
                Icons.calendar_today_rounded,
                color: AppColors.primary,
              ),
              suffix: _nextFollowUp == null
                  ? null
                  : IconButton(
                      tooltip: 'إلغاء الموعد',
                      onPressed: () => setState(() => _nextFollowUp = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            child: Text(
              _nextFollowUp == null
                  ? 'اختر التاريخ'
                  : CrmFormat.date(_nextFollowUp),
              style: TextStyle(
                color: _nextFollowUp == null
                    ? AppColors.hint
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تذكير بالمتابعة',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            Switch(
              key: const Key('contact.remind'),
              value: _nextFollowUp != null && _remind,
              activeTrackColor: const Color(0xFF2E9B37),
              onChanged: _nextFollowUp == null
                  ? null
                  : (v) => setState(() => _remind = v),
            ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            key: const Key('contact.error'),
            style: const TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}
