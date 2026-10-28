/// نماذج بيانات العملاء والموردين كما يعيدها السيرفر (`/api/v1`).
library;

import 'material_spec.dart';

export 'material_spec.dart';

typedef Json = Map<String, dynamic>;

List<T> _list<T>(Object? value, T Function(Json) parse) =>
    (value as List? ?? const []).cast<Json>().map(parse).toList();

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

double? _num(Object? v) => (v as num?)?.toDouble();

T _enum<T extends Enum>(List<T> values, Object? name) =>
    values.firstWhere((v) => v.name == name, orElse: () => values.first);

class LookupItem {
  const LookupItem({
    required this.id,
    required this.code,
    required this.nameAr,
    this.semantic,
    this.appliesTo = 'both',
  });

  final String id;
  final String code;
  final String nameAr;
  final String? semantic;
  final String appliesTo;

  bool appliesToCustomer() => appliesTo == 'both' || appliesTo == 'customer';
  bool appliesToSupplier() => appliesTo == 'both' || appliesTo == 'supplier';

  factory LookupItem.fromJson(Json j) => LookupItem(
    id: j['id'] as String,
    code: j['code'] as String,
    nameAr: j['nameAr'] as String,
    semantic: j['semantic'] as String?,
    appliesTo: j['appliesTo'] as String? ?? 'both',
  );
}

class UnitItem {
  const UnitItem({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.factorToKg,
  });

  final String id;
  final String code;
  final String nameAr;
  final double factorToKg;

  factory UnitItem.fromJson(Json j) => UnitItem(
    id: j['id'] as String,
    code: j['code'] as String,
    nameAr: j['nameAr'] as String,
    factorToKg: _num(j['factorToKg'])!,
  );
}

class GradeItem {
  const GradeItem({
    required this.id,
    required this.code,
    this.manufacturerId,
    this.verified = true,
    this.originIds = const [],
  });

  final String id;
  final String code;
  final String? manufacturerId;
  final bool verified;
  final List<String> originIds;

  factory GradeItem.fromJson(Json j) => GradeItem(
    id: j['id'] as String,
    code: j['code'] as String,
    manufacturerId: j['manufacturerId'] as String?,
    verified: j['isVerified'] as bool? ?? true,
    originIds: (j['originIds'] as List? ?? const []).cast<String>(),
  );
}

class ManufacturerItem {
  const ManufacturerItem({required this.id, required this.name});

  final String id;
  final String name;

  factory ManufacturerItem.fromJson(Json j) =>
      ManufacturerItem(id: j['id'] as String, name: j['name'] as String);
}

class MaterialItem {
  const MaterialItem({
    required this.id,
    required this.code,
    required this.nameAr,
    this.grades = const [],
  });

  final String id;
  final String code;
  final String nameAr;
  final List<GradeItem> grades;

  factory MaterialItem.fromJson(Json j) => MaterialItem(
    id: j['id'] as String,
    code: j['code'] as String,
    nameAr: j['nameAr'] as String,
    grades: _list(j['grades'], GradeItem.fromJson),
  );
}

class RepresentativeItem {
  const RepresentativeItem({required this.id, required this.name});

  final String id;
  final String name;

  factory RepresentativeItem.fromJson(Json j) =>
      RepresentativeItem(id: j['id'] as String, name: j['name'] as String);
}

/// القوائم الأساسية التي تُدار من الإعدادات.
class ReferenceData {
  const ReferenceData({
    required this.activityTypes,
    required this.contactOutcomes,
    required this.governorates,
    required this.currencies,
    required this.units,
    required this.materials,
    required this.representatives,
    this.myRepresentativeId,
    this.manufacturers = const [],
    this.countries = const [],
  });

  final List<LookupItem> activityTypes;
  final List<LookupItem> contactOutcomes;
  final List<LookupItem> governorates;
  final List<LookupItem> currencies;
  final List<UnitItem> units;
  final List<MaterialItem> materials;
  final List<RepresentativeItem> representatives;
  final String? myRepresentativeId;
  final List<ManufacturerItem> manufacturers;
  final List<LookupItem> countries;

  MaterialItem? material(String id) =>
      materials.where((m) => m.id == id).firstOrNull;

  GradeItem? grade(String id) =>
      materials.expand((m) => m.grades).where((g) => g.id == id).firstOrNull;

  ManufacturerItem? manufacturer(String id) =>
      manufacturers.where((m) => m.id == id).firstOrNull;

  LookupItem? country(String id) =>
      countries.where((c) => c.id == id).firstOrNull;

  UnitItem? unit(String id) => units.where((u) => u.id == id).firstOrNull;

  LookupItem? lookup(String? id) =>
      [...activityTypes, ...governorates].where((l) => l.id == id).firstOrNull;

  factory ReferenceData.fromJson(Json j) => ReferenceData(
    activityTypes: _list(j['activityTypes'], LookupItem.fromJson),
    contactOutcomes: _list(j['contactOutcomes'], LookupItem.fromJson),
    governorates: _list(j['governorates'], LookupItem.fromJson),
    currencies: _list(j['currencies'], LookupItem.fromJson),
    units: _list(j['units'], UnitItem.fromJson),
    materials: _list(j['materials'], MaterialItem.fromJson),
    representatives: _list(j['representatives'], RepresentativeItem.fromJson),
    myRepresentativeId: j['myRepresentativeId'] as String?,
    manufacturers: _list(j['manufacturers'], ManufacturerItem.fromJson),
    countries: _list(j['countries'], LookupItem.fromJson),
  );
}

enum PartyStatus { newParty, active, needsFollowUp, stopped }

PartyStatus _status(Object? name) => switch (name) {
  'active' => PartyStatus.active,
  'needsFollowUp' => PartyStatus.needsFollowUp,
  'stopped' => PartyStatus.stopped,
  _ => PartyStatus.newParty,
};

class PartySummary {
  const PartySummary({
    required this.status,
    this.lastDealDate,
    this.lastDealQuantityKg,
    this.lastContactAt,
    this.nextFollowUpAt,
  });

  final PartyStatus status;
  final DateTime? lastDealDate;
  final double? lastDealQuantityKg;
  final DateTime? lastContactAt;
  final DateTime? nextFollowUpAt;

  static PartySummary? fromJson(Object? value) {
    if (value is! Json) return null;
    return PartySummary(
      status: _status(value['status']),
      lastDealDate: _date(value['lastDealDate']),
      lastDealQuantityKg: _num(value['lastDealQuantityKg']),
      lastContactAt: _date(value['lastContactAt'])?.toLocal(),
      nextFollowUpAt: _date(value['nextFollowUpAt'])?.toLocal(),
    );
  }
}

class Phone {
  const Phone({required this.e164, this.whatsApp, this.isPrimary = false});

  final String e164;
  final String? whatsApp;
  final bool isPrimary;

  String get whatsAppNumber => whatsApp ?? e164;

  factory Phone.fromJson(Json j) => Phone(
    e164: j['e164'] as String,
    whatsApp: j['whatsAppE164'] as String?,
    isPrimary: j['isPrimary'] as bool? ?? false,
  );
}

class Interest {
  const Interest({required this.spec});

  final MaterialSpec spec;

  String get materialId => spec.materialId;
  String get materialCode => spec.materialCode;
  String? get gradeCode => spec.gradeCode;
  String get label => spec.label;

  factory Interest.fromJson(Json j) => Interest(spec: MaterialSpec.fromJson(j));
}

class LatestPrice {
  const LatestPrice({
    required this.price,
    required this.currency,
    required this.unitCode,
    required this.quoteDate,
    required this.expired,
  });

  final double price;
  final String currency;
  final String unitCode;
  final DateTime quoteDate;
  final bool expired;

  static LatestPrice? fromJson(Object? value) {
    if (value is! Json) return null;
    return LatestPrice(
      price: _num(value['price'])!,
      currency: value['currency'] as String,
      unitCode: value['unitCode'] as String,
      quoteDate: _date(value['quoteDate'])!,
      expired: value['expired'] as bool? ?? false,
    );
  }
}

class SupplierProduct {
  const SupplierProduct({
    required this.id,
    required this.spec,
    this.latestPrice,
  });

  final String id;
  final MaterialSpec spec;
  final LatestPrice? latestPrice;

  String get materialId => spec.materialId;
  String get materialCode => spec.materialCode;
  String? get gradeCode => spec.gradeCode;
  String get label => spec.label;

  factory SupplierProduct.fromJson(Json j) => SupplierProduct(
    id: j['id'] as String,
    spec: MaterialSpec.fromJson(j),
    latestPrice: LatestPrice.fromJson(j['latestPrice']),
  );
}

class PartyDetail {
  const PartyDetail({
    required this.id,
    required this.version,
    required this.name,
    required this.isCustomer,
    required this.isSupplier,
    required this.phones,
    required this.interests,
    required this.products,
    required this.canEdit,
    this.customerActivityId,
    this.supplierActivityId,
    this.representativeId,
    this.representativeName,
    this.email,
    this.notes,
    this.governorateId,
    this.region,
    this.addressLine,
    this.customerSummary,
    this.supplierSummary,
  });

  final String id;
  final int version;
  final String name;
  final bool isCustomer;
  final bool isSupplier;
  final List<Phone> phones;
  final List<Interest> interests;
  final List<SupplierProduct> products;
  final bool canEdit;
  final String? customerActivityId;
  final String? supplierActivityId;
  final String? representativeId;
  final String? representativeName;
  final String? email;
  final String? notes;
  final String? governorateId;
  final String? region;
  final String? addressLine;
  final PartySummary? customerSummary;
  final PartySummary? supplierSummary;

  Phone? get primaryPhone => phones.firstOrNull;

  factory PartyDetail.fromJson(Json j) => PartyDetail(
    id: j['id'] as String,
    version: (j['version'] as num).toInt(),
    name: j['name'] as String,
    isCustomer: j['isCustomer'] as bool,
    isSupplier: j['isSupplier'] as bool,
    phones: _list(j['phones'], Phone.fromJson),
    interests: _list(j['interests'], Interest.fromJson),
    products: _list(j['products'], SupplierProduct.fromJson),
    canEdit: j['canEdit'] as bool? ?? false,
    customerActivityId: j['customerActivityId'] as String?,
    supplierActivityId: j['supplierActivityId'] as String?,
    representativeId: j['representativeId'] as String?,
    representativeName: j['representativeName'] as String?,
    email: j['email'] as String?,
    notes: j['notes'] as String?,
    governorateId: j['governorateId'] as String?,
    region: j['region'] as String?,
    addressLine: j['addressLine'] as String?,
    customerSummary: PartySummary.fromJson(j['customerSummary']),
    supplierSummary: PartySummary.fromJson(j['supplierSummary']),
  );
}

/// الطرف الموجود عند رفض التسجيل بسبب تكرار رقم الهاتف.
class DuplicateParty {
  const DuplicateParty({
    required this.partyId,
    required this.name,
    required this.isCustomer,
    required this.isSupplier,
  });

  final String partyId;
  final String name;
  final bool isCustomer;
  final bool isSupplier;

  static DuplicateParty? fromData(Object? data) {
    if (data is! Map) return null;
    return DuplicateParty(
      partyId: data['partyId'] as String,
      name: data['name'] as String,
      isCustomer: data['isCustomer'] as bool? ?? false,
      isSupplier: data['isSupplier'] as bool? ?? false,
    );
  }
}

enum ContactChannel { call, whatsApp, visit, other }

class InteractionItem {
  const InteractionItem({
    required this.id,
    required this.channel,
    required this.outcomeName,
    required this.occurredAt,
    this.notes,
    this.nextFollowUpAt,
    this.followUpDone = false,
    this.createdByName = '',
  });

  final String id;
  final ContactChannel channel;
  final String outcomeName;
  final DateTime occurredAt;
  final String? notes;
  final DateTime? nextFollowUpAt;
  final bool followUpDone;
  final String createdByName;

  factory InteractionItem.fromJson(Json j) => InteractionItem(
    id: j['id'] as String,
    channel: _enum(ContactChannel.values, j['channel']),
    outcomeName: j['outcomeName'] as String,
    occurredAt: _date(j['occurredAt'])!.toLocal(),
    notes: j['notes'] as String?,
    nextFollowUpAt: _date(j['nextFollowUpAt'])?.toLocal(),
    followUpDone: j['followUpDone'] as bool? ?? false,
    createdByName: j['createdByName'] as String? ?? '',
  );
}

enum OrderStage {
  inquiry,
  quotation,
  confirmed,
  inProgress,
  completed,
  cancelled,
}

/// الانتقالات المسموحة، مطابقة لقواعد السيرفر (السيرفر هو المرجع).
const orderTransitions = <OrderStage, List<OrderStage>>{
  OrderStage.inquiry: [
    OrderStage.quotation,
    OrderStage.confirmed,
    OrderStage.cancelled,
  ],
  OrderStage.quotation: [
    OrderStage.inquiry,
    OrderStage.confirmed,
    OrderStage.cancelled,
  ],
  OrderStage.confirmed: [
    OrderStage.inProgress,
    OrderStage.completed,
    OrderStage.cancelled,
  ],
  OrderStage.inProgress: [OrderStage.completed, OrderStage.cancelled],
  OrderStage.completed: [],
  OrderStage.cancelled: [],
};

class LineItem {
  const LineItem({
    required this.spec,
    required this.quantity,
    required this.unitCode,
    required this.quantityKg,
    this.unitId,
  });

  final MaterialSpec spec;
  final double quantity;
  final String unitCode;
  final String? unitId;
  final double quantityKg;

  String get materialCode => spec.materialCode;
  String? get gradeCode => spec.gradeCode;
  String get label => spec.label;

  factory LineItem.fromJson(Json j) => LineItem(
    spec: MaterialSpec.fromJson(j),
    quantity: _num(j['quantity'])!,
    unitCode: j['unitCode'] as String,
    unitId: j['unitId'] as String?,
    quantityKg: _num(j['quantityKg'])!,
  );
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderDate,
    required this.stage,
    required this.onHold,
    required this.lines,
    required this.totalKg,
    required this.version,
    this.notes,
  });

  final String id;
  final DateTime orderDate;
  final OrderStage stage;
  final bool onHold;
  final List<LineItem> lines;
  final double totalKg;
  final int version;
  final String? notes;

  factory OrderItem.fromJson(Json j) => OrderItem(
    id: j['id'] as String,
    orderDate: _date(j['orderDate'])!,
    stage: _enum(OrderStage.values, j['stage']),
    onHold: j['onHold'] as bool? ?? false,
    lines: _list(j['lines'], LineItem.fromJson),
    totalKg: _num(j['totalKg'])!,
    version: (j['version'] as num).toInt(),
    notes: j['notes'] as String?,
  );
}

enum SupplyStatus { expected, received, cancelled }

class SupplyItem {
  const SupplyItem({
    required this.id,
    required this.supplyDate,
    required this.status,
    required this.lines,
    required this.totalKg,
    required this.version,
    this.notes,
  });

  final String id;
  final DateTime supplyDate;
  final SupplyStatus status;
  final List<LineItem> lines;
  final double totalKg;
  final int version;
  final String? notes;

  factory SupplyItem.fromJson(Json j) => SupplyItem(
    id: j['id'] as String,
    supplyDate: _date(j['supplyDate'])!,
    status: _enum(SupplyStatus.values, j['status']),
    lines: _list(j['lines'], LineItem.fromJson),
    totalKg: _num(j['totalKg'])!,
    version: (j['version'] as num).toInt(),
    notes: j['notes'] as String?,
  );
}
