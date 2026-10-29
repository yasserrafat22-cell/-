import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/device/device_location.dart';
import '../../../core/device/share_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_models.dart';
import '../domain/maps_link.dart';
import 'crm_widgets.dart';

/// يفتح شاشة إضافة موقع أو تعديله، ويعيد الموقع المحفوظ أو null.
/// [asDefault] null يترك الاختيار للمستخدم؛ false يمنع تغيير الافتراضي
/// (مثلًا عند إضافة موقع لطلب واحد).
Future<PartyLocation?> editLocation(
  BuildContext context, {
  required String partyId,
  PartyLocation? existing,
  LocationKind? kind,
  bool? asDefault,
}) => Navigator.of(context).push<PartyLocation>(
  MaterialPageRoute(
    builder: (_) => LocationEditScreen(
      partyId: partyId,
      existing: existing,
      initialKind: kind,
      asDefault: asDefault,
    ),
  ),
);

Future<void> openMap(BuildContext context, PartyLocation location) async {
  final link = location.link;
  if (link == null ||
      !await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication)) {
    if (context.mounted) showErrorSnack(context, 'لا يوجد رابط لهذا الموقع');
  }
}

enum _Method { link, gps, manual }

class LocationEditScreen extends ConsumerStatefulWidget {
  const LocationEditScreen({
    super.key,
    required this.partyId,
    this.existing,
    this.initialKind,
    this.asDefault,
  });

  final String partyId;
  final PartyLocation? existing;
  final LocationKind? initialKind;
  final bool? asDefault;

  @override
  ConsumerState<LocationEditScreen> createState() => _LocationEditScreenState();
}

class _LocationEditScreenState extends ConsumerState<LocationEditScreen> {
  late final _id = widget.existing?.id ?? const Uuid().v7();
  late LocationKind _kind =
      widget.existing?.kind ?? widget.initialKind ?? LocationKind.factory;
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _url = TextEditingController(text: widget.existing?.mapsUrl);
  late final _address = TextEditingController(
    text: widget.existing?.addressLine,
  );
  late final _notes = TextEditingController(text: widget.existing?.accessNotes);
  late final _lat = TextEditingController(
    text: widget.existing?.latitude?.toString(),
  );
  late final _lng = TextEditingController(
    text: widget.existing?.longitude?.toString(),
  );
  late bool _default = widget.asDefault ?? widget.existing?.isDefault ?? false;
  _Method _method = _Method.link;
  bool _locating = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_label, _url, _address, _notes, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  (double, double)? get _coordinates {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    return MapsLink.valid(lat, lng) ? (lat!, lng!) : null;
  }

  void _applyLink(String text) {
    final coords = MapsLink.isGoogleMaps(text)
        ? MapsLink.coordinates(text)
        : null;
    setState(() {
      if (coords != null) {
        _lat.text = coords.$1.toStringAsFixed(6);
        _lng.text = coords.$2.toStringAsFixed(6);
      }
    });
  }

  Future<void> _paste() async {
    setState(() => _method = _Method.link);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _url.text = text;
    _applyLink(text);
  }

  Future<void> _useGps() async {
    setState(() {
      _method = _Method.gps;
      _locating = true;
      _error = null;
    });
    try {
      final (lat, lng) = await ref.read(deviceLocationProvider).current();
      _lat.text = lat.toStringAsFixed(6);
      _lng.text = lng.toStringAsFixed(6);
    } on DeviceLocationException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (url.isNotEmpty && !MapsLink.isGoogleMaps(url)) {
      setState(() => _error = 'الرابط يجب أن يكون رابط Google Maps');
      return;
    }
    final hasLat = _lat.text.trim().isNotEmpty || _lng.text.trim().isNotEmpty;
    final coords = _coordinates;
    if (hasLat && coords == null) {
      setState(() => _error = 'الإحداثيات غير صحيحة');
      return;
    }
    if (url.isEmpty && coords == null && _address.text.trim().isEmpty) {
      setState(() => _error = 'أدخل العنوان أو رابط الخريطة أو الإحداثيات');
      return;
    }
    String? clean(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final draft = LocationDraft(
      id: _id,
      kind: _kind,
      label: clean(_label),
      addressLine: clean(_address),
      mapsUrl: url.isEmpty ? null : url,
      latitude: coords?.$1,
      longitude: coords?.$2,
      accessNotes: clean(_notes),
      isDefault: _default,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(crmRepositoryProvider);
    try {
      final saved = widget.existing == null
          ? await repo.createLocation(widget.partyId, draft)
          : await repo.updateLocation(widget.existing!, draft);
      ref.invalidate(locationsProvider(widget.partyId));
      ref.invalidate(historyProvider(widget.partyId));
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الموقع؟'),
        content: const Text(
          'الطلبات والتوريدات السابقة المرتبطة به تبقى كما هي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('location.confirmDelete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(crmRepositoryProvider).removeLocation(widget.existing!.id);
      ref.invalidate(locationsProvider(widget.partyId));
      ref.invalidate(historyProvider(widget.partyId));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coords = _coordinates;
    final url = _url.text.trim();
    return CrmScaffold(
      title: widget.existing == null ? 'إضافة موقع' : 'تعديل الموقع',
      icon: Icons.add_location_alt_rounded,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // الخطأ بجوار زر الحفظ حتى يظهر دائمًا دون تمرير.
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _error!,
                key: const Key('location.error'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          SaveButton(label: 'حفظ الموقع', busy: _saving, onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const FieldLabel(
            'نوع الموقع',
            icon: Icons.category_rounded,
            required: true,
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in LocationKind.values)
                ChoiceChip(
                  key: Key('location.kind.${k.name}'),
                  label: Text(k.nameAr),
                  selected: k == _kind,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: k == _kind ? Colors.white : AppColors.textPrimary,
                  ),
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const FieldLabel('اسم وصفي', icon: Icons.label_outline_rounded),
          TextField(
            key: const Key('location.label'),
            controller: _label,
            maxLength: 100,
            decoration: formDecoration(hint: 'مثال: مصنع العاشر - البوابة 2'),
          ),
          const FieldLabel('تحديد الموقع', icon: Icons.my_location_rounded),
          Row(
            children: [
              _MethodButton(
                key: const Key('location.paste'),
                label: 'لصق رابط',
                icon: Icons.link_rounded,
                selected: _method == _Method.link,
                onTap: _paste,
              ),
              _MethodButton(
                key: const Key('location.gps'),
                label: 'موقعي الحالي',
                icon: Icons.gps_fixed_rounded,
                selected: _method == _Method.gps,
                busy: _locating,
                onTap: _useGps,
              ),
              _MethodButton(
                key: const Key('location.manual'),
                label: 'إحداثيات',
                icon: Icons.pin_drop_outlined,
                selected: _method == _Method.manual,
                onTap: () => setState(() => _method = _Method.manual),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_method == _Method.link) ...[
            TextField(
              key: const Key('location.url'),
              controller: _url,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              onChanged: _applyLink,
              decoration: formDecoration(hint: 'https://maps.app.goo.gl/...'),
            ),
            const SizedBox(height: 6),
            if (url.isNotEmpty)
              coords != null
                  ? InfoStrip(
                      icon: Icons.check_circle_rounded,
                      title: 'تم استخراج الإحداثيات: ',
                      subtitle:
                          '${coords.$1.toStringAsFixed(5)} , ${coords.$2.toStringAsFixed(5)}',
                      green: true,
                    )
                  : const InfoStrip(
                      icon: Icons.info_outline_rounded,
                      title: 'سيُحفظ الرابط كما هو',
                      subtitle: '(لا يحتوي إحداثيات؛ يفتح في الخرائط مباشرة)',
                    ),
          ],
          if (_method != _Method.link)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('location.lat'),
                    controller: _lat,
                    enabled: _method == _Method.manual,
                    textDirection: TextDirection.ltr,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: formDecoration(hint: 'خط العرض'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('location.lng'),
                    controller: _lng,
                    enabled: _method == _Method.manual,
                    textDirection: TextDirection.ltr,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: formDecoration(hint: 'خط الطول'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          const FieldLabel('العنوان', icon: Icons.home_work_outlined),
          TextField(
            key: const Key('location.address'),
            controller: _address,
            maxLength: 300,
            decoration: formDecoration(hint: 'المدينة، المنطقة، الشارع'),
          ),
          const FieldLabel('ملاحظات الوصول', icon: Icons.notes_rounded),
          TextField(
            key: const Key('location.notes'),
            controller: _notes,
            maxLength: 300,
            decoration: formDecoration(hint: 'البوابة، المواعيد…'),
          ),
          if (widget.asDefault == null)
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const Key('location.default'),
                value: _default,
                onChanged: (v) => setState(() => _default = v),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'الموقع الافتراضي',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (widget.existing != null)
            TextButton.icon(
              key: const Key('location.delete'),
              onPressed: _remove,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              label: const Text(
                'حذف الموقع',
                style: TextStyle(color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? AppColors.primary : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.fieldBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                busy
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        icon,
                        color: selected ? Colors.white : AppColors.primary,
                      ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textPrimary,
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

/// قسم «المواقع» في تفاصيل العميل أو المورد.
class LocationsSection extends ConsumerWidget {
  const LocationsSection({super.key, required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(locationsProvider(party.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: FieldLabel('المواقع', icon: Icons.place_rounded),
            ),
            if (party.canEdit)
              TextButton.icon(
                key: const Key('location.add'),
                onPressed: () => editLocation(context, partyId: party.id),
                icon: const Icon(Icons.add_rounded),
                label: const Text('موقع'),
              ),
          ],
        ),
        ...switch (locations) {
          AsyncData(:final value) when value.isEmpty => [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'لا توجد مواقع محفوظة',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
          AsyncData(:final value) => [
            for (final (i, l) in value.indexed)
              LocationCard(
                location: l,
                index: i,
                partyName: party.name,
                onEdit: party.canEdit
                    ? () =>
                          editLocation(context, partyId: party.id, existing: l)
                    : null,
              ),
          ],
          AsyncError() => [
            TextButton(
              onPressed: () => ref.invalidate(locationsProvider(party.id)),
              child: const Text('تعذر تحميل المواقع — إعادة المحاولة'),
            ),
          ],
          _ => [const LinearProgressIndicator()],
        },
      ],
    );
  }
}

class LocationCard extends ConsumerWidget {
  const LocationCard({
    super.key,
    required this.location,
    required this.index,
    required this.partyName,
    this.onEdit,
  });

  final PartyLocation location;
  final int index;
  final String partyName;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = location;
    Widget action(
      String key,
      String label,
      IconData icon,
      VoidCallback onTap, {
      Color? color,
    }) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: OutlinedButton.icon(
        key: Key('location.$key.$index'),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color ?? AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          side: const BorderSide(color: AppColors.fieldBorder),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.fieldBorder),
        ),
        child: InkWell(
          key: Key('location.card.$index'),
          borderRadius: BorderRadius.circular(14),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (l.isDefault) const Pill('افتراضي'),
                  ],
                ),
                if (l.addressLine case final a? when a.isNotEmpty)
                  Text(
                    a,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                Text(
                  [
                    if (l.accessNotes case final n? when n.isNotEmpty) n,
                    if (l.mapsUrl != null && !l.hasCoordinates)
                      'رابط بدون إحداثيات',
                  ].join(' • '),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  runSpacing: 4,
                  children: [
                    if (l.link != null) ...[
                      action(
                        'map',
                        'الخريطة',
                        Icons.map_rounded,
                        () => openMap(context, l),
                      ),
                      action('copy', 'نسخ', Icons.copy_rounded, () async {
                        await Clipboard.setData(ClipboardData(text: l.link!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم نسخ رابط الموقع')),
                          );
                        }
                      }),
                    ],
                    action(
                      'share',
                      'مشاركة',
                      Icons.share_rounded,
                      () => ref
                          .read(shareServiceProvider)
                          .text(l.shareText(partyName)),
                      color: AppColors.greenDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// اختيار موقع لعملية واحدة (طلب أو توريد) من المواقع المحفوظة، أو إضافة
/// موقع جديد. لا يغيّر الموقع الافتراضي المحفوظ.
Future<PartyLocation?> pickLocation(
  BuildContext context,
  WidgetRef ref, {
  required String partyId,
  required LocationKind newKind,
  String? selectedId,
}) async {
  final locations = await ref.read(locationsProvider(partyId).future);
  if (!context.mounted) return null;
  final picked = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final l in locations)
            ListTile(
              key: Key('pickLocation.${l.id}'),
              leading: Icon(
                l.id == selectedId
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: AppColors.primary,
              ),
              title: Text(l.title),
              subtitle: Text(l.addressLine ?? ''),
              trailing: l.isDefault ? const Pill('افتراضي') : null,
              onTap: () => Navigator.pop(context, l),
            ),
          ListTile(
            key: const Key('pickLocation.new'),
            leading: const Icon(Icons.add_location_alt_rounded),
            title: const Text('موقع جديد لهذه العملية'),
            subtitle: const Text('يُحفظ ضمن المواقع دون تغيير الافتراضي'),
            onTap: () => Navigator.pop(context, 'new'),
          ),
        ],
      ),
    ),
  );
  if (picked is PartyLocation) return picked;
  if (picked == 'new' && context.mounted) {
    return editLocation(
      context,
      partyId: partyId,
      kind: newKind,
      asDefault: locations.isEmpty ? null : false,
    );
  }
  return null;
}
