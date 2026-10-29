import 'crm_models.dart';

/// مطابقة مورد لاحتياج عميل مع أسباب واضحة (من قواعد ثابتة على السيرفر).
class SupplierMatch {
  const SupplierMatch({
    required this.supplierId,
    required this.supplierName,
    required this.product,
    required this.need,
    required this.score,
    required this.reasons,
    this.price,
    this.currency,
    this.quoteDate,
    this.priceExpired = false,
  });

  final String supplierId;
  final String supplierName;
  final MaterialSpec product;
  final MaterialSpec need;
  final int score;
  final List<String> reasons;
  final double? price;
  final String? currency;
  final DateTime? quoteDate;
  final bool priceExpired;

  factory SupplierMatch.fromJson(Json j) {
    final price = j['latestPrice'] as Json?;
    return SupplierMatch(
      supplierId: j['supplierId'] as String,
      supplierName: j['supplierName'] as String,
      product: MaterialSpec.fromJson(j['product'] as Json),
      need: MaterialSpec.fromJson(j['need'] as Json),
      score: (j['score'] as num).toInt(),
      reasons: (j['reasons'] as List).cast<String>(),
      price: (price?['price'] as num?)?.toDouble(),
      currency: price?['currency'] as String?,
      quoteDate: price == null
          ? null
          : DateTime.parse(price['quoteDate'] as String),
      priceExpired: price?['expired'] as bool? ?? false,
    );
  }
}

class SupplierMatches {
  const SupplierMatches(this.exact, this.alternatives);

  final List<SupplierMatch> exact;
  final List<SupplierMatch> alternatives;

  factory SupplierMatches.fromJson(Json j) => SupplierMatches(
    [
      for (final m in (j['exact'] as List).cast<Json>())
        SupplierMatch.fromJson(m),
    ],
    [
      for (final m in (j['alternatives'] as List).cast<Json>())
        SupplierMatch.fromJson(m),
    ],
  );
}

class DuplicateGroup {
  const DuplicateGroup(this.partyIds, this.names);

  final List<String> partyIds;
  final List<String> names;
}

class DataQuality {
  const DataQuality({
    required this.missingActivity,
    required this.missingGovernorate,
    required this.withoutLocation,
    required this.withoutContacts,
    required this.duplicates,
  });

  final int missingActivity;
  final int missingGovernorate;
  final int withoutLocation;
  final int withoutContacts;
  final List<DuplicateGroup> duplicates;
}

DataQuality? _quality(Object? value) {
  if (value is! Json) return null;
  return DataQuality(
    missingActivity: (value['missingActivity'] as num).toInt(),
    missingGovernorate: (value['missingGovernorate'] as num).toInt(),
    withoutLocation: (value['withoutLocation'] as num).toInt(),
    withoutContacts: (value['withoutContacts'] as num).toInt(),
    duplicates: [
      for (final d in (value['possibleDuplicates'] as List).cast<Json>())
        DuplicateGroup(
          (d['partyIds'] as List).cast<String>(),
          (d['names'] as List).cast<String>(),
        ),
    ],
  );
}

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// فلاتر لوحة التقارير (الافتراضي: الشهر الحالي).
class ReportFilter {
  const ReportFilter({
    this.from,
    this.to,
    this.representativeId,
    this.materialId,
    this.customerId,
  });

  final DateTime? from;
  final DateTime? to;
  final String? representativeId;
  final String? materialId;
  final String? customerId;

  bool get isEmpty =>
      from == null &&
      to == null &&
      representativeId == null &&
      materialId == null &&
      customerId == null;

  Map<String, String> toQuery() => {
    if (from case final f?) 'from': _day(f),
    if (to case final t?) 'to': _day(t),
    'representativeId': ?representativeId,
    'materialId': ?materialId,
    'customerId': ?customerId,
  };

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ReportFilter &&
      other.from == from &&
      other.to == to &&
      other.representativeId == representativeId &&
      other.materialId == materialId &&
      other.customerId == customerId;

  @override
  int get hashCode =>
      Object.hash(from, to, representativeId, materialId, customerId);
}

class ReportKpis {
  const ReportKpis({
    this.completedOrders = 0,
    this.completedKg = 0,
    this.openOrders = 0,
    this.openKg = 0,
    this.cancelledOrders = 0,
    this.cancelledKg = 0,
    this.activeCustomers = 0,
    this.newCustomers = 0,
    this.contacts = 0,
    this.conversionRate,
    this.valueAvailable = false,
  });

  final int completedOrders;
  final double completedKg;
  final int openOrders;
  final double openKg;
  final int cancelledOrders;
  final double cancelledKg;
  final int activeCustomers;
  final int newCustomers;
  final int contacts;

  /// المكتمل ÷ (المكتمل + الملغى)؛ null إن لم تنتهِ طلبات في الفترة.
  final double? conversionRate;

  /// قيمة المبيعات: غير متاحة لأن الطلبات لا تحمل أسعارًا.
  final bool valueAvailable;

  factory ReportKpis.fromJson(Json j) => ReportKpis(
    completedOrders: _i(j['completedOrders']),
    completedKg: _d(j['completedKg']),
    openOrders: _i(j['openOrders']),
    openKg: _d(j['openKg']),
    cancelledOrders: _i(j['cancelledOrders']),
    cancelledKg: _d(j['cancelledKg']),
    activeCustomers: _i(j['activeCustomers']),
    newCustomers: _i(j['newCustomers']),
    contacts: _i(j['contacts']),
    conversionRate: (j['conversionRate'] as num?)?.toDouble(),
    valueAvailable: j['valueAvailable'] as bool? ?? false,
  );
}

class RankRow {
  const RankRow(this.label, this.orders, this.kg, {this.id, this.extra});

  final String? id;
  final String label;
  final int orders;
  final double kg;
  final String? extra;

  factory RankRow.fromJson(Json j) => RankRow(
    j['label'] as String,
    _i(j['orders']),
    _d(j['kg']),
    id: j['id'] as String?,
    extra: j['extra'] as String?,
  );
}

/// قيمة باسم (مرحلة طلب أو شهر) لعدد وكمية.
class ReportPoint {
  const ReportPoint(this.label, this.orders, this.kg);

  final String label;
  final int orders;
  final double kg;
}

class DemandRow {
  const DemandRow(
    this.material,
    this.demandCustomers,
    this.soldKg,
    this.suppliers,
  );

  final String material;
  final int demandCustomers;
  final double soldKg;

  /// null لمن لا يطّلع على الموردين.
  final int? suppliers;
}

class ReportDashboard {
  const ReportDashboard({
    required this.from,
    required this.to,
    this.kpis = const ReportKpis(),
    this.pipeline = const [],
    this.materials = const [],
    this.grades = const [],
    this.customers = const [],
    this.representatives = const [],
    this.suppliers,
    this.trend = const [],
    this.demand = const [],
    this.activity = const (0, 0, 0, 0),
    this.dormant = const [],
    this.overdue = 0,
    this.today = 0,
    this.incomplete = 0,
    this.quality,
  });

  final DateTime from;
  final DateTime to;
  final ReportKpis kpis;
  final List<ReportPoint> pipeline;
  final List<RankRow> materials;
  final List<RankRow> grades;
  final List<RankRow> customers;
  final List<RankRow> representatives;

  /// null لمن لا يطّلع على الموردين.
  final List<RankRow>? suppliers;
  final List<ReportPoint> trend;
  final List<DemandRow> demand;

  /// (جديد، نشط، يحتاج متابعة، متوقف).
  final (int, int, int, int) activity;
  final List<RankRow> dormant;
  final int overdue;
  final int today;
  final int incomplete;
  final DataQuality? quality;

  factory ReportDashboard.fromJson(Json j) {
    List<RankRow> rank(Object? v) => [
      for (final r in (v as List? ?? const []).cast<Json>())
        RankRow.fromJson(r),
    ];
    final a = j['activity'] as Json;
    return ReportDashboard(
      from: DateTime.parse(j['from'] as String),
      to: DateTime.parse(j['to'] as String),
      kpis: ReportKpis.fromJson(j['kpis'] as Json),
      pipeline: [
        for (final p in (j['pipeline'] as List).cast<Json>())
          ReportPoint(p['stage'] as String, _i(p['orders']), _d(p['kg'])),
      ],
      materials: rank(j['materials']),
      grades: rank(j['grades']),
      customers: rank(j['customers']),
      representatives: rank(j['representatives']),
      suppliers: j['suppliers'] == null ? null : rank(j['suppliers']),
      trend: [
        for (final t in (j['trend'] as List).cast<Json>())
          ReportPoint(t['month'] as String, _i(t['orders']), _d(t['kg'])),
      ],
      demand: [
        for (final d in (j['demand'] as List).cast<Json>())
          DemandRow(
            d['material'] as String,
            _i(d['demandCustomers']),
            _d(d['soldKg']),
            (d['suppliers'] as num?)?.toInt(),
          ),
      ],
      activity: (
        _i(a['new']),
        _i(a['active']),
        _i(a['needsFollowUp']),
        _i(a['stopped']),
      ),
      dormant: rank(j['dormant']),
      overdue: _i(j['overdueFollowUps']),
      today: _i(j['todayFollowUps']),
      incomplete: _i(j['incompleteRecords']),
      quality: _quality(j['quality']),
    );
  }
}
