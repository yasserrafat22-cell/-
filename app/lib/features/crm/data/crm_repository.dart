import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/catalog_models.dart';
import '../domain/crm_models.dart';

export '../domain/catalog_models.dart';

/// بيانات تسجيل عميل أو مورد. المعرف يُولد مرة واحدة عند فتح النموذج، فإعادة
/// الإرسال بعد انقطاع الاتصال لا تنشئ نسخة ثانية على السيرفر.
class NewParty {
  const NewParty({
    required this.id,
    required this.name,
    required this.phone,
    required this.isCustomer,
    this.activityId,
    this.representativeId,
    this.specs = const [],
  });

  final String id;
  final String name;
  final String phone;
  final bool isCustomer;
  final String? activityId;
  final String? representativeId;
  final List<SpecChoice> specs;

  Json toJson() => {
    'id': id,
    'name': name,
    'isCustomer': isCustomer,
    'isSupplier': !isCustomer,
    'phones': [
      {'number': phone},
    ],
    if (isCustomer) 'customerActivityId': activityId,
    if (!isCustomer) 'supplierActivityId': activityId,
    'representativeId': representativeId,
    if (isCustomer) 'interests': [for (final s in specs) s.toJson()],
    if (!isCustomer) 'products': [for (final s in specs) s.toJson()],
  };
}

class PartyDetailsUpdate {
  const PartyDetailsUpdate({
    required this.name,
    required this.phone,
    this.email,
    this.governorateId,
    this.region,
    this.addressLine,
    this.notes,
  });

  final String name;
  final String phone;
  final String? email;
  final String? governorateId;
  final String? region;
  final String? addressLine;
  final String? notes;
}

class NewLine {
  const NewLine({
    required this.spec,
    required this.quantity,
    required this.unitId,
  });

  final SpecChoice spec;
  final double quantity;
  final String unitId;

  Json toJson() => {...spec.toJson(), 'quantity': quantity, 'unitId': unitId};
}

/// فلاتر «السجل»؛ قيمة ثابتة تصلح مفتاحًا للمزود.
class RegistryFilter {
  const RegistryFilter({
    this.role,
    this.query = '',
    this.materialId,
    this.manufacturerId,
    this.gradeId,
    this.countryId,
    this.status,
    this.favorites = false,
  });

  /// `customer` أو `supplier` أو null (المفضلة).
  final String? role;
  final String query;
  final String? materialId;
  final String? manufacturerId;
  final String? gradeId;
  final String? countryId;
  final PartyStatus? status;
  final bool favorites;

  RegistryFilter copyWith({
    String? query,
    String? Function()? materialId,
    String? Function()? manufacturerId,
    String? Function()? gradeId,
    String? Function()? countryId,
    PartyStatus? Function()? status,
  }) => RegistryFilter(
    role: role,
    favorites: favorites,
    query: query ?? this.query,
    materialId: materialId == null ? this.materialId : materialId(),
    manufacturerId: manufacturerId == null
        ? this.manufacturerId
        : manufacturerId(),
    gradeId: gradeId == null ? this.gradeId : gradeId(),
    countryId: countryId == null ? this.countryId : countryId(),
    status: status == null ? this.status : status(),
  );

  Map<String, String> toQuery() => {
    'role': ?role,
    if (query.trim().isNotEmpty) 'q': query.trim(),
    'materialId': ?materialId,
    'manufacturerId': ?manufacturerId,
    'gradeId': ?gradeId,
    'countryId': ?countryId,
    if (status != null) 'status': status!.apiName,
    if (favorites) 'favorites': 'true',
  };

  @override
  bool operator ==(Object other) =>
      other is RegistryFilter &&
      other.role == role &&
      other.query == query &&
      other.materialId == materialId &&
      other.manufacturerId == manufacturerId &&
      other.gradeId == gradeId &&
      other.countryId == countryId &&
      other.status == status &&
      other.favorites == favorites;

  @override
  int get hashCode => Object.hash(
    role,
    query,
    materialId,
    manufacturerId,
    gradeId,
    countryId,
    status,
    favorites,
  );
}

class RegistryPage {
  const RegistryPage(this.items, this.total);

  final List<RegistryItem> items;
  final int total;
}

class CrmRepository {
  const CrmRepository(this._api);

  final ApiClient _api;

  Future<ReferenceData> reference() async =>
      ReferenceData.fromJson(await _api.get('/api/v1/reference') as Json);

  Future<PartyDetail> createParty(NewParty party) async => PartyDetail.fromJson(
    await _api.post('/api/v1/parties', party.toJson()) as Json,
  );

  Future<PartyDetail> party(String id) async =>
      PartyDetail.fromJson(await _api.get('/api/v1/parties/$id') as Json);

  /// يضيف دور العميل أو المورد لشركة مسجلة بالفعل بدل تكرارها.
  Future<PartyDetail> addRole(
    String id, {
    required bool customer,
    String? activityId,
  }) async => PartyDetail.fromJson(
    await _api.post('/api/v1/parties/$id/roles', {
      'isCustomer': customer,
      'isSupplier': !customer,
      if (customer) 'customerActivityId': activityId,
      if (!customer) 'supplierActivityId': activityId,
    }) as Json,
  );

  Future<PartyDetail> updateDetails(
    PartyDetail current,
    PartyDetailsUpdate update,
  ) => _put(current, {
    'name': update.name,
    'phones': [
      {'number': update.phone},
      for (final p in current.phones.skip(1))
        {'number': p.e164, 'whatsApp': p.whatsApp},
    ],
    'email': update.email,
    'notes': update.notes,
    'governorateId': update.governorateId,
    'region': update.region,
    'addressLine': update.addressLine,
  });

  /// يستبدل خامات العميل بالقائمة كاملة (الموجودة + الجديدة) مع حفظ باقي البيانات.
  Future<PartyDetail> setInterests(
    PartyDetail current,
    List<SpecChoice> specs,
  ) => _put(current, {
    'interests': [for (final s in specs) s.toJson()],
  });

  Future<void> addProduct(String partyId, SpecChoice spec) =>
      _api.post('/api/v1/parties/$partyId/products', spec.toJson());

  /// التعديل يرسل كل البيانات الحالية مع رقم النسخة، ويستبدل الحقول المعطاة فقط.
  Future<PartyDetail> _put(PartyDetail current, Json changes) async =>
      PartyDetail.fromJson(
        await _api.put('/api/v1/parties/${current.id}', {
          'version': current.version,
          'name': current.name,
          'phones': [
            for (final p in current.phones)
              {'number': p.e164, 'whatsApp': p.whatsApp},
          ],
          'customerActivityId': current.customerActivityId,
          'supplierActivityId': current.supplierActivityId,
          'representativeId': current.representativeId,
          'email': current.email,
          'notes': current.notes,
          'governorateId': current.governorateId,
          'region': current.region,
          'addressLine': current.addressLine,
          ...changes,
        }) as Json,
      );

  Future<List<InteractionItem>> interactions(String partyId) async =>
      (await _api.get('/api/v1/parties/$partyId/interactions') as List)
          .cast<Json>()
          .map(InteractionItem.fromJson)
          .toList();

  Future<void> addInteraction(
    String partyId, {
    required String id,
    required ContactChannel channel,
    required String outcomeId,
    String? notes,
    DateTime? nextFollowUpAt,
    bool remind = false,
  }) => _api.post('/api/v1/parties/$partyId/interactions', {
    'id': id,
    'channel': channel.name,
    'outcomeId': outcomeId,
    'notes': notes,
    'nextFollowUpAt': nextFollowUpAt?.toUtc().toIso8601String(),
    'remind': remind,
  });

  Future<List<OrderItem>> orders(String customerId) async =>
      (await _api.get('/api/v1/parties/$customerId/orders') as List)
          .cast<Json>()
          .map(OrderItem.fromJson)
          .toList();

  Future<void> createOrder({
    required String id,
    required String customerId,
    required String orderDate,
    required OrderStage stage,
    required List<NewLine> lines,
    String? notes,
    String? locationId,
  }) => _api.post('/api/v1/orders', {
    'id': id,
    'customerId': customerId,
    'orderDate': orderDate,
    'stage': stage.name,
    'lines': [for (final l in lines) l.toJson()],
    'notes': notes,
    'deliveryLocationId': locationId,
  });

  Future<void> changeOrderStage(OrderItem order, OrderStage stage) => _api.post(
    '/api/v1/orders/${order.id}/stage',
    {'stage': stage.name, 'version': order.version},
  );

  Future<List<SupplyItem>> supplies(String supplierId) async =>
      (await _api.get('/api/v1/parties/$supplierId/supplies') as List)
          .cast<Json>()
          .map(SupplyItem.fromJson)
          .toList();

  Future<void> createSupply({
    required String id,
    required String supplierId,
    required String supplyDate,
    required SupplyStatus status,
    required List<NewLine> lines,
    String? notes,
    String? locationId,
  }) => _api.post('/api/v1/supplies', {
    'id': id,
    'supplierId': supplierId,
    'supplyDate': supplyDate,
    'status': status.name,
    'lines': [for (final l in lines) l.toJson()],
    'notes': notes,
    'loadingLocationId': locationId,
  });

  Future<void> changeSupplyStatus(SupplyItem supply, SupplyStatus status) =>
      _api.post('/api/v1/supplies/${supply.id}/status', {
        'status': status.name,
        'version': supply.version,
      });

  // ---------------- الكتالوج ----------------

  /// يعيد الشركة الموجودة بنفس الاسم إن وُجدت بدل تكرارها.
  Future<ManufacturerItem> createManufacturer(String name) async =>
      ManufacturerItem.fromJson(
        await _api.post('/api/v1/catalog/manufacturers', {'name': name})
            as Json,
      );

  Future<List<CatalogManufacturer>> catalogManufacturers() async =>
      (await _api.get('/api/v1/catalog/manufacturers') as List)
          .cast<Json>()
          .map(CatalogManufacturer.fromJson)
          .toList();

  Future<void> updateManufacturer(
    String id,
    String name, {
    bool active = true,
  }) => _api.put('/api/v1/catalog/manufacturers/$id', {
    'name': name,
    'isActive': active,
  });

  Future<List<CatalogGrade>> catalogGrades({
    String? materialId,
    bool pendingOnly = false,
  }) async => (await _api.get(
    '/api/v1/catalog/grades?pending=$pendingOnly'
    '${materialId == null ? '' : '&materialId=$materialId'}',
  ) as List).cast<Json>().map(CatalogGrade.fromJson).toList();

  /// يرمي [ApiException] بالكود `catalog.similar_grade` (ومعه القائمة في
  /// `data`) إذا وُجد نفس الكود لشركة أخرى، حتى يؤكد المستخدم.
  Future<CatalogGrade> createGrade({
    required String materialId,
    required String manufacturerId,
    required String code,
    List<String> originIds = const [],
    bool confirmSimilar = false,
  }) async => CatalogGrade.fromJson(
    await _api.post('/api/v1/catalog/grades', {
      'materialId': materialId,
      'manufacturerId': manufacturerId,
      'code': code,
      'originIds': originIds,
      'confirmSimilar': confirmSimilar,
    }) as Json,
  );

  Future<CatalogGrade> updateGrade(
    String id, {
    required String? manufacturerId,
    required String code,
    required List<String> originIds,
    String? description,
    bool active = true,
  }) async => CatalogGrade.fromJson(
    await _api.put('/api/v1/catalog/grades/$id', {
      'manufacturerId': manufacturerId,
      'code': code,
      'originIds': originIds,
      'description': description,
      'isActive': active,
    }) as Json,
  );

  Future<CatalogGrade> verifyGrade(String id) async => CatalogGrade.fromJson(
    await _api.post('/api/v1/catalog/grades/$id/verify', const {}) as Json,
  );

  Future<LookupItem> createCountry(String code, String nameAr) async =>
      LookupItem.fromJson(
        await _api.post('/api/v1/catalog/countries', {
          'code': code,
          'nameAr': nameAr,
        }) as Json,
      );

  // ---------------- السجل ----------------

  Future<RegistryPage> registry(
    RegistryFilter filter, {
    int skip = 0,
    int take = 30,
  }) async {
    final query = Uri(
      queryParameters: {...filter.toQuery(), 'skip': '$skip', 'take': '$take'},
    ).query;
    final json = await _api.get('/api/v1/parties?$query') as Json;
    return RegistryPage(
      (json['items'] as List).cast<Json>().map(RegistryItem.fromJson).toList(),
      json['total'] as int,
    );
  }

  Future<void> setFavorite(String partyId, bool favorite) => favorite
      ? _api.put('/api/v1/parties/$partyId/favorite', null)
      : _api.delete('/api/v1/parties/$partyId/favorite');

  Future<List<HistoryEntry>> history(String partyId) async =>
      (await _api.get('/api/v1/parties/$partyId/history') as List)
          .cast<Json>()
          .map(HistoryEntry.fromJson)
          .toList();

  // ---------------- المواقع ----------------

  Future<List<PartyLocation>> locations(String partyId) async =>
      (await _api.get('/api/v1/parties/$partyId/locations') as List)
          .cast<Json>()
          .map(PartyLocation.fromJson)
          .toList();

  Future<PartyLocation> createLocation(
    String partyId,
    LocationDraft draft,
  ) async => PartyLocation.fromJson(
    await _api.post('/api/v1/parties/$partyId/locations', draft.toJson())
        as Json,
  );

  Future<PartyLocation> updateLocation(
    PartyLocation current,
    LocationDraft draft,
  ) async => PartyLocation.fromJson(
    await _api.put(
      '/api/v1/locations/${current.id}',
      draft.toJson(version: current.version),
    ) as Json,
  );

  Future<void> removeLocation(String id) =>
      _api.delete('/api/v1/locations/$id');

  // ---------------- المرفقات ----------------

  Future<List<AttachmentItem>> attachments(String partyId) async =>
      (await _api.get('/api/v1/parties/$partyId/attachments') as List)
          .cast<Json>()
          .map(AttachmentItem.fromJson)
          .toList();

  Future<AttachmentItem> uploadAttachment({
    required String partyId,
    required String id,
    required AttachmentKind kind,
    required String filePath,
    required String fileName,
    String? gradeId,
    String? materialId,
  }) async => AttachmentItem.fromJson(
    await _api.post(
      '/api/v1/parties/$partyId/attachments',
      FormData.fromMap({
        'id': id,
        'kind': kind.name,
        'gradeId': ?gradeId,
        'materialId': ?materialId,
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      }),
    ) as Json,
  );

  Future<Uint8List> attachmentBytes(String id) =>
      _api.bytes('/api/v1/attachments/$id/content');

  Future<void> removeAttachment(String id) =>
      _api.delete('/api/v1/attachments/$id');
}
