import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/features/crm/data/crm_repository.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';

/// بيانات اختبار تحاكي القوائم الأساسية في السيرفر (ليست بيانات حقيقية).
const testReference = ReferenceData(
  activityTypes: [
    LookupItem(id: 'act-factory', code: 'factory', nameAr: 'مصنع'),
    LookupItem(
      id: 'act-converter',
      code: 'converter',
      nameAr: 'محول بلاستيك',
      appliesTo: 'customer',
    ),
    LookupItem(id: 'act-trader', code: 'trader', nameAr: 'تاجر'),
    LookupItem(id: 'act-distributor', code: 'distributor', nameAr: 'موزع'),
    LookupItem(
      id: 'act-importer',
      code: 'importer',
      nameAr: 'مستورد',
      appliesTo: 'supplier',
    ),
    LookupItem(id: 'act-other', code: 'other', nameAr: 'أخرى'),
  ],
  contactOutcomes: [
    LookupItem(
      id: 'out-reached',
      code: 'reached',
      nameAr: 'تم التواصل بنجاح',
      semantic: 'reached',
    ),
    LookupItem(
      id: 'out-no-answer',
      code: 'no_answer',
      nameAr: 'لم يتم الرد',
      semantic: 'no_answer',
    ),
    LookupItem(
      id: 'out-pending',
      code: 'pending',
      nameAr: 'في انتظار الرد',
      semantic: 'pending',
    ),
    LookupItem(
      id: 'out-price',
      code: 'price_requested',
      nameAr: 'طلب عرض سعر',
      appliesTo: 'customer',
    ),
    LookupItem(
      id: 'out-agreed',
      code: 'follow_up_agreed',
      nameAr: 'تم الاتفاق على المتابعة',
      appliesTo: 'supplier',
    ),
    LookupItem(id: 'out-other', code: 'other', nameAr: 'أخرى'),
  ],
  governorates: [
    LookupItem(id: 'gov-cairo', code: 'eg-01', nameAr: 'القاهرة'),
    LookupItem(id: 'gov-giza', code: 'eg-02', nameAr: 'الجيزة'),
  ],
  currencies: [LookupItem(id: 'cur-egp', code: 'EGP', nameAr: 'جنيه مصري')],
  units: [
    UnitItem(id: 'unit-kg', code: 'kg', nameAr: 'كجم', factorToKg: 1),
    UnitItem(id: 'unit-ton', code: 'ton', nameAr: 'طن', factorToKg: 1000),
  ],
  materials: [
    MaterialItem(
      id: 'mat-pvc',
      code: 'PVC',
      nameAr: 'بولي فينيل كلوريد',
      grades: [GradeItem(id: 'g-sg5', code: 'SG-5')],
    ),
    MaterialItem(
      id: 'mat-hdpe',
      code: 'HDPE',
      nameAr: 'بولي إيثيلين عالي الكثافة',
      grades: [GradeItem(id: 'g-5502', code: '5502')],
    ),
    MaterialItem(id: 'mat-pp', code: 'PP', nameAr: 'بولي بروبيلين'),
  ],
  representatives: [
    RepresentativeItem(id: 'rep-me', name: 'أحمد محمد'),
    RepresentativeItem(id: 'rep-other', name: 'محمود علي'),
  ],
  myRepresentativeId: 'rep-me',
);

PartyDetail sampleCustomer({bool canEdit = true}) => PartyDetail(
  id: 'party-1',
  version: 7,
  name: 'شركة النور للصناعات البلاستيكية',
  isCustomer: true,
  isSupplier: false,
  phones: const [Phone(e164: '+201001234567', isPrimary: true)],
  interests: const [
    Interest(materialId: 'mat-pvc', materialCode: 'PVC', gradeCode: 'SG-5'),
    Interest(materialId: 'mat-hdpe', materialCode: 'HDPE'),
  ],
  products: const [],
  canEdit: canEdit,
  customerActivityId: 'act-factory',
  representativeId: 'rep-me',
  representativeName: 'أحمد محمد',
  governorateId: 'gov-cairo',
  region: 'المنطقة الصناعية',
  customerSummary: PartySummary(
    status: PartyStatus.active,
    lastDealDate: DateTime(2026, 10, 15),
    lastDealQuantityKg: 3000,
    lastContactAt: DateTime(2026, 10, 24, 11),
  ),
);

PartyDetail sampleSupplier() => PartyDetail(
  id: 'party-2',
  version: 3,
  name: 'شركة الصفوة لمواد البلاستيك',
  isCustomer: false,
  isSupplier: true,
  phones: const [Phone(e164: '+201112223334', isPrimary: true)],
  interests: const [],
  products: [
    SupplierProduct(
      id: 'prod-1',
      materialId: 'mat-pvc',
      materialCode: 'PVC',
      gradeCode: 'SG-5',
      latestPrice: LatestPrice(
        price: 42000,
        currency: 'EGP',
        unitCode: 'ton',
        quoteDate: DateTime(2026, 10, 22),
        expired: false,
      ),
    ),
    const SupplierProduct(
      id: 'prod-2',
      materialId: 'mat-hdpe',
      materialCode: 'HDPE',
    ),
  ],
  canEdit: true,
  supplierActivityId: 'act-factory',
  representativeId: 'rep-me',
  representativeName: 'أحمد محمد',
  governorateId: 'gov-giza',
  region: 'المنطقة الصناعية - 6 أكتوبر',
  supplierSummary: PartySummary(
    status: PartyStatus.active,
    lastDealDate: DateTime(2026, 10, 15),
    lastDealQuantityKg: 5000,
    lastContactAt: DateTime(2026, 10, 24, 11),
  ),
);

/// مستودع في الذاكرة يسجل ما يرسله التطبيق للسيرفر.
class FakeCrmRepository implements CrmRepository {
  FakeCrmRepository({List<PartyDetail>? parties}) {
    for (final p in parties ?? [sampleCustomer(), sampleSupplier()]) {
      this.parties[p.id] = p;
    }
  }

  final parties = <String, PartyDetail>{};
  final created = <NewParty>[];
  final roles = <(String, bool)>[];
  final interactionsSent = <Map<String, Object?>>[];
  final ordersSent = <Map<String, Object?>>[];
  final suppliesSent = <Map<String, Object?>>[];
  final updates = <PartyDetailsUpdate>[];
  final stageChanges = <(String, OrderStage)>[];
  ApiException? createError;
  ApiException? updateError;

  List<OrderItem> orderList = [
    OrderItem(
      id: 'order-1',
      orderDate: DateTime(2026, 10, 15),
      stage: OrderStage.confirmed,
      onHold: false,
      lines: const [
        LineItem(
          materialCode: 'PVC',
          gradeCode: 'SG-5',
          quantity: 3,
          unitCode: 'ton',
          quantityKg: 3000,
        ),
      ],
      totalKg: 3000,
      version: 1,
    ),
  ];

  List<InteractionItem> interactionList = [
    InteractionItem(
      id: 'int-1',
      channel: ContactChannel.call,
      outcomeName: 'تم التواصل بنجاح',
      occurredAt: DateTime(2026, 10, 24, 11, 30),
      notes: 'طلب عرض سعر لخامة PVC',
      createdByName: 'أحمد محمد',
    ),
  ];

  @override
  Future<ReferenceData> reference() async => testReference;

  @override
  Future<PartyDetail> createParty(NewParty party) async {
    final error = createError;
    if (error != null) throw error;
    created.add(party);
    final detail = PartyDetail(
      id: party.id,
      version: 1,
      name: party.name,
      isCustomer: party.isCustomer,
      isSupplier: !party.isCustomer,
      phones: [Phone(e164: '+20${party.phone.substring(1)}')],
      interests: const [],
      products: const [],
      canEdit: true,
      customerActivityId: party.isCustomer ? party.activityId : null,
      supplierActivityId: party.isCustomer ? null : party.activityId,
      representativeName: 'أحمد محمد',
      customerSummary: party.isCustomer
          ? const PartySummary(status: PartyStatus.newParty)
          : null,
      supplierSummary: party.isCustomer
          ? null
          : const PartySummary(status: PartyStatus.newParty),
    );
    parties[party.id] = detail;
    return detail;
  }

  @override
  Future<PartyDetail> party(String id) async =>
      parties[id] ??
      (throw const ApiException('not_found', 'العنصر غير موجود'));

  @override
  Future<PartyDetail> addRole(
    String id, {
    required bool customer,
    String? activityId,
  }) async {
    roles.add((id, customer));
    return parties[id]!;
  }

  @override
  Future<PartyDetail> updateDetails(
    PartyDetail current,
    PartyDetailsUpdate update,
  ) async {
    final error = updateError;
    if (error != null) throw error;
    updates.add(update);
    return current;
  }

  @override
  Future<List<InteractionItem>> interactions(String partyId) async =>
      interactionList;

  @override
  Future<void> addInteraction(
    String partyId, {
    required String id,
    required ContactChannel channel,
    required String outcomeId,
    String? notes,
    DateTime? nextFollowUpAt,
    bool remind = false,
  }) async => interactionsSent.add({
    'partyId': partyId,
    'id': id,
    'channel': channel,
    'outcomeId': outcomeId,
    'notes': notes,
    'nextFollowUpAt': nextFollowUpAt,
    'remind': remind,
  });

  @override
  Future<List<OrderItem>> orders(String customerId) async => orderList;

  @override
  Future<void> createOrder({
    required String id,
    required String customerId,
    required String orderDate,
    required OrderStage stage,
    required List<NewLine> lines,
    String? notes,
  }) async => ordersSent.add({
    'id': id,
    'customerId': customerId,
    'stage': stage,
    'lines': [for (final l in lines) l.toJson()],
    'notes': notes,
  });

  @override
  Future<void> changeOrderStage(OrderItem order, OrderStage stage) async =>
      stageChanges.add((order.id, stage));

  @override
  Future<List<SupplyItem>> supplies(String supplierId) async => [];

  @override
  Future<void> createSupply({
    required String id,
    required String supplierId,
    required String supplyDate,
    required SupplyStatus status,
    required List<NewLine> lines,
    String? notes,
  }) async => suppliesSent.add({
    'id': id,
    'supplierId': supplierId,
    'status': status,
    'lines': [for (final l in lines) l.toJson()],
  });

  @override
  Future<void> changeSupplyStatus(
    SupplyItem supply,
    SupplyStatus status,
  ) async {}
}
