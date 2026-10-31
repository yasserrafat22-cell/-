import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/device/device_location.dart';
import '../../../core/device/file_services.dart';
import '../../../core/device/share_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../application/crm_providers.dart';
import '../data/crm_repository.dart';
import '../domain/crm_models.dart';
import '../domain/egypt_cities.dart';
import '../domain/maps_link.dart';
import 'contact_launcher.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';
import 'quick_add_party_screen.dart' show AsyncBody;

/// ترتيب الخامات كما اعتمده المالك؛ باقي الخامات بعدها أبجديًا.
const ownerMaterialOrder = [
  'PP',
  'HDPE',
  'LDPE',
  'LLDPE',
  'PVC',
  'PS',
  'GPPS',
  'HIPS',
  'PET',
  'ABS',
  'SAN',
  'PC',
  'PA6',
  'PA66',
  'POM',
  'PBT',
  'ASA',
  'EVA',
  'PR200',
  'Borouge 150',
];

const ownerManufacturerOrder = [
  'SABIC',
  'Marlex',
  'Advanced',
  'Tasnee',
  'Kayan',
  'Petro',
  'Sadara',
  'Borouge',
  'Chem',
  'OQ',
];

const jobTitles = [
  'مدير مصنع',
  'مدير مشتريات',
  'مالك المصنع',
  'عامل',
  'موظف',
  'وظيفة أخرى',
];

/// موبايل مصري: 11 رقمًا يبدأ بـ 010 أو 011 أو 012 أو 015.
final egyptianMobile = RegExp(r'^01[0125]\d{8}$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String _digits(String s) => s.replaceAll(RegExp(r'\s|-'), '');

String roleTitle(List<String> roles) => switch (roles) {
  _ when roles.contains('system_admin') => 'مدير النظام',
  _ when roles.contains('sales_manager') => 'مدير المبيعات',
  _ when roles.contains('purchasing_manager') => 'مدير المشتريات',
  _ when roles.contains('secretary') => 'السكرتارية',
  _ => 'مندوب مبيعات',
};

class _Employee {
  _Employee() : id = const Uuid().v7();

  final String id;
  final name = TextEditingController();
  final phone = TextEditingController();
  final customTitle = TextEditingController();
  String? title;

  String? get jobTitle => title == 'وظيفة أخرى'
      ? (customTitle.text.trim().isEmpty ? null : customTitle.text.trim())
      : title;

  bool get isEmpty =>
      name.text.trim().isEmpty && phone.text.trim().isEmpty && title == null;

  void dispose() {
    name.dispose();
    phone.dispose();
    customTitle.dispose();
  }
}

/// موقع مضاف قبل الحفظ (لا يحل محل موقع سابق).
class _Site {
  _Site({
    required this.kind,
    this.label,
    this.governorateId,
    this.region,
    this.address,
    this.mapsUrl,
    this.lat,
    this.lng,
  });

  /// معرف ثابت: إعادة الحفظ لا تكرر الموقع.
  final String id = const Uuid().v7();
  final LocationKind kind;
  final String? label;
  final String? governorateId;
  final String? region;
  final String? address;
  final String? mapsUrl;
  final double? lat;
  final double? lng;

  String get title => label == null ? kind.nameAr : '${kind.nameAr} — $label';

  String? get link =>
      MapsLink.forLocation(url: mapsUrl, lat: lat, lng: lng, address: address);
}

class _Option {
  const _Option(this.id, this.label, {this.subtitle, this.search = ''});

  final String id;
  final String label;
  final String? subtitle;
  final String search;
}

/// «تسجيل عميل» بالتصميم المعتمد. الإلزامي ثلاثة فقط: اسم الشركة، موبايل مصري
/// صحيح، وخامة + Grade واحد على الأقل. الحفظ يعمل دون اتصال (طابور المزامنة)،
/// والموظفون والمواقع والصورة والمرفقات تُرسل بعده بالترتيب لنفس السجل.
class CustomerRegistrationScreen extends ConsumerStatefulWidget {
  const CustomerRegistrationScreen({super.key});

  @override
  ConsumerState<CustomerRegistrationScreen> createState() =>
      _CustomerRegistrationScreenState();
}

class _CustomerRegistrationScreenState
    extends ConsumerState<CustomerRegistrationScreen> {
  // معرف ثابت: تكرار الضغط أو إعادة المحاولة لا ينشئ سجلًا ثانيًا.
  final _id = const Uuid().v7();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _link = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _siteLabel = TextEditingController();
  final _siteSearch = TextEditingController();
  final _employees = [_Employee()];
  final _materials = <String>[];
  final _grades = <String>[];
  final _sites = <_Site>[];
  final _files = <(String, PickedFile)>[];
  final _logoId = const Uuid().v7();
  PickedFile? _logo;
  String? _makerId;
  String? _governorateId;
  String? _region;
  String? _representativeId;
  LocationKind _siteKind = LocationKind.headOffice;
  String _siteMode = 'link';
  bool _saving = false;
  List<RegistryItem> _similar = const [];

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _email]) {
      c.addListener(() => setState(() {}));
    }
    _name.addListener(_lookupSimilar);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _email,
      _address,
      _link,
      _lat,
      _lng,
      _siteLabel,
      _siteSearch,
    ]) {
      c.dispose();
    }
    for (final e in _employees) {
      e.dispose();
    }
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().length >= 2;
  bool get _phoneOk => egyptianMobile.hasMatch(_digits(_phone.text));
  bool get _emailOk =>
      _email.text.trim().isEmpty || _emailPattern.hasMatch(_email.text.trim());
  bool get _gradeOk => _grades.isNotEmpty;
  bool get _valid => _nameOk && _phoneOk && _gradeOk && _emailOk;

  // ------------------------- أسماء مشابهة أثناء الكتابة -------------------------

  int _lookupToken = 0;

  Future<void> _lookupSimilar() async {
    final text = _name.text.trim();
    final token = ++_lookupToken;
    if (text.length < 3) {
      if (_similar.isNotEmpty) setState(() => _similar = const []);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (token != _lookupToken || !mounted) return;
    try {
      final page = await ref
          .read(crmRepositoryProvider)
          .registry(RegistryFilter(query: text), take: 5);
      if (token == _lookupToken && mounted) {
        setState(() => _similar = page.items);
      }
    } on ApiException {
      // بدون اتصال: لا اقتراحات، والسيرفر يتحقق من التكرار عند المزامنة.
    }
  }

  // ------------------------- القوائم -------------------------

  Future<Set<String>?> _pick({
    required String title,
    required List<_Option> options,
    required Set<String> selected,
    bool multi = true,
    String? addHint,
    Future<_Option?> Function(String text)? onAdd,
    String keyPrefix = 'pick',
  }) => showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(
      title: title,
      options: options,
      selected: selected,
      multi: multi,
      addHint: addHint,
      onAdd: onAdd,
      keyPrefix: keyPrefix,
    ),
  );

  List<_Option> _materialOptions(ReferenceData refs) {
    int rank(MaterialItem m) {
      final i = ownerMaterialOrder.indexWhere(
        (c) => c.toLowerCase() == m.code.toLowerCase(),
      );
      return i < 0 ? 1000 : i;
    }

    final list = [...refs.materials]
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.code.compareTo(b.code);
      });
    return [
      for (final m in list)
        _Option(
          m.id,
          m.code,
          subtitle: m.nameAr == m.code ? null : m.nameAr,
          search: '${m.code} ${m.nameAr}',
        ),
    ];
  }

  Future<void> _pickMaterials(ReferenceData refs) async {
    final picked = await _pick(
      title: 'الخامات الرئيسية',
      options: _materialOptions(refs),
      selected: {..._materials},
      addHint: 'خامة جديدة (مثل PA6)',
      keyPrefix: 'material',
      onAdd: (text) async {
        try {
          final m = await ref
              .read(crmRepositoryProvider)
              .createMaterialType(text);
          ref.invalidate(referenceDataProvider);
          return _Option(m.id, m.code);
        } on ApiException catch (e) {
          if (mounted) showErrorSnack(context, e.message);
          return null;
        }
      },
    );
    if (picked == null) return;
    setState(() {
      _materials
        ..removeWhere((id) => !picked.contains(id))
        ..addAll(picked.where((id) => !_materials.contains(id)));
    });
  }

  /// الـ Grade وخامته من القوائم المحملة.
  (MaterialItem, GradeItem)? _gradeOf(ReferenceData refs, String gradeId) {
    for (final m in refs.materials) {
      for (final g in m.grades) {
        if (g.id == gradeId) return (m, g);
      }
    }
    return null;
  }

  String _gradeLabel(ReferenceData refs, GradeItem g) {
    final maker = g.manufacturerId == null
        ? null
        : refs.manufacturer(g.manufacturerId!)?.name;
    return maker == null ? g.code : '${g.code} — $maker';
  }

  Future<void> _pickGrades(ReferenceData refs) async {
    final scope = _materials.isEmpty
        ? refs.materials
        : refs.materials.where((m) => _materials.contains(m.id)).toList();
    final options = [
      for (final m in scope)
        for (final g in m.grades)
          if (_makerId == null || g.manufacturerId == _makerId)
            _Option(
              g.id,
              _gradeLabel(refs, g),
              subtitle: m.code,
              search:
                  '${g.code} ${m.code} ${g.manufacturerId == null ? '' : refs.manufacturer(g.manufacturerId!)?.name ?? ''}',
            ),
    ];
    final picked = await _pick(
      title: 'الجريدات (Grades)',
      options: options,
      selected: {..._grades},
      addHint: 'كود Grade جديد (مثل 500P)',
      keyPrefix: 'grade',
      onAdd: (code) => _addGrade(refs, code),
    );
    if (picked == null) return;
    setState(() {
      _grades
        ..removeWhere((id) => !picked.contains(id))
        ..addAll(picked.where((id) => !_grades.contains(id)));
      // خامة كل Grade مختار تُضاف للخامات الرئيسية دون حذف غيرها.
      for (final id in _grades) {
        final m = _gradeOf(ref.read(referenceDataProvider).value ?? refs, id);
        if (m != null && !_materials.contains(m.$1.id)) _materials.add(m.$1.id);
      }
    });
  }

  /// Grade جديد يُربط بالخامة المختارة، وبالشركة فقط إن اختيرت صراحة.
  Future<_Option?> _addGrade(ReferenceData refs, String code) async {
    String? materialId;
    if (_materials.length == 1) {
      materialId = _materials.single;
    } else if (_materials.isEmpty) {
      showErrorSnack(context, 'اختر الخامة الرئيسية أولًا');
      return null;
    } else {
      materialId = (await _pick(
        title: 'خامة الـ Grade «$code»',
        options: [
          for (final id in _materials)
            if (refs.material(id) case final m?) _Option(m.id, m.code),
        ],
        selected: const {},
        multi: false,
        keyPrefix: 'gradeMaterial',
      ))?.firstOrNull;
      if (materialId == null) return null;
    }
    final repo = ref.read(crmRepositoryProvider);
    Future<_Option?> create({bool confirm = false}) async {
      final g = await repo.createGrade(
        materialId: materialId!,
        manufacturerId: _makerId,
        code: code,
        confirmSimilar: confirm,
      );
      ref.invalidate(referenceDataProvider);
      await ref.read(referenceDataProvider.future);
      final maker = _makerId == null ? null : refs.manufacturer(_makerId!);
      return _Option(
        g.id,
        maker == null ? g.code : '${g.code} — ${maker.name}',
        subtitle: refs.material(materialId!)?.code,
      );
    }

    try {
      return await create();
    } on ApiException catch (e) {
      if (e.code != 'catalog.similar_grade' || !mounted) {
        if (mounted) showErrorSnack(context, e.message);
        return null;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Grade مشابه'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('grade.confirmSimilar'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ليس نفس الـ Grade، أضفه'),
            ),
          ],
        ),
      );
      if (ok != true) return null;
      try {
        return await create(confirm: true);
      } on ApiException catch (e) {
        if (mounted) showErrorSnack(context, e.message);
        return null;
      }
    }
  }

  Future<void> _pickMaker(ReferenceData refs) async {
    int rank(ManufacturerItem m) {
      final i = ownerManufacturerOrder.indexWhere(
        (c) => c.toLowerCase() == m.name.toLowerCase(),
      );
      return i < 0 ? 1000 : i;
    }

    final list = [...refs.manufacturers]
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.name.compareTo(b.name);
      });
    final picked = await _pick(
      title: 'الشركة المصنعة',
      options: [for (final m in list) _Option(m.id, m.name, search: m.name)],
      selected: {?_makerId},
      multi: false,
      addHint: 'شركة مصنعة جديدة',
      keyPrefix: 'maker',
      onAdd: (name) async {
        try {
          final m = await ref
              .read(crmRepositoryProvider)
              .createManufacturer(name);
          ref.invalidate(referenceDataProvider);
          return _Option(m.id, m.name);
        } on ApiException catch (e) {
          if (mounted) showErrorSnack(context, e.message);
          return null;
        }
      },
    );
    if (picked != null) setState(() => _makerId = picked.firstOrNull);
  }

  Future<void> _pickGovernorate(ReferenceData refs) async {
    final picked = await _pick(
      title: 'المحافظة',
      options: [
        for (final g in refs.governorates)
          _Option(g.id, g.nameAr, search: g.nameAr),
      ],
      selected: {?_governorateId},
      multi: false,
      keyPrefix: 'governorate',
    );
    if (picked == null) return;
    setState(() {
      if (picked.firstOrNull != _governorateId) _region = null;
      _governorateId = picked.firstOrNull;
    });
  }

  Future<void> _pickCity(ReferenceData refs) async {
    final gov = _governorateId == null
        ? null
        : refs.governorates.where((g) => g.id == _governorateId).firstOrNull;
    final cities = egyptCities[gov?.nameAr] ?? const <String>[];
    final picked = await _pick(
      title: 'المنطقة / المدينة',
      options: [for (final c in cities) _Option(c, c, search: c)],
      selected: {?_region},
      multi: false,
      addHint: 'مدينة أو منطقة أخرى',
      keyPrefix: 'city',
      onAdd: (text) async => _Option(text, text),
    );
    if (picked != null) setState(() => _region = picked.firstOrNull);
  }

  // ------------------------- المواقع -------------------------

  _Site? _composedSite() {
    final url = _link.text.trim();
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    final address = _address.text.trim();
    final coords = MapsLink.coordinates(url);
    if (url.isEmpty &&
        lat == null &&
        address.isEmpty &&
        _governorateId == null &&
        _region == null) {
      return null;
    }
    return _Site(
      kind: _siteKind,
      label:
          _siteKind == LocationKind.other && _siteLabel.text.trim().isNotEmpty
          ? _siteLabel.text.trim()
          : null,
      governorateId: _governorateId,
      region: _region,
      address: address.isEmpty ? null : address,
      mapsUrl: url.isEmpty ? null : url,
      lat: lat ?? coords?.$1,
      lng: lng ?? coords?.$2,
    );
  }

  String? _siteError() {
    final url = _link.text.trim();
    if (url.isNotEmpty && !MapsLink.isGoogleMaps(url)) {
      return 'الرابط يجب أن يكون رابط Google Maps';
    }
    final lat = _lat.text.trim(), lng = _lng.text.trim();
    if (lat.isNotEmpty || lng.isNotEmpty) {
      final a = double.tryParse(lat), b = double.tryParse(lng);
      if (!MapsLink.valid(a, b)) return 'الإحداثيات غير صحيحة';
    }
    return null;
  }

  void _saveSite() {
    final error = _siteError();
    if (error != null) return showErrorSnack(context, error);
    final site = _composedSite();
    if (site == null) {
      return showErrorSnack(
        context,
        'أدخل العنوان أو المحافظة أو رابط الخريطة أو الإحداثيات',
      );
    }
    setState(() {
      _sites.add(site);
      for (final c in [_link, _lat, _lng, _siteLabel, _address]) {
        c.clear();
      }
    });
    showSuccessSnack(context, 'أُضيف الموقع: ${site.title}');
  }

  Future<void> _currentLocation() async {
    try {
      final (lat, lng) = await ref.read(deviceLocationProvider).current();
      setState(() {
        _siteMode = 'coords';
        _lat.text = lat.toStringAsFixed(6);
        _lng.text = lng.toStringAsFixed(6);
      });
    } on DeviceLocationException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    }
  }

  // ------------------------- الملفات -------------------------

  Future<bool?> _askCamera() => showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('source.camera'),
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('الكاميرا'),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            key: const Key('source.gallery'),
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('معرض الصور'),
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickLogo() async {
    final camera = await _askCamera();
    if (camera == null) return;
    final file = await ref.read(fileServicesProvider).pickImage(camera: camera);
    if (file == null || !mounted) return;
    if (file.size > 10 * 1024 * 1024) {
      return showErrorSnack(context, 'الحد الأقصى للصورة هو 10MB');
    }
    setState(() => _logo = file);
  }

  Future<void> _addFile() async {
    final file = await ref.read(fileServicesProvider).pickDocument(const [
      'pdf',
      'jpg',
      'jpeg',
      'png',
      'webp',
    ]);
    if (file == null || !mounted) return;
    final pdf = file.name.toLowerCase().endsWith('.pdf');
    if (file.size > (pdf ? 20 : 10) * 1024 * 1024) {
      return showErrorSnack(
        context,
        pdf ? 'الحد الأقصى لملف PDF هو 20MB' : 'الحد الأقصى للصورة هو 10MB',
      );
    }
    setState(() => _files.add((const Uuid().v7(), file)));
  }

  // ------------------------- التواصل والمشاركة -------------------------

  /// كل الأرقام الصحيحة المتاحة: رقم الشركة ثم الموظفون.
  List<(String, String)> _numbers() => [
    if (_phoneOk) ('رقم الشركة', _digits(_phone.text)),
    for (final e in _employees)
      if (ContactLauncher.toE164(e.phone.text) != null)
        (
          e.name.text.trim().isEmpty ? 'موظف' : e.name.text.trim(),
          _digits(e.phone.text),
        ),
  ];

  Future<void> _contact({required bool whatsApp}) async {
    final numbers = _numbers();
    if (numbers.isEmpty) {
      return showErrorSnack(context, 'أدخل رقم هاتف صحيح أولًا');
    }
    var chosen = numbers.first.$2;
    if (numbers.length > 1) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, number) in numbers)
                ListTile(
                  key: Key('contact.number.$number'),
                  leading: const Icon(Icons.phone_rounded),
                  title: Text(label),
                  subtitle: Text(number, textDirection: TextDirection.ltr),
                  onTap: () => Navigator.pop(context, number),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      chosen = picked;
    }
    final e164 = ContactLauncher.toE164(chosen)!;
    // يفتح التطبيق فقط؛ لا رسالة ولا اتصال تلقائي ولا تسجيل نشاط.
    if (whatsApp) {
      await ContactLauncher.whatsApp(e164);
    } else {
      await ContactLauncher.call(e164);
    }
  }

  Future<void> _share(ReferenceData refs) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => ContactSharePreview(
        name: _name.text.trim(),
        phone: _phoneOk ? _digits(_phone.text) : null,
        employees: [
          for (final e in _employees)
            if (!e.isEmpty)
              (
                e.name.text.trim(),
                e.jobTitle,
                e.phone.text.trim().isEmpty ? null : e.phone.text.trim(),
              ),
        ],
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        address: _addressText(refs, _governorateId, _region, _address.text),
        locations: [
          for (final s in _sites)
            (
              s.title,
              _addressText(refs, s.governorateId, s.region, s.address),
              s.link,
            ),
        ],
      ),
    );
    if (text != null) await ref.read(shareServiceProvider).text(text);
  }

  static String? _addressText(
    ReferenceData refs,
    String? governorateId,
    String? region,
    String? address,
  ) {
    final gov = governorateId == null
        ? null
        : refs.governorates.where((g) => g.id == governorateId).firstOrNull;
    final parts = [
      if (address case final a? when a.trim().isNotEmpty) a.trim(),
      ?region,
      ?gov?.nameAr,
    ];
    return parts.isEmpty ? null : parts.join(' - ');
  }

  Future<void> _assign(ReferenceData refs) async {
    final picked = await _pick(
      title: 'إسناد لمندوب',
      options: [
        for (final r in refs.representatives)
          _Option(r.id, r.name, search: r.name),
      ],
      selected: {?_representativeId},
      multi: false,
      keyPrefix: 'assign',
    );
    if (picked != null) setState(() => _representativeId = picked.firstOrNull);
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف السجل؟'),
        content: const Text(
          'لم يُحفظ هذا العميل بعد؛ ستُحذف كل البيانات المدخلة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('register.confirmDiscard'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) context.pop();
  }

  // ------------------------- الحفظ -------------------------

  /// بعد نجاح الحفظ لا يُعاد الإرسال (حتى لو ضُغط مرة أخرى قبل الانتقال).
  bool _saved = false;

  Future<void> _save(ReferenceData refs, {bool confirmSimilar = false}) async {
    if (!_valid || _saving || _saved) return;
    final siteError = _siteError();
    if (siteError != null) return showErrorSnack(context, siteError);
    // ما كُتب في بيانات الموقع ولم يُضغط «حفظ الموقع» يُحفظ أيضًا ولا يضيع.
    // المحافظة والمدينة وحدهما بعد مواقع محفوظة لا تُنشئ موقعًا مكررًا.
    if (_composedSite() case final pending?
        when _sites.isEmpty ||
            pending.mapsUrl != null ||
            pending.lat != null ||
            pending.address != null) {
      _sites.add(pending);
      for (final c in [_link, _lat, _lng, _siteLabel, _address]) {
        c.clear();
      }
    }
    final sites = [..._sites];
    final main =
        sites.where((s) => s.kind == LocationKind.headOffice).firstOrNull ??
        sites.firstOrNull;
    setState(() => _saving = true);
    final repo = ref.read(crmRepositoryProvider);
    try {
      final party = await repo.createParty(
        NewParty(
          id: _id,
          name: _name.text.trim(),
          phone: _digits(_phone.text),
          isCustomer: true,
          representativeId: _representativeId ?? refs.myRepresentativeId,
          specs: [
            for (final g in _grades)
              if (_gradeOf(refs, g) case (final m, _))
                SpecChoice(materialId: m.id, gradeId: g),
            for (final m in _materials)
              if (!_grades.any((g) => _gradeOf(refs, g)?.$1.id == m))
                SpecChoice(materialId: m),
          ],
          confirmSimilar: confirmSimilar,
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          governorateId: main?.governorateId,
          region: main?.region,
          addressLine: main?.address,
        ),
      );
      final partyId = party?.id ?? _id;
      // الإضافات بعد السجل نفسه؛ تنتظر في الطابور حتى يُرسل السجل.
      for (final (i, e) in _employees.where((e) => !e.isEmpty).indexed) {
        await repo.addContact(
          partyId,
          PartyContact(
            id: e.id,
            name: e.name.text.trim().isEmpty ? 'موظف' : e.name.text.trim(),
            jobTitle: e.jobTitle,
            mobile: e.phone.text.trim().isEmpty ? null : e.phone.text.trim(),
            isPrimary: i == 0,
          ),
        );
      }
      for (final (i, s) in sites.indexed) {
        await repo.createLocation(
          partyId,
          LocationDraft(
            id: s.id,
            kind: s.kind,
            label: s.label,
            addressLine: s.address,
            mapsUrl: s.mapsUrl,
            latitude: s.lat,
            longitude: s.lng,
            governorateId: s.governorateId,
            region: s.region,
            isDefault: identical(s, main) || (main == null && i == 0),
          ),
        );
      }
      if (_logo case final logo?) {
        await repo.uploadAttachment(
          partyId: partyId,
          id: _logoId,
          kind: AttachmentKind.logo,
          filePath: logo.path,
          fileName: logo.name,
        );
      }
      for (final (fileId, f) in _files) {
        await repo.uploadAttachment(
          partyId: partyId,
          id: fileId,
          kind: AttachmentKind.other,
          filePath: f.path,
          fileName: f.name,
        );
      }
      _saved = true;
      ref.invalidate(registryProvider);
      if (!mounted) return;
      if (party == null) {
        showSuccessSnack(context, 'تم الحفظ وأُرسل للإدارة');
        context.pop();
        return;
      }
      showSuccessSnack(
        context,
        party.version == 0
            ? 'حُفظ على الجهاز — بانتظار المزامنة'
            : 'تم حفظ العميل بنجاح',
      );
      context.pushReplacement(CrmRoutes.party(party.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _handleError(e, refs);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleError(ApiException e, ReferenceData refs) async {
    if (e.code case 'party.similar' || 'party.similar_hidden') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('سجل مشابه'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('similar.saveAnyway'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ليست نفس الشركة، احفظ'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) await _save(refs, confirmSimilar: true);
      return;
    }
    if (e.code == 'party.duplicate_phone') {
      final existing = DuplicateParty.fromData(e.data);
      // مسجل كمورد فقط: يُضاف له دور العميل وخاماته بدل تكرار الشركة.
      final canAddRole = existing != null && !existing.isCustomer;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('رقم مسجل بالفعل'),
          content: Text(
            canAddRole
                ? '${e.message} كمورد.\nيمكن إضافته كعميل لنفس الشركة دون تكرار.'
                : '${e.message}.\nافتح الملف الموجود بدل تسجيله مرة أخرى.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            if (canAddRole)
              TextButton(
                key: const Key('duplicate.addRole'),
                onPressed: () => Navigator.pop(context, 'role'),
                child: const Text('إضافته كعميل'),
              ),
            if (existing != null)
              FilledButton(
                key: const Key('duplicate.open'),
                onPressed: () => Navigator.pop(context, 'open'),
                child: const Text('فتح الملف'),
              ),
          ],
        ),
      );
      if (action == null || existing == null || !mounted) return;
      if (action == 'role') {
        final repo = ref.read(crmRepositoryProvider);
        try {
          await repo.addRole(existing.partyId, customer: true);
          for (final g in _grades) {
            if (_gradeOf(refs, g) case (final m, _)) {
              await repo.addInterest(
                existing.partyId,
                SpecChoice(materialId: m.id, gradeId: g),
              );
            }
          }
        } on ApiException catch (e) {
          if (mounted) showErrorSnack(context, e.message);
          return;
        }
      }
      if (mounted) context.pushReplacement(CrmRoutes.party(existing.partyId));
      return;
    }
    showErrorSnack(context, e.message);
  }

  // ------------------------- الواجهة -------------------------

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider);
    final auth = ref.watch(authControllerProvider);
    final user = auth is Authenticated ? auth.user : null;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(
            canSave: _valid && !_saving && refs.hasValue,
            saving: _saving,
            onSave: () => _save(refs.requireValue),
          ),
          Expanded(
            child: AsyncBody(
              value: refs,
              onRetry: () => ref.invalidate(referenceDataProvider),
              data: (r) => _form(r, user),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(ReferenceData refs, AuthUser? user) {
    final canAssign = ref.watch(canAssignProvider);
    final rep = _representativeId == null
        ? null
        : refs.representatives
              .where((r) => r.id == _representativeId)
              .firstOrNull;
    final gov = _governorateId == null
        ? null
        : refs.governorates.where((g) => g.id == _governorateId).firstOrNull;
    final siteQuery = _siteSearch.text.trim();
    return SingleChildScrollView(
      key: const Key('register.list'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label(
                    'اسم الشركة',
                    Icons.apartment_rounded,
                    required: true,
                  ),
                  TextField(
                    key: const Key('register.name'),
                    controller: _name,
                    decoration: _decoration(
                      'أدخل اسم الشركة الكامل',
                      state: _name.text.isEmpty ? null : _nameOk,
                    ),
                  ),
                  for (final s in _similar)
                    InkWell(
                      key: Key('register.similar.${s.id}'),
                      onTap: () => context.push(CrmRoutes.party(s.id)),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'مسجل: ${s.name}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.reportsAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _Card(
              child: InkWell(
                key: const Key('register.logo'),
                onTap: _pickLogo,
                child: Column(
                  children: [
                    const _Label('صورة الشركة', null, center: true),
                    Stack(
                      alignment: Alignment.bottomLeft,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: const Color(0xFFE8EEF7),
                          child: _logo == null
                              ? const Icon(
                                  Icons.domain_rounded,
                                  size: 42,
                                  color: Color(0xFFA7B4C8),
                                )
                              : const Icon(
                                  Icons.check_circle_rounded,
                                  size: 42,
                                  color: AppColors.greenDark,
                                ),
                        ),
                        const CircleAvatar(
                          radius: 15,
                          backgroundColor: AppColors.primary,
                          child: Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _logo?.name ?? 'أضف صورة الشركة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.hint,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _row(
            _Card(
              key: const Key('register.identity'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label(
                    'المندوب: ${roleTitle(user?.roles ?? const [])}',
                    Icons.person_rounded,
                  ),
                  Text(
                    user?.displayName ?? '',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('رقم الهاتف الأساسي', null, required: true),
                  _PhoneField(
                    fieldKey: const Key('register.phone'),
                    controller: _phone,
                    valid: _phone.text.isEmpty ? null : _phoneOk,
                  ),
                ],
              ),
            ),
          ),
          for (final (i, e) in _employees.indexed) ..._employeeRows(i, e),
          _Card(
            key: const Key('register.materials'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: _Label(
                        'الخامات الرئيسية',
                        Icons.layers_rounded,
                        required: true,
                      ),
                    ),
                    _BlueButton(
                      'إضافة خامة',
                      key: const Key('register.addMaterial'),
                      onTap: () => _pickMaterials(refs),
                    ),
                  ],
                ),
                _SearchBox(
                  'ابحث عن خامة أو درجة أو صنف',
                  key: const Key('register.materialSearch'),
                  onTap: () => _pickMaterials(refs),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final id in _materials)
                      if (refs.material(id) case final m?)
                        _ChipX(
                          m.code,
                          key: Key('register.material.${m.code}'),
                          onRemove: () => setState(() {
                            _materials.remove(id);
                            _grades.removeWhere(
                              (g) => _gradeOf(refs, g)?.$1.id == id,
                            );
                          }),
                        ),
                  ],
                ),
              ],
            ),
          ),
          _Card(
            key: const Key('register.grades'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: _Label(
                        'الجريدات (Grades)',
                        Icons.view_in_ar_rounded,
                        required: true,
                      ),
                    ),
                    _BlueButton(
                      'إضافة جريد',
                      key: const Key('register.addGrade'),
                      onTap: () => _pickGrades(refs),
                    ),
                  ],
                ),
                _SearchBox(
                  'ابحث عن جريد أو صنف',
                  key: const Key('register.gradeSearch'),
                  onTap: () => _pickGrades(refs),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final id in _grades)
                      if (_gradeOf(refs, id) case (final m, final g))
                        _ChipX(
                          '${m.code} · ${_gradeLabel(refs, g)}',
                          key: Key('register.grade.${g.code}'),
                          onRemove: () => setState(() => _grades.remove(id)),
                        ),
                  ],
                ),
                const SizedBox(height: 8),
                const _Label(
                  'الشركة المصنعة',
                  Icons.factory_rounded,
                  small: true,
                ),
                _Dropdown(
                  key: const Key('register.maker'),
                  hint: 'اختر الشركة المصنعة',
                  value: _makerId == null
                      ? null
                      : refs.manufacturer(_makerId!)?.name,
                  onTap: () => _pickMaker(refs),
                ),
              ],
            ),
          ),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Label('العنوان التفصيلي', Icons.location_on_rounded),
                TextField(
                  key: const Key('register.address'),
                  controller: _address,
                  decoration: _decoration(
                    'أدخل العنوان بالتفصيل ( الشارع - المنطقة - المدينة ... )',
                  ),
                ),
              ],
            ),
          ),
          _row(
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label(
                    'المنطقة / المدينة',
                    Icons.location_city_rounded,
                  ),
                  _Dropdown(
                    key: const Key('register.city'),
                    hint: 'اختر المنطقة / المدينة',
                    value: _region,
                    onTap: () => _pickCity(refs),
                  ),
                ],
              ),
            ),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('المحافظة', Icons.location_on_rounded),
                  _Dropdown(
                    key: const Key('register.governorate'),
                    hint: 'اختر المحافظة',
                    value: gov?.nameAr,
                    onTap: () => _pickGovernorate(refs),
                  ),
                ],
              ),
            ),
          ),
          _Card(
            key: const Key('register.sites'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: _Label('مواقع الشركة', Icons.location_on_rounded),
                    ),
                    _BlueButton(
                      'إضافة موقع',
                      key: const Key('register.addSite'),
                      onTap: _saveSite,
                    ),
                  ],
                ),
                TextField(
                  key: const Key('register.siteSearch'),
                  controller: _siteSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: _decoration(
                    'ابحث عن موقع للشركة',
                    prefix: const Icon(Icons.search_rounded),
                  ),
                ),
                for (final (i, s) in _sites.indexed)
                  if (siteQuery.isEmpty ||
                      '${s.title} ${s.address ?? ''} ${s.region ?? ''}'
                          .contains(siteQuery))
                    ListTile(
                      key: Key('register.site.$i'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.place_rounded,
                        color: AppColors.primary,
                      ),
                      title: Text(s.title),
                      subtitle: Text(
                        [
                          ?_addressText(
                            refs,
                            s.governorateId,
                            s.region,
                            s.address,
                          ),
                          if (s.link != null) 'رابط خريطة',
                        ].join(' • '),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _sites.removeAt(i)),
                      ),
                    ),
                const SizedBox(height: 8),
                const _Label(
                  'نوع الموقع',
                  Icons.navigation_rounded,
                  small: true,
                ),
                Row(
                  children: [
                    // عرض كل خيار حسب طول اسمه حتى يبقى الخط بحجم واحد تقريبًا.
                    for (final k in LocationKind.values)
                      Expanded(
                        flex: k.nameAr.length + 3,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _Segment(
                            k.nameAr,
                            key: Key('register.siteKind.${k.name}'),
                            selected: _siteKind == k,
                            onTap: () => setState(() => _siteKind = k),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_siteKind == LocationKind.other) ...[
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('register.siteLabel'),
                    controller: _siteLabel,
                    decoration: _decoration('نوع الموقع (مثل مكتب)'),
                  ),
                ],
                const SizedBox(height: 10),
                const _Label(
                  'تحديد الموقع',
                  Icons.my_location_rounded,
                  small: true,
                ),
                Row(
                  children: [
                    for (final (mode, label, icon) in [
                      ('link', 'لصق رابط', Icons.link_rounded),
                      ('current', 'موقعي الحالي', Icons.gps_fixed_rounded),
                      ('coords', 'إحداثيات', Icons.location_on_rounded),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _Segment(
                            label,
                            icon: icon,
                            key: Key('register.siteMode.$mode'),
                            selected: _siteMode == mode,
                            onTap: () {
                              setState(() => _siteMode = mode);
                              if (mode == 'current') _currentLocation();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_siteMode == 'link')
                  TextField(
                    key: const Key('register.siteLink'),
                    controller: _link,
                    textDirection: TextDirection.ltr,
                    decoration: _decoration(
                      'الصق رابط Google Maps',
                      suffix: IconButton(
                        tooltip: 'فتح الخرائط',
                        icon: const Icon(Icons.map_rounded),
                        onPressed: () => ContactLauncher.openUrl(
                          'https://www.google.com/maps',
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('register.siteLat'),
                          controller: _lat,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          textDirection: TextDirection.ltr,
                          decoration: _decoration('خط العرض'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('register.siteLng'),
                          controller: _lng,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          textDirection: TextDirection.ltr,
                          decoration: _decoration('خط الطول'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('register.saveSite'),
                  onPressed: _saveSite,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('حفظ الموقع'),
                ),
              ],
            ),
          ),
          _Card(
            key: const Key('register.attachments'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.attach_file_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'المرفقات',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _files.isEmpty
                                ? 'لا توجد ملفات مرفقة'
                                : '${_files.length} ملف',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('register.addFile'),
                      onPressed: _addFile,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة'),
                    ),
                  ],
                ),
                for (final (i, (_, f)) in _files.indexed)
                  ListTile(
                    key: Key('register.file.$i'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      f.name.toLowerCase().endsWith('.pdf')
                          ? Icons.picture_as_pdf_rounded
                          : Icons.image_rounded,
                      color: f.name.toLowerCase().endsWith('.pdf')
                          ? AppColors.error
                          : AppColors.primary,
                    ),
                    title: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('يُرفع بعد الحفظ'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _files.removeAt(i)),
                    ),
                  ),
              ],
            ),
          ),
          _row(
            _Action(
              rep == null ? 'إسناد لمندوب' : 'مسند إلى: ${rep.name}',
              Icons.assignment_ind_rounded,
              key: const Key('register.assign'),
              onTap: canAssign ? () => _assign(refs) : null,
            ),
            _Action(
              'مشاركة بيانات التواصل',
              Icons.share_rounded,
              key: const Key('register.share'),
              onTap: _nameOk ? () => _share(refs) : null,
            ),
          ),
          _Card(
            child: Row(
              children: [
                const Expanded(
                  child: _Label('حالة الشركة', Icons.check_box_rounded),
                ),
                Container(
                  key: const Key('register.status'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F5E1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'شركة جديدة',
                    style: TextStyle(
                      color: AppColors.greenDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  'اتصال',
                  Icons.phone_rounded,
                  key: const Key('register.call'),
                  color: AppColors.primary,
                  onTap: _numbers().isEmpty
                      ? null
                      : () => _contact(whatsApp: false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigButton(
                  'واتساب',
                  Icons.chat_rounded,
                  key: const Key('register.whatsapp'),
                  color: const Color(0xFF1FA34A),
                  onTap: _numbers().isEmpty
                      ? null
                      : () => _contact(whatsApp: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // لا توجد بيانات محفوظة بعد: التعديل والاستكمال من بطاقة العميل بعد الحفظ.
              const Expanded(
                child: _OutlineButton(
                  'تعديل البيانات واستكمالها',
                  Icons.edit_rounded,
                  key: Key('register.edit'),
                  color: AppColors.primary,
                  onTap: null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlineButton(
                  'حذف السجل',
                  Icons.delete_rounded,
                  key: const Key('register.discard'),
                  color: AppColors.error,
                  onTap: _discard,
                ),
              ),
            ],
          ),
          if (!_valid) ...[
            const SizedBox(height: 10),
            Text(
              key: const Key('register.missing'),
              'للحفظ: ${[if (!_nameOk) 'اسم الشركة', if (!_phoneOk) 'رقم موبايل صحيح (010/011/012/015)', if (!_gradeOk) 'خامة + Grade', if (!_emailOk) 'بريد إلكتروني صحيح أو فارغ'].join('، ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  /// البريد بجوار الموظف الأساسي كما في التصميم المعتمد.
  Widget _emailCard() => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('البريد الإلكتروني', Icons.check_box_rounded),
        TextField(
          key: const Key('register.email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: _decoration(
            'أدخل البريد الإلكتروني',
            state: _email.text.trim().isEmpty ? null : _emailOk,
          ),
        ),
      ],
    ),
  );

  List<Widget> _employeeRows(int i, _Employee e) {
    final name = _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Label(
                  i == 0 ? 'اسم الموظف الأساسي' : 'اسم الموظف ${i + 1}',
                  Icons.groups_rounded,
                ),
              ),
              if (i == _employees.length - 1)
                InkWell(
                  key: const Key('register.addEmployee'),
                  onTap: () => setState(() => _employees.add(_Employee())),
                  child: const Icon(
                    Icons.add_circle_rounded,
                    color: AppColors.primary,
                  ),
                )
              else if (i > 0)
                InkWell(
                  onTap: () => setState(() => _employees.removeAt(i).dispose()),
                  child: const Icon(Icons.close_rounded, color: AppColors.hint),
                ),
            ],
          ),
          TextField(
            key: Key('register.employee.$i.name'),
            controller: e.name,
            decoration: _decoration('أدخل اسم الموظف المسؤول'),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: Key('register.employee.$i.title'),
            initialValue: e.title,
            isExpanded: true,
            decoration: _decoration('الوظيفة'),
            items: [
              for (final t in jobTitles)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => e.title = v),
          ),
          if (e.title == 'وظيفة أخرى') ...[
            const SizedBox(height: 6),
            TextField(
              key: Key('register.employee.$i.customTitle'),
              controller: e.customTitle,
              decoration: _decoration('اكتب الوظيفة'),
            ),
          ],
        ],
      ),
    );
    final phone = _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('رقم هاتف الموظف', Icons.phone_rounded),
          _PhoneField(
            fieldKey: Key('register.employee.$i.phone'),
            controller: e.phone,
            valid: e.phone.text.isEmpty
                ? null
                : ContactLauncher.toE164(e.phone.text) != null,
            onChanged: () => setState(() {}),
          ),
        ],
      ),
    );
    return i == 0
        ? [_row(name, _emailCard()), _row(phone, const SizedBox())]
        : [_row(name, phone)];
  }

  // بلا IntrinsicHeight: حساب الارتفاع المسبق يخطئ مع القوائم المنسدلة فيقص المحتوى.
  Widget _row(Widget start, Widget end) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: start),
      const SizedBox(width: 10),
      Expanded(child: end),
    ],
  );
}

InputDecoration _decoration(
  String hint, {
  bool? state,
  Widget? prefix,
  Widget? suffix,
}) {
  final color = switch (state) {
    true => AppColors.greenDark,
    false => AppColors.error,
    null => AppColors.fieldBorder,
  };
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: state == null ? 1 : 1.6),
  );
  return InputDecoration(
    hintText: hint,
    hintMaxLines: 1,
    hintStyle: const TextStyle(
      color: AppColors.hint,
      fontSize: 14,
      overflow: TextOverflow.ellipsis,
    ),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(
        color: state == null ? AppColors.primary : color,
        width: 1.8,
      ),
    ),
    prefixIcon: prefix,
    suffixIcon: suffix,
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canSave,
    required this.saving,
    required this.onSave,
  });

  final bool canSave;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [AppColors.primary, AppColors.primaryBright],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Row(
          children: [
            IconButton(
              key: const Key('register.back'),
              icon: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
              ),
              onPressed: () => context.pop(),
            ),
            const Expanded(
              child: Text(
                'تسجيل عميل',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Material(
              color: Colors.white.withValues(alpha: canSave ? 0.22 : 0.10),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: const Key('register.save'),
                borderRadius: BorderRadius.circular(12),
                onTap: canSave ? onSave : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        saving ? 'جارٍ الحفظ' : 'حفظ',
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: canSave ? 1 : 0.6,
                          ),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_rounded,
                        color: Colors.white.withValues(
                          alpha: canSave ? 1 : 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE3EAF5)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F0B3C78),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

class _Label extends StatelessWidget {
  const _Label(
    this.text,
    this.icon, {
    this.required = false,
    this.small = false,
    this.center = false,
  });

  final String text;
  final IconData? icon;
  final bool required;
  final bool small;
  final bool center;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, color: AppColors.primary, size: small ? 20 : 24),
          const SizedBox(width: 6),
        ],
        // سطر واحد يُصغَّر عند الضيق حتى تبقى بطاقتا الصف بنفس الارتفاع.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              text,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: small ? 14 : 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        if (required) ...[
          const SizedBox(width: 6),
          const Text(
            'أساسي',
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ],
    ),
  );
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.fieldKey,
    required this.controller,
    required this.valid,
    this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final bool? valid;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    textDirection: TextDirection.ltr,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.fieldBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🇪🇬', style: TextStyle(fontSize: 16)),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: TextField(
          key: fieldKey,
          controller: controller,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          maxLength: 11,
          onChanged: onChanged == null ? null : (_) => onChanged!(),
          decoration: _decoration('01XXXXXXXXX', state: valid).copyWith(
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 14,
            ),
            hintStyle: const TextStyle(color: AppColors.hint, fontSize: 13),
          ),
        ),
      ),
    ],
  );
}

class _SearchBox extends StatelessWidget {
  const _SearchBox(this.hint, {super.key, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _decoration(hint, prefix: const Icon(Icons.search_rounded)),
        child: const SizedBox(height: 18),
      ),
    ),
  );
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    super.key,
    required this.hint,
    required this.value,
    required this.onTap,
  });

  final String hint;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: _decoration(
        hint,
        suffix: const Icon(Icons.keyboard_arrow_down_rounded),
      ),
      isEmpty: value == null,
      child: value == null
          ? null
          : Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

class _BlueButton extends StatelessWidget {
  const _BlueButton(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: const Icon(Icons.add_rounded, size: 22),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _ChipX extends StatelessWidget {
  const _ChipX(this.label, {super.key, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(right: 12, left: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FC),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.close_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          onPressed: onRemove,
        ),
      ],
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.fieldBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, {super.key, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _Card(
    child: InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: onTap == null ? AppColors.hint : AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: onTap == null ? AppColors.hint : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BigButton extends StatelessWidget {
  const _BigButton(
    this.label,
    this.icon, {
    super.key,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: Icon(icon),
    label: Text(
      label,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    ),
  );
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton(
    this.label,
    this.icon, {
    super.key,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: onTap == null ? AppColors.fieldBorder : color),
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: Icon(icon),
    label: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// قائمة بحث قابلة للتمرير؛ آخر عنصر دائمًا حقل فارغ مع (+) للإضافة الفورية.
class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.multi,
    required this.keyPrefix,
    this.addHint,
    this.onAdd,
  });

  final String title;
  final List<_Option> options;
  final Set<String> selected;
  final bool multi;
  final String keyPrefix;
  final String? addHint;
  final Future<_Option?> Function(String text)? onAdd;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _query = TextEditingController();
  final _add = TextEditingController();
  late final _options = [...widget.options];
  late final _selected = {...widget.selected};
  bool _adding = false;

  @override
  void dispose() {
    _query.dispose();
    _add.dispose();
    super.dispose();
  }

  Future<void> _submitAdd() async {
    final text = _add.text.trim();
    if (text.isEmpty || _adding || widget.onAdd == null) return;
    final key = text.toLowerCase();
    // موجود بنفس الاسم: يُختار بدل إضافته مرة أخرى.
    final existing = _options
        .where((o) => o.label.toLowerCase().split(' — ').first == key)
        .firstOrNull;
    if (existing != null) return _toggle(existing.id);
    setState(() => _adding = true);
    final added = await widget.onAdd!(text);
    if (!mounted) return;
    setState(() {
      _adding = false;
      if (added != null) {
        _options.add(added);
        _add.clear();
      }
    });
    if (added != null) _toggle(added.id);
  }

  void _toggle(String id) {
    if (!widget.multi) {
      Navigator.pop(context, {id});
      return;
    }
    setState(
      () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final shown = [
      for (final o in _options)
        if (q.isEmpty ||
            o.label.toLowerCase().contains(q) ||
            o.search.toLowerCase().contains(q))
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
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: _decoration(
                  'اكتب للبحث',
                  prefix: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in shown)
                    ListTile(
                      key: Key('${widget.keyPrefix}.option.${o.label}'),
                      dense: true,
                      title: Text(
                        o.label,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                      ),
                      subtitle: o.subtitle == null ? null : Text(o.subtitle!),
                      trailing: widget.multi
                          ? Icon(
                              _selected.contains(o.id)
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: AppColors.primary,
                            )
                          : null,
                      onTap: () => _toggle(o.id),
                    ),
                  if (widget.onAdd != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: Key('${widget.keyPrefix}.addField'),
                              controller: _add,
                              onSubmitted: (_) => _submitAdd(),
                              decoration: _decoration(
                                widget.addHint ?? 'إضافة',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filled(
                            key: Key('${widget.keyPrefix}.add'),
                            onPressed: _adding ? null : _submitAdd,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (widget.multi)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    key: Key('${widget.keyPrefix}.done'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text('تم (${_selected.length})'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// معاينة «مشاركة بيانات التواصل» قبل الإرسال: اختيار الحقول والمواقع.
class ContactSharePreview extends StatefulWidget {
  const ContactSharePreview({
    super.key,
    required this.name,
    this.phone,
    this.employees = const [],
    this.email,
    this.address,
    this.locations = const [],
  });

  final String name;
  final String? phone;

  /// (الاسم، الوظيفة، الرقم).
  final List<(String, String?, String?)> employees;
  final String? email;
  final String? address;

  /// (العنوان، الوصف، الرابط).
  final List<(String, String?, String?)> locations;

  @override
  State<ContactSharePreview> createState() => _ContactSharePreviewState();
}

class _ContactSharePreviewState extends State<ContactSharePreview> {
  final _on = <String>{'name', 'phone', 'employees', 'email', 'address'};
  late final _sites = <int>{
    for (var i = 0; i < widget.locations.length; i++) i,
  };

  String get _text => [
    if (_on.contains('name')) widget.name,
    if (_on.contains('phone') && widget.phone != null) 'هاتف: ${widget.phone}',
    if (_on.contains('employees'))
      for (final (name, title, phone) in widget.employees)
        [
          [name, ?title].where((x) => x.isNotEmpty).join(' - '),
          ?phone,
        ].join(': '),
    if (_on.contains('email') && widget.email != null) 'بريد: ${widget.email}',
    if (_on.contains('address') && widget.address != null)
      'العنوان: ${widget.address}',
    for (final i in _sites)
      if (widget.locations[i] case (final title, final addr, final link))
        [title, ?addr, if (link != null) 'الخريطة: $link'].join('\n'),
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    Widget check(String key, String label, bool available) => available
        ? CheckboxListTile(
            key: Key('share.field.$key'),
            dense: true,
            value: _on.contains(key),
            title: Text(label),
            onChanged: (v) =>
                setState(() => v == true ? _on.add(key) : _on.remove(key)),
          )
        : const SizedBox.shrink();
    return AlertDialog(
      title: const Text('مشاركة بيانات التواصل'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            check('name', 'اسم الشركة', true),
            check('phone', 'رقم الشركة', widget.phone != null),
            check(
              'employees',
              'الموظفون وأرقامهم',
              widget.employees.isNotEmpty,
            ),
            check('email', 'البريد الإلكتروني', widget.email != null),
            check('address', 'العنوان', widget.address != null),
            for (final (i, (title, _, _)) in widget.locations.indexed)
              CheckboxListTile(
                key: Key('share.site.$i'),
                dense: true,
                value: _sites.contains(i),
                title: Text(title),
                onChanged: (v) => setState(
                  () => v == true ? _sites.add(i) : _sites.remove(i),
                ),
              ),
            const Divider(),
            Container(
              key: const Key('share.preview'),
              padding: const EdgeInsets.all(8),
              color: AppColors.fieldFill,
              child: Text(_text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('share.send'),
          onPressed: _text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _text),
          child: const Text('مشاركة'),
        ),
      ],
    );
  }
}
