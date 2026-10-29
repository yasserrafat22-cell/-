import 'crm_models.dart';
import 'maps_link.dart';

enum LocationKind {
  headOffice('المقر الرئيسي'),
  factory('المصنع'),
  warehouse('المخزن'),
  loading('موقع التحميل'),
  delivery('موقع التسليم'),
  other('موقع آخر');

  const LocationKind(this.nameAr);

  final String nameAr;
}

/// موقع محفوظ لعميل أو مورد.
class PartyLocation {
  const PartyLocation({
    required this.id,
    required this.partyId,
    required this.kind,
    this.label,
    this.addressLine,
    this.mapsUrl,
    this.latitude,
    this.longitude,
    this.accessNotes,
    this.isDefault = false,
    this.version = 0,
  });

  final String id;
  final String partyId;
  final LocationKind kind;
  final String? label;
  final String? addressLine;
  final String? mapsUrl;
  final double? latitude;
  final double? longitude;
  final String? accessNotes;
  final bool isDefault;
  final int version;

  /// «المخزن — موقع التحميل» أو نوع الموقع فقط.
  String get title =>
      label == null || label!.isEmpty ? kind.nameAr : '${kind.nameAr} — $label';

  bool get hasCoordinates => MapsLink.valid(latitude, longitude);

  String? get link => MapsLink.forLocation(
    url: mapsUrl,
    lat: latitude,
    lng: longitude,
    address: addressLine,
  );

  /// رابط موثوق فقط للسائق: الرابط المحفوظ، أو رابط من إحداثيات محفوظة.
  /// لا يُبنى رابط من نص العنوان حتى لا يُرسل موقع غير مؤكد.
  String? get verifiedLink =>
      MapsLink.forLocation(url: mapsUrl, lat: latitude, lng: longitude);

  /// رسالة «إرسال للسائق» بالنموذج المعتمد. الحقول غير المتوفرة تُحذف.
  /// [loading] موقع تحميل من مورد، وإلا موقع تسليم لعميل.
  String driverMessage({required String partyName, required bool loading}) => [
    loading ? '🚚 بيانات موقع التحميل' : '🚚 بيانات موقع التسليم',
    loading ? '🏭 المورد: $partyName' : '🏢 العميل: $partyName',
    '📦 الموقع: $title',
    if (addressLine case final a? when a.trim().isNotEmpty)
      '📍 العنوان: ${a.trim()}',
    if (verifiedLink case final l?) '🗺️ رابط الخريطة:\n$l',
    if (accessNotes case final n? when n.trim().isNotEmpty)
      '📝 تعليمات الوصول:\n${n.trim()}',
  ].join('\n\n');

  /// نص المشاركة (واتساب أو غيره).
  String shareText(String partyName) => [
    partyName,
    title,
    if (addressLine case final a? when a.isNotEmpty) 'العنوان: $a',
    if (link case final l?) 'الخريطة: $l',
    if (accessNotes case final n? when n.isNotEmpty) 'ملاحظات الوصول: $n',
  ].join('\n');

  factory PartyLocation.fromJson(Json j) => PartyLocation(
    id: j['id'] as String,
    partyId: j['partyId'] as String,
    kind: LocationKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => LocationKind.other,
    ),
    label: j['label'] as String?,
    addressLine: j['addressLine'] as String?,
    mapsUrl: j['mapsUrl'] as String?,
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    accessNotes: j['accessNotes'] as String?,
    isDefault: j['isDefault'] as bool? ?? false,
    version: (j['version'] as num?)?.toInt() ?? 0,
  );
}

/// بيانات موقع جديد أو معدّل قبل الحفظ.
class LocationDraft {
  const LocationDraft({
    required this.id,
    required this.kind,
    this.label,
    this.addressLine,
    this.mapsUrl,
    this.latitude,
    this.longitude,
    this.accessNotes,
    this.isDefault = false,
  });

  final String id;
  final LocationKind kind;
  final String? label;
  final String? addressLine;
  final String? mapsUrl;
  final double? latitude;
  final double? longitude;
  final String? accessNotes;
  final bool isDefault;

  Json toJson({int version = 0}) => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'addressLine': addressLine,
    'mapsUrl': mapsUrl,
    'latitude': latitude,
    'longitude': longitude,
    'accessNotes': accessNotes,
    'isDefault': isDefault,
    'version': version,
  };
}
