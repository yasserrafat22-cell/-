import 'dart:convert';
import 'dart:typed_data';

import 'package:qadisiyah/core/device/device_location.dart';
import 'package:qadisiyah/core/device/document_services.dart';
import 'package:qadisiyah/core/device/file_services.dart';
import 'package:qadisiyah/core/device/share_service.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/core/notifications/reminder_scheduler.dart';
import 'package:qadisiyah/core/offline/offline_store.dart';
import 'package:qadisiyah/features/crm/data/crm_repository.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/domain/quick_entry.dart';

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
      // Grade سابق بلا شركة مصنّعة.
      grades: [GradeItem(id: 'g-sg5', code: 'SG-5')],
    ),
    MaterialItem(
      id: 'mat-hdpe',
      code: 'HDPE',
      nameAr: 'بولي إيثيلين عالي الكثافة',
      grades: [GradeItem(id: 'g-5502', code: '5502', manufacturerId: 'man-a')],
    ),
    MaterialItem(
      id: 'mat-pp',
      code: 'PP',
      nameAr: 'بولي بروبيلين',
      grades: [
        GradeItem(
          id: 'g-pp500',
          code: 'PP500',
          manufacturerId: 'man-a',
          originIds: ['c-sa'],
        ),
        GradeItem(id: 'g-129h', code: '129H', manufacturerId: 'man-b'),
        GradeItem(
          id: 'g-m030',
          code: 'MARLEX 030',
          manufacturerId: 'man-c',
          verified: false,
        ),
      ],
    ),
  ],
  manufacturers: [
    ManufacturerItem(id: 'man-a', name: 'مصنع تجريبي أ'),
    ManufacturerItem(id: 'man-b', name: 'مصنع تجريبي ب'),
    ManufacturerItem(id: 'man-c', name: 'مصنع تجريبي ج'),
  ],
  countries: [
    LookupItem(id: 'c-sa', code: 'SA', nameAr: 'السعودية'),
    LookupItem(id: 'c-in', code: 'IN', nameAr: 'الهند'),
  ],
  representatives: [
    RepresentativeItem(id: 'rep-me', name: 'أحمد محمد'),
    RepresentativeItem(id: 'rep-other', name: 'محمود علي'),
  ],
  myRepresentativeId: 'rep-me',
  customerActivities: [
    ActivityItem(id: 'ca-injection', name: 'حقن البلاستيك'),
    ActivityItem(id: 'ca-blowing', name: 'نفخ البلاستيك'),
    ActivityItem(id: 'ca-film', name: 'سحب الأفلام'),
    ActivityItem(id: 'ca-other', name: 'أخرى'),
  ],
);

PartyDetail sampleCustomer({
  bool canEdit = true,
  bool? canAdd,
  int number = 0,
}) => PartyDetail(
  number: number,
  id: 'party-1',
  version: 7,
  name: 'شركة النور للصناعات البلاستيكية',
  isCustomer: true,
  isSupplier: false,
  phones: const [Phone(e164: '+201001234567', isPrimary: true)],
  interests: const [
    Interest(
      spec: MaterialSpec(
        materialId: 'mat-pp',
        materialCode: 'PP',
        gradeId: 'g-pp500',
        gradeCode: 'PP500',
        manufacturerId: 'man-a',
        manufacturerName: 'مصنع تجريبي أ',
        originId: 'c-sa',
        originName: 'السعودية',
        precision: SpecPrecision.exact,
      ),
    ),
    Interest(
      spec: MaterialSpec(
        materialId: 'mat-hdpe',
        materialCode: 'HDPE',
        precision: SpecPrecision.open,
      ),
    ),
  ],
  products: const [],
  canEdit: canEdit,
  canAdd: canAdd,
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

PartyDetail sampleSupplier({bool isFavorite = false}) => PartyDetail(
  isFavorite: isFavorite,
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
      spec: const MaterialSpec(
        materialId: 'mat-pvc',
        materialCode: 'PVC',
        gradeId: 'g-sg5',
        gradeCode: 'SG-5',
        precision: SpecPrecision.unknownManufacturer,
      ),
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
      spec: MaterialSpec(
        materialId: 'mat-hdpe',
        materialCode: 'HDPE',
        gradeId: 'g-5502',
        gradeCode: '5502',
        manufacturerId: 'man-a',
        manufacturerName: 'مصنع تجريبي أ',
        precision: SpecPrecision.exact,
      ),
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
  final createAttempts = <NewParty>[];
  final roles = <(String, bool)>[];
  final interactionsSent = <Map<String, Object?>>[];
  final ordersSent = <Map<String, Object?>>[];
  final suppliesSent = <Map<String, Object?>>[];
  final updates = <PartyDetailsUpdate>[];
  final stageChanges = <(String, OrderStage)>[];
  ApiException? createError;
  ApiException? updateError;

  /// السيرفر حفظ السجل لكنه لا يظهر لصاحبه (مورد أضافه مندوب).
  bool createHidden = false;

  /// حُفظ على الجهاز دون اتصال (نسخة 0) بانتظار المزامنة.
  bool createOffline = false;

  /// الخطأ يحدث في أول محاولة فقط (مثل سجل مشابه ثم التأكيد).
  bool createErrorOnce = false;
  final deleted = <String>[];
  final restored = <String>[];

  List<OrderItem> orderList = [
    OrderItem(
      id: 'order-1',
      orderDate: DateTime(2026, 10, 15),
      stage: OrderStage.confirmed,
      onHold: false,
      lines: const [
        LineItem(
          spec: MaterialSpec(
            materialId: 'mat-pvc',
            materialCode: 'PVC',
            gradeId: 'g-sg5',
            gradeCode: 'SG-5',
            precision: SpecPrecision.unknownManufacturer,
          ),
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
  Future<ReferenceData> reference() async {
    final r = testReference;
    if (gradesCreated.isEmpty &&
        materialsCreated.isEmpty &&
        manufacturersCreated.isEmpty &&
        activitiesCreated.isEmpty) {
      return r;
    }
    // ما أُضيف من الكتالوج يظهر في القوائم بعد التحديث، كما في السيرفر.
    return ReferenceData(
      activityTypes: r.activityTypes,
      contactOutcomes: r.contactOutcomes,
      governorates: r.governorates,
      currencies: r.currencies,
      units: r.units,
      representatives: r.representatives,
      myRepresentativeId: r.myRepresentativeId,
      manufacturers: [...r.manufacturers, ...manufacturersCreated],
      countries: r.countries,
      customerActivities: [...r.customerActivities, ...activitiesCreated],
      materials: [
        for (final m in r.materials)
          MaterialItem(
            id: m.id,
            code: m.code,
            nameAr: m.nameAr,
            grades: [
              ...m.grades,
              for (final (i, g) in gradesCreated.indexed)
                if (g['materialId'] == m.id)
                  GradeItem(
                    id: i == 0 ? 'g-new' : 'g-new-$i',
                    code: g['code']! as String,
                    manufacturerId: g['manufacturerId'] as String?,
                  ),
            ],
          ),
        for (final code in materialsCreated)
          MaterialItem(id: 'mat-$code', code: code, nameAr: code),
      ],
    );
  }

  @override
  Future<PartyDetail?> createParty(NewParty party) async {
    final error = createError;
    createAttempts.add(party);
    if (error != null) {
      if (createErrorOnce) createError = null;
      throw error;
    }
    created.add(party);
    if (createHidden) return null;
    final detail = PartyDetail(
      id: party.id,
      version: createOffline ? 0 : 1,
      name: party.name,
      isCustomer: party.isCustomer,
      isSupplier: !party.isCustomer,
      phones: [Phone(e164: '+20${party.phone.substring(1)}')],
      interests: const [],
      products: const [],
      canEdit: true,
      customerActivityId: party.isCustomer ? party.activityId : null,
      customerActivityIds: party.isCustomer ? party.activityIds : const [],
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
    String? locationId,
  }) async => ordersSent.add({
    'id': id,
    'customerId': customerId,
    'stage': stage,
    'lines': [for (final l in lines) l.toJson()],
    'notes': notes,
    'locationId': locationId,
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
    String? locationId,
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

  final activitiesCreated = <ActivityItem>[];

  /// مثل السيرفر: نفس الاسم بعد التطبيع يعيد الموجود.
  @override
  Future<ActivityItem> createCustomerActivity(String name) async {
    String norm(String s) => s
        .trim()
        .replaceAll(RegExp('[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ');
    final all = [...testReference.customerActivities, ...activitiesCreated];
    final existing = all.where((a) => norm(a.name) == norm(name)).firstOrNull;
    if (existing != null) return existing;
    final added = ActivityItem(
      id: 'ca-new-${activitiesCreated.length}',
      name: name.trim(),
    );
    activitiesCreated.add(added);
    return added;
  }

  final interestsSet = <List<SpecChoice>>[];
  final productsAdded = <SpecChoice>[];
  final gradesCreated = <Map<String, Object?>>[];
  final verified = <String>[];
  ApiException? createGradeError;

  @override
  Future<PartyDetail> setInterests(
    PartyDetail current,
    List<SpecChoice> specs,
  ) async {
    interestsSet.add(specs);
    return current;
  }

  @override
  Future<void> addProduct(String partyId, SpecChoice spec) async =>
      productsAdded.add(spec);

  final interestsAdded = <SpecChoice>[];

  @override
  Future<void> addInterest(String partyId, SpecChoice spec) async =>
      interestsAdded.add(spec);

  @override
  Future<void> deleteParty(String id) async => deleted.add(id);

  final assigned = <(String, String)>[];

  @override
  Future<void> assignParty(String id, String representativeId) async =>
      assigned.add((id, representativeId));

  /// طابور المزامنة في الاختبارات.
  final pendingList = <PendingOp>[];
  SyncResult nextSync = const SyncResult(0, 0);
  int syncCalls = 0;

  @override
  Future<List<PendingOp>> pendingOps() async => List.of(pendingList);

  List<FollowUpItem> followUpList = [];
  SupplierMatches matches = const SupplierMatches([], []);
  ReportDashboard report = ReportDashboard(
    from: DateTime(2026, 10),
    to: DateTime(2026, 10, 28),
  );
  final reportFilters = <ReportFilter>[];
  final reportExcels = <List<String>>[];

  @override
  Future<List<FollowUpItem>> followUps({int days = 7}) async => followUpList;

  @override
  Future<SupplierMatches> supplierMatches(String customerId) async => matches;

  CustomerMatches customerMatchList = const CustomerMatches([], []);
  final customerMatchQueries = <String>[];

  @override
  Future<CustomerMatches> customerMatches(String supplierId) async {
    customerMatchQueries.add(supplierId);
    return customerMatchList;
  }

  @override
  Future<ReportDashboard> reportDashboard(ReportFilter filter) async {
    reportFilters.add(filter);
    return report;
  }

  @override
  Future<Uint8List> reportExcel(
    ReportFilter filter,
    List<String> sections,
  ) async {
    reportExcels.add(sections);
    return Uint8List.fromList(const [80, 75]);
  }

  SearchResults searchResults = const SearchResults();
  final searches = <SearchQuery>[];

  /// صلاحيات المشاركة كما يفرضها السيرفر (المندوب: بطاقة واحدة فقط).
  bool bulkShareAllowed = true;
  final shareRequests = <(String, int)>[];
  final searchExports = <List<String>?>[];

  @override
  Future<SearchResults> search(SearchQuery query) async {
    searches.add(query);
    return searchResults;
  }

  @override
  Future<void> authorizeShare(String scope, int count, {String? query}) async {
    if (!(scope == 'card' && count == 1) && !bulkShareAllowed) {
      throw const ApiException(
        'forbidden',
        'مشاركة أو تصدير أكثر من بطاقة غير مسموح لهذا المستخدم',
        status: 403,
      );
    }
    shareRequests.add((scope, count));
  }

  @override
  Future<Uint8List> exportSearch(SearchQuery query, {List<String>? ids}) async {
    searchExports.add(ids);
    return Uint8List.fromList(const [80, 75]);
  }

  /// ما يرد به السيرفر الوهمي للمعاينة/التنفيذ (committed يُضبط حسب العملية).
  Map<String, dynamic> importJson = {
    'kind': 'parties',
    'committed': false,
    'headers': ['الاسم', 'الهاتف', 'Grade', 'النوع'],
    'mapping': {'name': 0, 'phone': 1, 'grade': 2, 'type': 3},
    'counts': {
      'new': 1,
      'existing': 0,
      'duplicate': 0,
      'invalid': 1,
      'review': 1,
    },
    'rows': [
      {
        'row': 2,
        'status': 'new',
        'values': {
          'name': 'شركة النور',
          'phone': '01001234567',
          'grade': '',
          'type': '',
        },
        'notes': ['غير مصنف — يحتاج تحديد النوع'],
      },
      {
        'row': 3,
        'status': 'invalid',
        'values': {'name': 'س', 'phone': '', 'grade': '', 'type': ''},
        'notes': ['يلزم حقلان على الأقل'],
      },
      {
        'row': 4,
        'status': 'review',
        'values': {
          'name': 'شركة ب',
          'phone': '12',
          'grade': '',
          'type': 'مورد',
        },
        'notes': ['رقم الهاتف غير صحيح: 12'],
      },
    ],
    'previousImportAt': null,
  };
  final importCalls = <(String, Map<String, int>?, String?)>[];
  final completions = <(String, String?, String?, bool, bool)>[];

  @override
  Future<ImportResult> importPreview(
    String kind,
    Uint8List file, {
    Map<String, int>? mapping,
  }) async {
    importCalls.add(('preview', mapping, null));
    return ImportResult.fromJson({...importJson, 'kind': kind});
  }

  @override
  Future<ImportResult> importCommit(
    String kind,
    String importId,
    Uint8List file, {
    Map<String, int>? mapping,
  }) async {
    importCalls.add(('commit', mapping, importId));
    return ImportResult.fromJson({
      ...importJson,
      'kind': kind,
      'committed': true,
    });
  }

  @override
  Future<Uint8List> importTemplate(String kind) async {
    exported.add('template.$kind');
    return Uint8List.fromList(const [80, 75]);
  }

  @override
  Future<Uint8List> exportCatalog() async {
    exported.add('catalog');
    return Uint8List.fromList(const [80, 75]);
  }

  // ---------- الإدخال السريع ----------
  final quickValidations = <(String, String, List<EntryRow>)>[];
  final quickCommits = <(String, String, String, List<EntryRow>)>[];
  final _quickResults = <String, BatchResult>{};
  bool quickOffline = false;
  List<ExcelSheetData> excelSheets = const [];
  ApiException? excelError;
  final pendingStore = <PendingEntry>[];
  final pendingUpdates = <(String, EntryRow)>[];
  final pendingCompletes = <(String, bool)>[];
  final pendingMerges = <(String, bool)>[];
  final pendingDiscards = <String>[];

  /// صفوف محمية من الاستبعاد وسبب كل منها (كما يحكم السيرفر).
  final protectedPending = <String, String>{};

  /// طلبات الإكمال/الدمج التي أُرسل معها تأكيد المراجعة.
  final reviewAcks = <String>[];

  /// يرفض تنفيذ «حذف الكل» مرة واحدة كأن القائمة تغيرت بعد المعاينة.
  bool snapshotChangeOnce = false;
  final discardAllCalls = <String?>[];

  /// عمليات «الإدخال السريع» على الجهاز بانتظار المزامنة (للعرض).
  int localQuickOpsCount = 0;
  bool completeSimilarOnce = false;
  bool mergeNeedsRole = false;
  List<BatchSummary> batchList = const [];
  final undone = <String>[];
  final exportCalls = <(String, String?, String?)>[];
  ExportData exportResult = const ExportData(0, 0, []);

  Future<List<RowResult>> _quickRows(
    String audience,
    List<EntryRow> rows,
  ) async {
    final refs = await reference();
    final phones = {
      for (final p in parties.values)
        for (final ph in p.phones) normalizeMobile(ph.e164): p,
    };
    final seen = <String>{};
    return [
      for (final r in rows)
        () {
          final c = checkRow(r, audience, refs);
          final phone = normalizeMobile(r.phone ?? '');
          final owner = phones[phone];
          final dupInBatch = phone.length == 11 && !seen.add(phone);
          // نفس حكم السيرفر: العوائق ← ناقص، المكرر، ثم الـ Grade الملتبس ← مراجعة.
          final status = !c.complete
              ? 'pending'
              : owner != null || dupInBatch
              ? 'duplicate'
              : c.status(acknowledged: r.reviewAcknowledged);
          return RowResult(
            id: r.id,
            row: r.row,
            status: status,
            issues: c.issues,
            kind: c.kind,
            materialId: c.material?.id,
            gradeId: c.grade?.id,
            materialCode: c.material?.code,
            gradeLabel: c.grade?.code,
            warnings: c.warnings,
            unverifiedGrade: c.unverifiedGrade,
            needsReview: c.needsReview && !r.reviewAcknowledged,
            duplicateOfId: owner?.id,
            duplicateName:
                owner?.name ?? (dupInBatch ? 'صف آخر في الدفعة' : null),
          );
        }(),
    ];
  }

  @override
  Future<BatchResult> quickValidate(
    String id,
    String method,
    String audience,
    List<EntryRow> rows, {
    String? fileName,
  }) async {
    quickValidations.add((id, audience, rows));
    final r = await _quickRows(audience, rows);
    return BatchResult(
      batchId: id,
      committed: false,
      total: r.length,
      created: 0,
      pending: r.where((x) => x.status == 'pending').length,
      duplicate: r.where((x) => x.status == 'duplicate').length,
      failed: 0,
      rows: r,
    );
  }

  @override
  Future<BatchResult?> quickCommit(
    String id,
    String method,
    String audience,
    List<EntryRow> rows, {
    String? fileName,
  }) async {
    quickCommits.add((id, method, audience, rows));
    if (quickOffline) return null;
    if (_quickResults[id] case final done?) return done;
    final r = [
      for (final x in await _quickRows(audience, rows))
        x.status == 'ready'
            ? RowResult(
                id: x.id,
                row: x.row,
                status: 'completed',
                issues: const [],
                kind: x.kind,
                materialCode: x.materialCode,
                gradeLabel: x.gradeLabel,
                partyId: 'party-${x.id}',
              )
            : x,
    ];
    for (final x in r.where((x) => x.status != 'completed')) {
      final row = rows.firstWhere((e) => e.id == x.id);
      pendingStore.add(
        PendingEntry(
          id: x.id,
          batchId: id,
          method: method,
          row: x.row,
          kind: x.kind ?? row.kind,
          name: row.name,
          phone: row.phone,
          material: row.material,
          grade: row.grade,
          status: x.status,
          issues: x.issues,
          duplicateOfId: x.duplicateOfId,
          duplicateName: x.duplicateName,
          createdAt: DateTime(2026, 11, 1),
        ),
      );
    }
    return _quickResults[id] = BatchResult(
      batchId: id,
      committed: true,
      total: r.length,
      created: r.where((x) => x.status == 'completed').length,
      pending: r.where((x) => x.status == 'pending').length,
      duplicate: r.where((x) => x.status == 'duplicate').length,
      failed: 0,
      rows: r,
    );
  }

  @override
  Future<List<ExcelSheetData>> quickReadExcel(
    String path,
    String fileName,
  ) async {
    if (excelError case final e?) throw e;
    return excelSheets;
  }

  @override
  Future<PendingPage> pendingEntries({
    String? query,
    String? kind,
    String? issue,
    String? batchId,
    int skip = 0,
    int take = 50,
  }) async {
    final q = (query ?? '').trim();
    final all = [
      for (final e in pendingStore)
        if ((kind == null || e.kind == kind) &&
            (issue == null || e.issues.contains(issue)) &&
            (q.isEmpty ||
                (e.name ?? '').contains(q) ||
                (e.phone ?? '').contains(q)))
          e,
    ];
    return PendingPage(all.skip(skip).take(take).toList(), all.length);
  }

  @override
  Future<PendingEntry> updatePending(String id, EntryRow row) async {
    pendingUpdates.add((id, row));
    final i = pendingStore.indexWhere((e) => e.id == id);
    final old = pendingStore[i];
    final refs = await reference();
    final c = checkRow(row, old.kind ?? 'mixed', refs);
    return pendingStore[i] = PendingEntry(
      id: id,
      batchId: old.batchId,
      method: old.method,
      row: old.row,
      kind: row.kind ?? old.kind,
      name: row.name,
      phone: row.phone,
      material: row.material,
      grade: row.grade,
      materialId: row.materialId,
      gradeId: row.gradeId,
      status: old.status,
      issues: c.issues,
      duplicateOfId: old.duplicateOfId,
      duplicateName: old.duplicateName,
      createdAt: old.createdAt,
    );
  }

  @override
  Future<String> completePending(
    String id, {
    bool confirmSimilar = false,
    bool acknowledgeReview = false,
  }) async {
    pendingCompletes.add((id, confirmSimilar));
    if (acknowledgeReview) reviewAcks.add(id);
    final entry = pendingStore.where((e) => e.id == id).firstOrNull;
    if (entry != null &&
        entry.needsReview &&
        !entry.reviewAcknowledged &&
        !acknowledgeReview) {
      throw const ApiException(
        'quick.review_required',
        'الـ Grade يحتاج مراجعة: سيُحفظ كنص غير موثق. أكد للمتابعة',
      );
    }
    if (completeSimilarOnce && !confirmSimilar) {
      completeSimilarOnce = false;
      throw const ApiException('party.similar', 'يوجد اسم مشابه: شركة تجريبية');
    }
    pendingStore.removeWhere((e) => e.id == id);
    return 'party-$id';
  }

  @override
  Future<String> mergePending(
    String id, {
    bool addRole = false,
    bool acknowledgeReview = false,
  }) async {
    pendingMerges.add((id, addRole));
    if (acknowledgeReview) reviewAcks.add(id);
    if (mergeNeedsRole && !addRole) {
      throw const ApiException(
        'quick.role_needed',
        'السجل مسجل كعميل. أكد إضافته كمورد',
      );
    }
    final e = pendingStore.firstWhere((e) => e.id == id);
    pendingStore.remove(e);
    return e.duplicateOfId!;
  }

  @override
  Future<DiscardOutcome> discardPending(String id) async {
    if (protectedPending[id] case final String reason) {
      throw ApiException('quick.protected', discardReasonLabel(reason));
    }
    pendingDiscards.add(id);
    pendingStore.removeWhere((e) => e.id == id);
    return DiscardOutcome(id: id, outcome: 'discarded');
  }

  @override
  Future<DiscardManyResult> discardPendingMany(List<String> ids) async {
    final skipped = <DiscardOutcome>[];
    var discarded = 0;
    for (final id in ids) {
      if (protectedPending[id] case final String reason) {
        skipped.add(DiscardOutcome(id: id, outcome: 'skipped', reason: reason));
      } else if (pendingStore.any((e) => e.id == id)) {
        pendingDiscards.add(id);
        pendingStore.removeWhere((e) => e.id == id);
        discarded++;
      } else {
        skipped.add(
          DiscardOutcome(id: id, outcome: 'skipped', reason: 'not_found'),
        );
      }
    }
    return DiscardManyResult(
      discarded: discarded,
      alreadyDiscarded: 0,
      skipped: skipped,
      remainingPending: pendingStore.length,
    );
  }

  @override
  Future<DiscardAllResult> discardAllPending({
    String? token,
    String? kind,
  }) async {
    discardAllCalls.add(token);
    final scope = [
      for (final e in pendingStore)
        if (kind == null || e.kind == kind) e,
    ];
    final eligible = [
      for (final e in scope)
        if (!protectedPending.containsKey(e.id)) e,
    ];
    final protectedItems = [
      for (final e in scope)
        if (protectedPending[e.id] case final String reason)
          DiscardOutcome(id: e.id, outcome: 'skipped', reason: reason),
    ];
    final byReason = <String, int>{};
    for (final p in protectedItems) {
      byReason[p.reason!] = (byReason[p.reason!] ?? 0) + 1;
    }
    final current = eligible.map((e) => e.id).join(',');
    if (token != null) {
      if (snapshotChangeOnce || token != current) {
        snapshotChangeOnce = false;
        throw const ApiException(
          'quick.snapshot_changed',
          'تغيرت القائمة منذ المعاينة. راجع الأعداد من جديد',
        );
      }
      for (final e in eligible) {
        pendingDiscards.add(e.id);
      }
      pendingStore.removeWhere(eligible.contains);
    }
    return DiscardAllResult(
      committed: token != null,
      eligible: eligible.length,
      protectedCount: protectedItems.length,
      protectedByReason: byReason,
      protectedItems: protectedItems,
      token: current,
      remainingPending: token == null
          ? pendingStore.length - eligible.length
          : pendingStore.length,
    );
  }

  @override
  Future<int> localQuickOps() async => localQuickOpsCount;

  @override
  Future<Uint8List> pendingExcel({String? kind, String? issue}) async {
    exported.add('pending');
    return Uint8List.fromList(const [80, 75]);
  }

  @override
  Future<List<BatchSummary>> quickBatches() async => batchList;

  @override
  Future<Json> undoBatch(String id) async {
    undone.add(id);
    return {
      'reversed': 1,
      'discarded': 1,
      'blocked': [
        {
          'partyId': 'p',
          'name': 'شركة معدلة',
          'reason': 'عُدّلت بعد الاستيراد',
        },
      ],
      'status': 'partially_undone',
    };
  }

  @override
  Future<ExportData> exportData(
    String audience, {
    String? materialId,
    String? gradeId,
  }) async {
    exportCalls.add((audience, materialId, gradeId));
    return exportResult;
  }

  @override
  Future<Uint8List> exportExcel(
    String audience, {
    String? materialId,
    String? gradeId,
  }) async {
    exported.add('export.$audience');
    return Uint8List.fromList(const [80, 75]);
  }

  @override
  Future<PartyDetail> completeParty(
    String id, {
    String? name,
    String? phone,
    bool isCustomer = false,
    bool isSupplier = false,
  }) async {
    completions.add((id, name, phone, isCustomer, isSupplier));
    return parties[id]!;
  }

  final backupPasswords = <String>[];
  final exported = <String>[];

  @override
  Future<Uint8List> fullBackup(String password) async {
    backupPasswords.add(password);
    return Uint8List.fromList(utf8.encode('QBK1'));
  }

  @override
  Future<Uint8List> exportParties(String role) async {
    exported.add(role);
    return Uint8List.fromList(const [80, 75]);
  }

  @override
  Future<Uint8List> deviceBackup(String password) async =>
      Uint8List.fromList(utf8.encode('QDV1'));

  @override
  Future<int> importDeviceBackup(Uint8List bytes, String password) async => 0;

  @override
  Future<SyncResult> syncPending() async {
    syncCalls++;
    // يُرسل أول [nextSync.sent] من العمليات المعلقة فقط.
    final sent = pendingList
        .where((o) => o.status == PendingStatus.pending)
        .take(nextSync.sent)
        .toList();
    pendingList.removeWhere(sent.contains);
    return nextSync;
  }

  @override
  Future<void> retryOp(PendingOp op, {bool confirmSimilar = false}) async =>
      op.status = PendingStatus.pending;

  final materialsCreated = <String>[];

  @override
  Future<MaterialItem> createMaterialType(
    String code, {
    String? nameAr,
    String? nameEn,
  }) async {
    materialsCreated.add(code);
    return MaterialItem(id: 'mat-$code', code: code, nameAr: nameAr ?? code);
  }

  @override
  Future<void> discardOp(PendingOp op) async => pendingList.remove(op);

  final contactList = <String, List<PartyContact>>{};
  final contactsAdded = <PartyContact>[];
  final contactsUpdated = <PartyContact>[];
  final contactsRemoved = <String>[];

  @override
  Future<List<PartyContact>> contacts(String partyId) async =>
      contactList[partyId] ?? const [];

  @override
  Future<void> addContact(String partyId, PartyContact contact) async {
    contactsAdded.add(contact);
    contactList.putIfAbsent(partyId, () => []).add(contact);
  }

  @override
  Future<void> updateContact(PartyContact contact) async =>
      contactsUpdated.add(contact);

  @override
  Future<void> removeContact(String id) async => contactsRemoved.add(id);

  final gradeFilesUploaded = <(String, String, String)>[];
  final gradeFilesRemoved = <String>[];

  @override
  Future<void> uploadGradeFile({
    required String gradeId,
    required String id,
    required String kind,
    required String filePath,
    required String fileName,
  }) async => gradeFilesUploaded.add((gradeId, kind, fileName));

  @override
  Future<Uint8List> gradeFileBytes(String id) async =>
      Uint8List.fromList(const [37, 80, 68, 70]);

  @override
  Future<void> removeGradeFile(String id) async => gradeFilesRemoved.add(id);

  @override
  Future<void> restoreParty(String id) async => restored.add(id);

  final manufacturersCreated = <ManufacturerItem>[];

  @override
  Future<ManufacturerItem> createManufacturer(String name) async {
    final existing = testReference.manufacturers
        .where((m) => m.name == name)
        .firstOrNull;
    if (existing != null) return existing;
    final created = ManufacturerItem(id: 'man-new', name: name);
    manufacturersCreated.add(created);
    return created;
  }

  @override
  Future<List<CatalogManufacturer>> catalogManufacturers() async => [
    for (final m in testReference.manufacturers)
      CatalogManufacturer(id: m.id, name: m.name, gradeCount: 1),
  ];

  @override
  Future<void> updateManufacturer(
    String id,
    String name, {
    bool active = true,
  }) async {}

  @override
  Future<List<CatalogGrade>> catalogGrades({
    String? materialId,
    bool pendingOnly = false,
  }) async => [
    for (final m in testReference.materials)
      if (materialId == null || m.id == materialId)
        for (final g in m.grades)
          if (!pendingOnly || !g.verified)
            CatalogGrade(
              id: g.id,
              materialId: m.id,
              materialCode: m.code,
              code: g.code,
              manufacturerId: g.manufacturerId,
              manufacturerName: g.manufacturerId == null
                  ? null
                  : testReference.manufacturer(g.manufacturerId!)!.name,
              originIds: g.originIds,
              verified: g.verified,
              createdByName: g.verified ? null : 'أحمد محمد',
            ),
  ];

  @override
  Future<CatalogGrade> createGrade({
    required String materialId,
    required String? manufacturerId,
    required String code,
    List<String> originIds = const [],
    bool confirmSimilar = false,
  }) async {
    final error = createGradeError;
    if (error != null && !confirmSimilar) throw error;
    gradesCreated.add({
      'materialId': materialId,
      'manufacturerId': manufacturerId,
      'code': code,
      'confirmSimilar': confirmSimilar,
    });
    return CatalogGrade(
      id: gradesCreated.length == 1
          ? 'g-new'
          : 'g-new-${gradesCreated.length - 1}',
      materialId: materialId,
      materialCode: '?',
      code: code,
      manufacturerId: manufacturerId,
      verified: false,
    );
  }

  @override
  Future<CatalogGrade> updateGrade(
    String id, {
    required String? manufacturerId,
    required String code,
    required List<String> originIds,
    String? description,
    bool active = true,
  }) async => CatalogGrade(
    id: id,
    materialId: '?',
    materialCode: '?',
    code: code,
    manufacturerId: manufacturerId,
  );

  @override
  Future<CatalogGrade> verifyGrade(String id) async {
    verified.add(id);
    return CatalogGrade(id: id, materialId: '?', materialCode: '?', code: '?');
  }

  @override
  Future<LookupItem> createCountry(String code, String nameAr) async =>
      LookupItem(id: 'c-$code', code: code, nameAr: nameAr);

  final registryQueries = <RegistryFilter>[];

  /// شعار الشركة المحفوظ لكل طرف كما يرسله السيرفر في بطاقات السجل.
  final registryLogos = <String, String>{};
  final favorites = <(String, bool)>[];

  /// نتائج السجل: كل الأطراف المناسبة للدور، والمطابقة المفتوحة لمن اهتمامه مفتوح.
  @override
  Future<RegistryPage> registry(
    RegistryFilter filter, {
    int skip = 0,
    int take = 30,
  }) async {
    registryQueries.add(filter);
    final items = [
      for (final p in parties.values)
        if ((filter.role != 'customer' || p.isCustomer) &&
            (filter.role != 'supplier' || p.isSupplier) &&
            (!filter.favorites || p.isFavorite) &&
            (filter.query.isEmpty || p.name.contains(filter.query)))
          RegistryItem(
            id: p.id,
            name: p.name,
            isCustomer: p.isCustomer,
            isSupplier: p.isSupplier,
            primaryPhone: p.primaryPhone?.e164,
            activityId: p.isCustomer
                ? p.customerActivityId
                : p.supplierActivityId,
            governorateId: p.governorateId,
            region: p.region,
            isFavorite: p.isFavorite,
            logoAttachmentId: registryLogos[p.id],
            customerActivityIds: p.customerActivityIds,
            summary: p.isCustomer ? p.customerSummary : p.supplierSummary,
            specs: [
              for (final i in p.interests) i.spec,
              for (final pr in p.products) pr.spec,
            ],
            match: filter.materialId == null
                ? null
                : p.interests.any((i) => i.spec.isOpen)
                ? 'open'
                : 'exact',
          ),
    ];
    return RegistryPage(items, items.length);
  }

  @override
  Future<void> setFavorite(String partyId, bool favorite) async =>
      favorites.add((partyId, favorite));

  @override
  Future<List<HistoryEntry>> history(String partyId) async => [
    HistoryEntry(
      at: DateTime(2026, 10, 28, 10, 15),
      description: 'عدّل: الاسم',
      userName: 'أحمد محمد',
    ),
    HistoryEntry(
      at: DateTime(2026, 10, 25, 9, 2),
      description: 'أنشأ السجل',
      userName: 'أحمد محمد',
    ),
  ];

  final shared = <String>[];
  final locationsCreated = <(String, LocationDraft)>[];
  final locationsUpdated = <LocationDraft>[];
  final locationsRemoved = <String>[];

  Map<String, List<PartyLocation>> locationLists = {
    'party-1': const [
      PartyLocation(
        id: 'loc-1',
        partyId: 'party-1',
        kind: LocationKind.factory,
        label: 'البوابة 2',
        addressLine: 'المنطقة الصناعية - عنوان تجريبي',
        mapsUrl: 'https://maps.google.com/?q=30.2950,31.7420',
        latitude: 30.295,
        longitude: 31.742,
        accessNotes: 'التحميل حتى 4 م',
        isDefault: true,
      ),
      PartyLocation(
        id: 'loc-2',
        partyId: 'party-1',
        kind: LocationKind.delivery,
        addressLine: 'مخزن تجريبي',
        mapsUrl: 'https://maps.app.goo.gl/AbCdEf123',
      ),
    ],
  };

  @override
  Future<List<PartyLocation>> locations(String partyId) async =>
      locationLists[partyId] ?? const [];

  @override
  Future<PartyLocation> createLocation(
    String partyId,
    LocationDraft draft,
  ) async {
    locationsCreated.add((partyId, draft));
    return PartyLocation(
      id: draft.id,
      partyId: partyId,
      kind: draft.kind,
      label: draft.label,
      addressLine: draft.addressLine,
      mapsUrl: draft.mapsUrl,
      latitude: draft.latitude,
      longitude: draft.longitude,
      isDefault: draft.isDefault,
    );
  }

  @override
  Future<PartyLocation> updateLocation(
    PartyLocation current,
    LocationDraft draft,
  ) async {
    locationsUpdated.add(draft);
    return current;
  }

  @override
  Future<void> removeLocation(String id) async => locationsRemoved.add(id);

  final uploads = <Map<String, Object?>>[];
  final attachmentsRemoved = <String>[];

  Map<String, List<AttachmentItem>> attachmentLists = {
    'party-2': const [
      AttachmentItem(
        id: 'att-photo',
        kind: AttachmentKind.productPhoto,
        fileName: 'منتج.png',
        contentType: 'image/png',
        sizeBytes: 120000,
      ),
      AttachmentItem(
        id: 'att-tds',
        kind: AttachmentKind.technicalDataSheet,
        fileName: 'TDS-5502.pdf',
        contentType: 'application/pdf',
        sizeBytes: 1258291,
        spec: MaterialSpec(
          materialId: 'mat-hdpe',
          materialCode: 'HDPE',
          gradeId: 'g-5502',
          gradeCode: '5502',
          manufacturerId: 'man-a',
          manufacturerName: 'مصنع تجريبي أ',
          precision: SpecPrecision.exact,
        ),
      ),
    ],
  };

  @override
  Future<List<AttachmentItem>> attachments(String partyId) async =>
      attachmentLists[partyId] ?? const [];

  @override
  Future<AttachmentItem> uploadAttachment({
    required String partyId,
    required String id,
    required AttachmentKind kind,
    required String filePath,
    required String fileName,
    String? gradeId,
    String? materialId,
  }) async {
    uploads.add({
      'partyId': partyId,
      'kind': kind,
      'fileName': fileName,
      'gradeId': gradeId,
      'materialId': materialId,
    });
    return AttachmentItem(
      id: id,
      kind: kind,
      fileName: fileName,
      contentType: 'application/pdf',
      sizeBytes: 1,
    );
  }

  @override
  Future<Uint8List> attachmentBytes(String id) async => tinyPng;

  @override
  Future<void> removeAttachment(String id) async => attachmentsRemoved.add(id);
}

/// يسجل ما يُرسل لقائمة المشاركة بدل فتحها.
class FakeShareService extends ShareService {
  const FakeShareService(this.log);

  final List<String> log;

  @override
  Future<void> text(String text, {String? subject}) async => log.add(text);

  @override
  Future<void> file(String path, {String? mimeType, String? text}) async =>
      log.add('file:$path');
}

class FakeDeviceLocation extends DeviceLocation {
  const FakeDeviceLocation();

  @override
  Future<(double, double)> current() async => (30.0444, 31.2357);
}

/// صورة PNG حقيقية بحجم 1×1 للاختبارات.
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// اختيار ملفات وهمي: يعيد ملفًا بالحجم المطلوب ويسجل ما فُتح.
class FakeFileServices extends FileServices {
  FakeFileServices();

  int nextSize = 2048;
  final opened = <String>[];

  @override
  Future<PickedFile?> pickImage({required bool camera}) async =>
      PickedFile(path: '/tmp/photo.jpg', name: 'photo.jpg', size: nextSize);

  @override
  Future<PickedFile?> pickDocument(List<String> extensions) async =>
      extensions.contains('xlsx')
      ? PickedFile(path: '/tmp/data.xlsx', name: 'عملاء.xlsx', size: nextSize)
      : PickedFile(path: '/tmp/sheet.pdf', name: 'sheet.pdf', size: nextSize);

  @override
  Future<String> writeTemp(String id, String fileName, Uint8List bytes) async =>
      '/tmp/$id/$fileName';

  @override
  Future<Uint8List?> pickAnyBytes() async => Uint8List.fromList(const [80, 75]);

  @override
  Future<bool> open(String path, String mimeType) async {
    opened.add(path);
    return true;
  }
}

/// يسجل الإشعارات المجدولة بدل جدولتها فعليًا.
class FakeReminderScheduler implements ReminderScheduler {
  final scheduled = <String, Reminder>{};
  int permissionRequests = 0;
  int clears = 0;
  void Function(String partyId)? onOpen;

  @override
  Future<void> init(void Function(String partyId) onOpen) async =>
      this.onOpen = onOpen;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    scheduled
      ..clear()
      ..addAll({for (final r in reminders) r.key: r});
  }

  @override
  Future<void> clear() async {
    clears++;
    scheduled.clear();
  }
}

/// يسجل ملفات PDF والطباعة بدل إنشائها فعليًا.
class FakeDocumentServices extends DocumentServices {
  final printed = <TableDocument>[];
  final pdfs = <TableDocument>[];

  @override
  Future<Uint8List> pdf(TableDocument doc) async {
    pdfs.add(doc);
    return Uint8List.fromList(const [37, 80, 68, 70]);
  }

  @override
  Future<void> print(TableDocument doc, String name) async => printed.add(doc);
}
