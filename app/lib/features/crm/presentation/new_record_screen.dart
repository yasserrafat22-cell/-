import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/device/share_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../data/crm_repository.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'crm_widgets.dart';
import 'location_screens.dart';
import 'material_picker.dart';
import 'quick_add_party_screen.dart' show AsyncBody;

/// تسجيل طلب جديد لعميل (ص8) أو توريد جديد لمورد (ص9): تاريخ، وعدة خامات
/// بكمياتها ووحداتها، والحالة (إضافة معتمدة T4)، وملاحظات.
class NewRecordScreen extends ConsumerStatefulWidget {
  const NewRecordScreen({
    super.key,
    required this.partyId,
    required this.supply,
  });

  final String partyId;
  final bool supply;

  @override
  ConsumerState<NewRecordScreen> createState() => _NewRecordScreenState();
}

class _Line {
  SpecChoice? spec;
  String? unitId;
  final quantity = TextEditingController();
}

class _NewRecordScreenState extends ConsumerState<NewRecordScreen> {
  final _id = const Uuid().v7();
  final _notes = TextEditingController();
  final _lines = <_Line>[_Line()];
  late DateTime _date = DateUtils.dateOnly(ref.read(clockProvider)());
  OrderStage _stage = OrderStage.inquiry;
  SupplyStatus _status = SupplyStatus.received;
  bool _saving = false;
  String? _error;

  /// موقع هذه العملية فقط؛ null يعني الموقع الافتراضي للطرف.
  String? _locationId;

  String? get _effectiveLocationId =>
      _locationId ??
      ref
          .read(locationsProvider(widget.partyId))
          .value
          ?.where((l) => l.isDefault)
          .firstOrNull
          ?.id;

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.quantity.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: ref.read(clockProvider)().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(ReferenceData refs) async {
    final lines = <NewLine>[];
    for (final l in _lines) {
      final quantity = double.tryParse(
        l.quantity.text.trim().replaceAll(',', '.'),
      );
      if (l.spec == null || quantity == null || quantity <= 0) {
        setState(() => _error = 'اختر الخامة واكتب كمية أكبر من صفر لكل سطر');
        return;
      }
      lines.add(
        NewLine(
          spec: l.spec!,
          quantity: quantity,
          unitId: l.unitId ?? _defaultUnit(refs),
        ),
      );
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final repo = ref.read(crmRepositoryProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    try {
      if (widget.supply) {
        await repo.createSupply(
          id: _id,
          supplierId: widget.partyId,
          supplyDate: CrmFormat.isoDay(_date),
          status: _status,
          lines: lines,
          notes: notes,
          locationId: _effectiveLocationId,
        );
      } else {
        await repo.createOrder(
          id: _id,
          customerId: widget.partyId,
          orderDate: CrmFormat.isoDay(_date),
          stage: _stage,
          lines: lines,
          notes: notes,
          locationId: _effectiveLocationId,
        );
      }
      if (!mounted) return;
      refreshParty(ref, widget.partyId);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// رسالة للسائق: الخامات والكميات والموقع ورابط الخريطة. تُرسل يدويًا.
  String _driverMessage(ReferenceData refs, PartyLocation location) {
    final party = ref.read(partyProvider(widget.partyId)).value;
    final lines = [
      for (final l in _lines)
        if (l.spec != null)
          '- ${l.spec!.describe(refs).label}'
              '${l.quantity.text.trim().isEmpty ? '' : ' — ${l.quantity.text.trim()} '
                        '${CrmFormat.unitName(refs.unit(l.unitId ?? _defaultUnit(refs))?.code ?? 'ton')}'}',
    ];
    return [
      '${widget.supply ? 'توريد من' : 'طلب'}: ${party?.name ?? ''}',
      'التاريخ: ${CrmFormat.date(_date)}',
      if (lines.isNotEmpty) ...['الخامات:', ...lines],
      '${widget.supply ? 'موقع التحميل' : 'موقع التسليم'}: ${location.title}',
      if (location.addressLine case final a? when a.isNotEmpty) 'العنوان: $a',
      if (location.link case final link?) 'الخريطة: $link',
      if (location.accessNotes case final n? when n.isNotEmpty)
        'ملاحظات الوصول: $n',
    ].join('\n');
  }

  static String _defaultUnit(ReferenceData refs) =>
      (refs.units.where((u) => u.code == 'ton').firstOrNull ?? refs.units.first)
          .id;

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider);
    return CrmScaffold(
      title: widget.supply ? 'تسجيل توريد جديد' : 'تسجيل طلب جديد',
      icon: widget.supply
          ? Icons.local_shipping_rounded
          : Icons.assignment_ind_rounded,
      bottom: refs.hasValue
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الخطأ بجوار زر الحفظ حتى يظهر دائمًا دون تمرير.
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      _error!,
                      key: const Key('record.error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                SaveButton(
                  label: widget.supply ? 'حفظ التوريد' : 'حفظ الطلب',
                  busy: _saving,
                  onPressed: () => _save(refs.requireValue),
                ),
              ],
            )
          : null,
      body: AsyncBody(
        value: refs,
        onRetry: () => ref.invalidate(referenceDataProvider),
        data: _form,
      ),
    );
  }

  Future<void> _pickLine(_Line line) async {
    final picked = await pickSpec(
      context,
      allowOpen: !widget.supply,
      initial: line.spec,
    );
    if (picked != null) setState(() => line.spec = picked);
  }

  Widget _form(ReferenceData refs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        FieldLabel(
          widget.supply ? 'تاريخ التوريد' : 'تاريخ الطلب',
          icon: Icons.calendar_month_rounded,
          required: true,
        ),
        InkWell(
          key: const Key('record.date'),
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: formDecoration(
              prefix: const Icon(
                Icons.calendar_today_rounded,
                color: AppColors.primary,
              ),
            ),
            child: Text(
              CrmFormat.date(_date),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFE3EEFA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: const Text(
                  'الخامة / المنتج والكمية',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              for (final (i, line) in _lines.indexed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 4, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              key: Key('line.$i.material'),
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _pickLine(line),
                              child: InputDecorator(
                                decoration: formDecoration(
                                  suffix: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: AppColors.navy,
                                  ),
                                ),
                                isEmpty: line.spec == null,
                                child: line.spec == null
                                    ? const Text(
                                        'اختر',
                                        style: TextStyle(color: AppColors.hint),
                                      )
                                    : Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: SpecChip(
                                          line.spec!.describe(refs),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'حذف',
                            onPressed: _lines.length == 1
                                ? null
                                : () => setState(
                                    () => _lines.removeAt(i).quantity.dispose(),
                                  ),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: Key('line.$i.quantity'),
                              controller: line.quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              textDirection: TextDirection.ltr,
                              decoration: formDecoration(
                                hint: '0.00',
                                suffix: _UnitSelector(
                                  units: refs.units,
                                  selected: line.unitId ?? _defaultUnit(refs),
                                  onChanged: (u) =>
                                      setState(() => line.unitId = u),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Material(
                  color: const Color(0xFFE3EEFA),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: const Key('record.addLine'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: _lines.length >= 50
                        ? null
                        : () => setState(() => _lines.add(_Line())),
                    child: const SizedBox(
                      height: 46,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, color: AppColors.navy),
                          SizedBox(width: 6),
                          Text(
                            'إضافة خامة أخرى',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _LocationField(
          partyId: widget.partyId,
          supply: widget.supply,
          selectedId: _locationId,
          onChanged: (id) => setState(() => _locationId = id),
          driverMessage: (location) => _driverMessage(refs, location),
        ),
        FieldLabel(
          widget.supply ? 'حالة التوريد' : 'حالة الطلب',
          icon: Icons.flag_outlined,
          required: true,
        ),
        if (widget.supply)
          ChoiceTiles<SupplyStatus>(
            keyPrefix: 'status',
            options: const [
              ChoiceOption(
                SupplyStatus.received,
                'مستلم',
                Icons.check_circle_outline_rounded,
              ),
              ChoiceOption(
                SupplyStatus.expected,
                'متوقع',
                Icons.schedule_rounded,
              ),
            ],
            selected: _status,
            onChanged: (v) => setState(() => _status = v),
          )
        else
          ChoiceTiles<OrderStage>(
            keyPrefix: 'stage',
            options: const [
              ChoiceOption(
                OrderStage.inquiry,
                'استفسار',
                Icons.help_outline_rounded,
              ),
              ChoiceOption(
                OrderStage.quotation,
                'عرض سعر',
                Icons.request_quote_outlined,
              ),
              ChoiceOption(
                OrderStage.confirmed,
                'طلب مؤكد',
                Icons.verified_outlined,
              ),
            ],
            selected: _stage,
            onChanged: (v) => setState(() => _stage = v),
          ),
        FieldLabel(
          widget.supply ? 'ملاحظات التوريد' : 'ملاحظات الطلب',
          icon: Icons.notes_rounded,
        ),
        TextField(
          key: const Key('record.notes'),
          controller: _notes,
          maxLines: 4,
          maxLength: 300,
          decoration: formDecoration(
            hint: widget.supply
                ? 'أي ملاحظات أو تفاصيل إضافية...'
                : 'ملاحظات أو متطلبات خاصة...',
          ),
        ),
      ],
    );
  }
}

class _UnitSelector extends StatelessWidget {
  const _UnitSelector({
    required this.units,
    required this.selected,
    required this.onChanged,
  });

  final List<UnitItem> units;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = units.where((u) => u.id == selected).firstOrNull;
    return PopupMenuButton<String>(
      tooltip: 'الوحدة',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final u in units)
          PopupMenuItem(value: u.id, child: Text(u.nameAr)),
      ],
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Text(
            current == null ? '' : CrmFormat.unitName(current.code),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// موقع التسليم (للطلب) أو التحميل (للتوريد) لهذه العملية، و«إرسال للسائق».
class _LocationField extends ConsumerWidget {
  const _LocationField({
    required this.partyId,
    required this.supply,
    required this.selectedId,
    required this.onChanged,
    required this.driverMessage,
  });

  final String partyId;
  final bool supply;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final String Function(PartyLocation) driverMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(locationsProvider(partyId)).value ?? const [];
    final fallback = locations.where((l) => l.isDefault).firstOrNull;
    final selected = locations
        .where((l) => l.id == (selectedId ?? fallback?.id))
        .firstOrNull;
    final kind = supply ? LocationKind.loading : LocationKind.delivery;
    Future<void> change() async {
      final picked = await pickLocation(
        context,
        ref,
        partyId: partyId,
        newKind: kind,
        selectedId: selected?.id,
      );
      if (picked != null) onChanged(picked.id);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(
          supply ? 'موقع التحميل' : 'موقع التسليم',
          icon: Icons.local_shipping_outlined,
        ),
        SectionCard(
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: selected == null
                    ? const Text(
                        'لم يُحدد موقع',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected.isDefault
                                ? '${selected.title} (افتراضي)'
                                : selected.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (selected.addressLine case final a?)
                            Text(
                              a,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                        ],
                      ),
              ),
              TextButton(
                key: const Key('record.location'),
                onPressed: change,
                child: Text(selected == null ? 'اختيار' : 'تغيير'),
              ),
            ],
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          ActionPill(
            key: const Key('record.driver'),
            label: 'إرسال للسائق',
            icon: Icons.share_rounded,
            colors: ActionPill.green,
            height: 50,
            onTap: () =>
                ref.read(shareServiceProvider).text(driverMessage(selected)),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}
