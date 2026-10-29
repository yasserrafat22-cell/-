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

class RepActivity {
  const RepActivity(
    this.name,
    this.newCustomers,
    this.contacts,
    this.orders,
    this.ordersKg,
  );

  final String name;
  final int newCustomers;
  final int contacts;
  final int orders;
  final double ordersKg;
}

class MaterialDemand {
  const MaterialDemand(this.spec, this.customers, this.suppliers);

  final String spec;
  final int customers;

  /// null لمن لا يطّلع على الموردين.
  final int? suppliers;
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

class ReportSummary {
  const ReportSummary({
    required this.overdue,
    required this.today,
    required this.representatives,
    required this.materials,
    this.quality,
  });

  final int overdue;
  final int today;
  final List<RepActivity> representatives;
  final List<MaterialDemand> materials;
  final DataQuality? quality;

  factory ReportSummary.fromJson(Json j) {
    final q = j['quality'] as Json?;
    return ReportSummary(
      overdue: (j['overdueFollowUps'] as num).toInt(),
      today: (j['todayFollowUps'] as num).toInt(),
      representatives: [
        for (final r in (j['representatives'] as List).cast<Json>())
          RepActivity(
            r['representative'] as String,
            (r['newCustomers'] as num).toInt(),
            (r['contacts'] as num).toInt(),
            (r['orders'] as num).toInt(),
            (r['ordersKg'] as num).toDouble(),
          ),
      ],
      materials: [
        for (final m in (j['materials'] as List).cast<Json>())
          MaterialDemand(
            m['spec'] as String,
            (m['customers'] as num).toInt(),
            (m['suppliers'] as num?)?.toInt(),
          ),
      ],
      quality: q == null
          ? null
          : DataQuality(
              missingActivity: (q['missingActivity'] as num).toInt(),
              missingGovernorate: (q['missingGovernorate'] as num).toInt(),
              withoutLocation: (q['withoutLocation'] as num).toInt(),
              withoutContacts: (q['withoutContacts'] as num).toInt(),
              duplicates: [
                for (final d in (q['possibleDuplicates'] as List).cast<Json>())
                  DuplicateGroup(
                    (d['partyIds'] as List).cast<String>(),
                    (d['names'] as List).cast<String>(),
                  ),
              ],
            ),
    );
  }
}
