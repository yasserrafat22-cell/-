import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:uuid/uuid.dart';

import '../../../core/device/file_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/offline_store.dart';
import '../../../core/security/backup_key_wrap.dart';
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
    this.recordDate,
    this.specs = const [],
    this.confirmSimilar = false,
  });

  final String id;
  final String name;
  final String phone;
  final bool isCustomer;
  final String? activityId;
  final String? representativeId;
  final DateTime? recordDate;
  final List<SpecChoice> specs;

  /// المستخدم أكد أنه ليس نفس الشركة رغم وجود سجل مشابه.
  final bool confirmSimilar;

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
    if (recordDate case final d?)
      'recordDate':
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    if (isCustomer) 'interests': [for (final s in specs) s.toJson()],
    if (!isCustomer) 'products': [for (final s in specs) s.toJson()],
    if (confirmSimilar) 'confirmSimilar': true,
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
    this.deleted = false,
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

  /// المحذوفات (للمدير العام فقط) لاستعادتها.
  final bool deleted;

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
    deleted: deleted,
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
    if (deleted) 'deleted': 'true',
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
      other.favorites == favorites &&
      other.deleted == deleted;

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
    deleted,
  );
}

class RegistryPage {
  const RegistryPage(this.items, this.total);

  final List<RegistryItem> items;
  final int total;
}

/// علامة «حُفظت العملية على الجهاز وستُرسل عند عودة الاتصال».
const queuedOffline = _Queued();

class _Queued {
  const _Queued();
}

/// نتيجة مزامنة: عدد ما أُرسل، وعدد ما يحتاج مراجعة.
class SyncResult {
  const SyncResult(this.sent, this.needsReview);

  final int sent;
  final int needsReview;

  SyncResult _merge(SyncResult next) =>
      SyncResult(sent + next.sent, next.needsReview);
}

class CrmRepository {
  const CrmRepository(this._api, {this._offline, this._userId, this._files});

  final ApiClient _api;

  /// لنسخ الملفات المنتظرة للرفع دون اتصال داخل مساحة التطبيق.
  final FileServices? _files;

  /// العمل دون اتصال: نسخ محلية للقراءة وطابور للكتابة (للمستخدم الحالي فقط).
  final OfflineStore? _offline;
  final String? _userId;

  bool get _canWorkOffline => _offline != null && _userId != null;

  /// قراءة مع حفظ نسخة محلية؛ عند انقطاع الاتصال تُعرض آخر نسخة محفوظة.
  Future<Object?> _get(String path) async {
    try {
      final json = await _api.get(path);
      if (_canWorkOffline) await _offline!.remember(_userId!, path, json);
      return json;
    } on ApiException catch (e) {
      if (!_canWorkOffline) rethrow;
      // لم يعد مسموحًا (صلاحية سُحبت أو سجل حُذف): تُحذف النسخة المحلية فلا تُعرض لاحقًا.
      if (e.status == 403 || e.status == 404) {
        await _offline!.forget(_userId!, path);
        rethrow;
      }
      if (!e.isNetwork) rethrow;
      return await _offline!.cached(_userId!, path) ?? (throw e);
    }
  }

  /// قوائم ملف طرف: لسجل لم يُزامن بعد تكون فارغة بدل خطأ.
  Future<List<Json>> _getList(String path, String partyId) async {
    try {
      return (await _get(path) as List).cast<Json>();
    } on ApiException {
      if (await _localParty(partyId) != null) return const [];
      rethrow;
    }
  }

  Future<List<PendingOp>> _pending() async =>
      _canWorkOffline ? await _offline!.ops(_userId!) : const [];

  Future<PendingOp?> _localParty(String partyId) async => (await _pending())
      .where((o) => o.kind == 'party.create' && o.partyId == partyId)
      .firstOrNull;

  /// كتابة تُحفظ على الجهاز إذا انقطع الاتصال. إذا كان للسجل عمليات لم تُرسل
  /// بعد تُضاف بعدها مباشرة للحفاظ على الترتيب (مثل موقع لعميل جديد).
  Future<Object?> _write(
    String method,
    String path,
    Object? body, {
    required String label,
    String? partyId,
    String? kind,
  }) async {
    if (_canWorkOffline && await _mustWait(partyId, body)) {
      return _enqueue(
        method,
        path,
        body,
        label: label,
        partyId: partyId,
        kind: kind,
      );
    }
    try {
      return await _send(method, path, body);
    } on ApiException catch (e) {
      if (!e.isNetwork || !_canWorkOffline) rethrow;
      return _enqueue(
        method,
        path,
        body,
        label: label,
        partyId: partyId,
        kind: kind,
      );
    }
  }

  Future<Object> _enqueue(
    String method,
    String path,
    Object? body, {
    required String label,
    String? partyId,
    String? kind,
  }) async {
    await _offline!.enqueue(
      PendingOp(
        id: const Uuid().v7(),
        userId: _userId!,
        method: method,
        path: path,
        body: body,
        label: label,
        createdAt: DateTime.now(),
        partyId: partyId,
        kind: kind,
      ),
    );
    return queuedOffline;
  }

  /// تنتظر العملية في الطابور إذا كان لسجلها عمليات لم تُرسل، أو كانت تشير إلى
  /// خامة/شركة/Grade أُضيف دون اتصال ولم يصل للسيرفر بعد (حفاظًا على الترتيب والعلاقات).
  Future<bool> _mustWait(String? partyId, Object? body) async {
    if (!_canWorkOffline) return false;
    final pending = await _pending();
    if (pending.isEmpty) return false;
    if (partyId != null && pending.any((o) => o.partyId == partyId)) {
      return true;
    }
    final text = body == null ? '' : jsonEncode(body);
    return pending.any(
      (o) =>
          (o.kind?.startsWith('catalog.') ?? false) &&
          o.body is Map &&
          text.contains((o.body! as Map)['id'] as String? ?? '\u0000'),
    );
  }

  /// عملية رفع ملف (صورة أو PDF): بدون اتصال تُحفظ نسخة من الملف داخل التطبيق
  /// وتنتظر في الطابور حتى يؤكد السيرفر استلامها.
  Future<Object?> _upload(
    String path,
    Map<String, String> fields,
    String filePath,
    String fileName, {
    required String label,
    required String partyId,
  }) async {
    Map<String, Object?> body(String file) => {
      'upload': {'fields': fields, 'path': file, 'fileName': fileName},
    };
    final files = _files;
    if (!_canWorkOffline || files == null) {
      return _send('POST', path, body(filePath));
    }
    if (!await _mustWait(partyId, null)) {
      try {
        return await _send('POST', path, body(filePath));
      } on ApiException catch (e) {
        if (!e.isNetwork) rethrow;
      }
    }
    return _enqueue(
      'POST',
      path,
      body(await files.keepForUpload(filePath, fields['id']!)),
      label: label,
      partyId: partyId,
    );
  }

  /// يرسل العملية؛ محتوى `upload` يتحول لنموذج ملف (multipart).
  Future<Object?> _send(String method, String path, Object? body) async {
    if (body is Map && body['upload'] is Map) {
      final u = (body['upload'] as Map).cast<String, Object?>();
      return _api.send(
        method,
        path,
        FormData.fromMap({
          ...(u['fields']! as Map).cast<String, Object?>(),
          'file': await MultipartFile.fromFile(
            u['path']! as String,
            filename: u['fileName'] as String?,
          ),
        }),
      );
    }
    return _api.send(method, path, body);
  }

  /// يرسل العمليات المحفوظة بالترتيب. يتوقف عند انقطاع الاتصال؛ ما يرفضه
  /// السيرفر (صلاحية، تكرار، تعارض) يُعلَّم «يحتاج مراجعة» مع سببه، وتنتظر
  /// بعده عمليات نفس السجل. الصلاحيات يعيد السيرفر فحصها مع كل عملية.
  Future<SyncResult> syncPending() async {
    if (!_canWorkOffline) return const SyncResult(0, 0);
    var sent = 0;
    final blocked = <String>{};
    for (final op in await _pending()) {
      if (op.status == PendingStatus.needsReview) {
        if (op.partyId != null) blocked.add(op.partyId!);
        continue;
      }
      if (op.partyId != null && blocked.contains(op.partyId)) continue;
      try {
        op.attempts++;
        final response = await _send(op.method, op.path, op.body);
        await _offline!.remove(op.id);
        sent++;
        if (op.body case {'upload': {'path': final String kept}}) {
          await _files?.discardUpload(kept);
        }
        // نفس السجل موجود على السيرفر بمعرف آخر (مثل Grade أضافه جهاز آخر): تُربط
        // العمليات التالية بالمعرف الصحيح بدل إنشاء نسخة مكررة.
        if (op.body case {'id': final String localId}
            when response is Map &&
                response['id'] is String &&
                response['id'] != localId) {
          await _offline.remap(_userId!, localId, response['id'] as String);
          return SyncResult(sent, 0)._merge(await syncPending());
        }
      } on ApiException catch (e) {
        if (e.isNetwork || e.code == 'auth') {
          await _offline!.update(op);
          break;
        }
        op
          ..status = PendingStatus.needsReview
          ..errorCode = e.code
          ..error = e.message;
        await _offline!.update(op);
        if (op.partyId != null) blocked.add(op.partyId!);
      }
    }
    final review = (await _pending())
        .where((o) => o.status == PendingStatus.needsReview)
        .length;
    return SyncResult(sent, review);
  }

  Future<List<PendingOp>> pendingOps() => _pending();

  Future<SupplierMatches> supplierMatches(String customerId) async =>
      SupplierMatches.fromJson(
        await _get('/api/v1/parties/$customerId/supplier-matches') as Json,
      );

  Future<ReportSummary> reportSummary() async =>
      ReportSummary.fromJson(await _get('/api/v1/reports/summary') as Json);

  /// المتابعات المفتوحة خلال [days] يومًا (مع آخر نسخة محفوظة دون اتصال).
  Future<List<FollowUpItem>> followUps({int days = 7}) async =>
      ((await _get('/api/v1/follow-ups?days=$days')) as List)
          .cast<Json>()
          .map(FollowUpItem.fromJson)
          .toList();

  /// نسخة كاملة مشفرة: يُرسل للسيرفر مفتاح عام مؤقت فقط، وكلمة المرور تغلّف مفتاح
  /// النسخة على الجهاز (لا تمر على الشبكة ولا تُحفظ).
  Future<Uint8List> fullBackup(String password) async {
    final wrap = BackupKeyWrap.generate();
    final wire = await _api.postBytes('/api/v1/admin/backups', {
      'publicKey': wrap.publicKeyBase64,
    });
    return wrap.toPasswordFile(wire, password);
  }

  /// ملف Excel للعملاء أو الموردين بحسب صلاحيات المستخدم.
  Future<Uint8List> exportParties(String role) =>
      _api.bytes('/api/v1/export/parties?role=$role');

  /// نسخة مشفرة من بيانات الجهاز غير المرسلة (لحفظها عند تعطل الاتصال طويلًا).
  Future<Uint8List> deviceBackup(String password) async {
    if (!_canWorkOffline) throw ApiException.network;
    return _offline!.exportFor(_userId!, password);
  }

  Future<int> importDeviceBackup(Uint8List bytes, String password) async {
    if (!_canWorkOffline) throw ApiException.network;
    return _offline!.importFor(_userId!, bytes, password);
  }

  /// إعادة المحاولة بعد المراجعة؛ [confirmSimilar] يؤكد الإضافة رغم وجود سجل مشابه.
  Future<void> retryOp(PendingOp op, {bool confirmSimilar = false}) async {
    if (confirmSimilar && op.body is Map) {
      (op.body! as Map)['confirmSimilar'] = true;
    }
    op
      ..status = PendingStatus.pending
      ..error = null
      ..errorCode = null;
    await _offline?.update(op);
  }

  Future<void> discardOp(PendingOp op) async {
    if (op.body case {'upload': {'path': final String kept}}) {
      await _files?.discardUpload(kept);
    }
    await _offline?.remove(op.id);
  }

  /// القوائم الأساسية مع ما أُضيف للكتالوج على الجهاز ولم يُزامن بعد.
  Future<ReferenceData> reference() async {
    final json = Map<String, dynamic>.of(
      await _get('/api/v1/reference') as Json,
    );
    final local = (await _pending()).where(
      (o) => (o.kind?.startsWith('catalog.') ?? false) && o.body is Map,
    );
    if (local.isEmpty) return ReferenceData.fromJson(json);
    final materials = [
      for (final m in (json['materials'] as List).cast<Json>())
        {...m, 'grades': List<Object?>.of(m['grades'] as List)},
    ];
    final makers = List<Object?>.of(json['manufacturers'] as List? ?? []);
    for (final op in local) {
      final b = (op.body! as Map).cast<String, Object?>();
      switch (op.kind) {
        case 'catalog.material' when !materials.any((m) => m['id'] == b['id']):
          materials.add({
            'id': b['id'],
            'code': b['code'],
            'nameAr': b['nameAr'] ?? b['code'],
            'grades': <Object?>[],
          });
        case 'catalog.manufacturer':
          makers.add({'id': b['id'], 'name': b['name']});
        case 'catalog.grade':
          final material = materials
              .where((m) => m['id'] == b['materialId'])
              .firstOrNull;
          (material?['grades'] as List?)?.add({
            'id': b['id'],
            'code': b['code'],
            'manufacturerId': b['manufacturerId'],
            'isVerified': true,
            'originIds': b['originIds'],
          });
      }
    }
    return ReferenceData.fromJson({
      ...json,
      'materials': materials,
      'manufacturers': makers,
    });
  }

  /// يعيد null إذا حُفظ السجل لكنه لا يظهر لصاحبه (مثل مورد أضافه مندوب).
  Future<PartyDetail?> createParty(NewParty party) async {
    final result = await _write(
      'POST',
      '/api/v1/parties',
      party.toJson(),
      label: '${party.isCustomer ? 'عميل' : 'مورد'} جديد: ${party.name}',
      partyId: party.id,
      kind: 'party.create',
    );
    if (identical(result, queuedOffline)) {
      return _localDetail(party.toJson());
    }
    final json = result! as Json;
    return json['visible'] == false ? null : PartyDetail.fromJson(json);
  }

  /// ملف مبدئي من البيانات المحفوظة على الجهاز (قبل المزامنة).
  static PartyDetail _localDetail(Object? body) {
    final j = (body! as Map).cast<String, Object?>();
    final number = ((j['phones']! as List).first as Map)['number'] as String;
    final digits = number.replaceAll(RegExp(r'[^\d+]'), '');
    return PartyDetail(
      id: j['id']! as String,
      version: 0,
      name: j['name']! as String,
      isCustomer: j['isCustomer']! as bool,
      isSupplier: j['isSupplier']! as bool,
      phones: [
        Phone(
          e164: digits.startsWith('+')
              ? digits
              : '+20${digits.startsWith('0') ? digits.substring(1) : digits}',
          isPrimary: true,
        ),
      ],
      interests: const [],
      products: const [],
      canEdit: false,
      canAdd: true,
      customerActivityId: j['customerActivityId'] as String?,
      supplierActivityId: j['supplierActivityId'] as String?,
      representativeId: j['representativeId'] as String?,
    );
  }

  Future<PartyDetail> party(String id) async {
    try {
      return PartyDetail.fromJson(await _get('/api/v1/parties/$id') as Json);
    } on ApiException {
      // سجل أُنشئ على الجهاز ولم يُزامن بعد.
      if (await _localParty(id) case final op?) return _localDetail(op.body);
      rethrow;
    }
  }

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

  /// يضيف خامة لاهتمامات العميل دون تعديل الموجود.
  Future<void> addInterest(String partyId, SpecChoice spec) => _write(
    'POST',
    '/api/v1/parties/$partyId/interests',
    spec.toJson(),
    label: 'إضافة خامة',
    partyId: partyId,
  );

  /// إسناد السجل لمندوب آخر (حدث إداري لمديري الأقسام والمدير العام).
  Future<void> assignParty(String id, String representativeId) => _api.post(
    '/api/v1/parties/$id/assign',
    {'representativeId': representativeId},
  );

  /// حذف آمن (منطقي) واستعادة: للمدير العام فقط.
  Future<void> deleteParty(String id) => _api.delete('/api/v1/parties/$id');

  Future<void> restoreParty(String id) =>
      _api.post('/api/v1/parties/$id/restore', const <String, Object?>{});

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
      (await _getList(
        '/api/v1/parties/$partyId/interactions',
        partyId,
      )).map(InteractionItem.fromJson).toList();

  Future<void> addInteraction(
    String partyId, {
    required String id,
    required ContactChannel channel,
    required String outcomeId,
    String? notes,
    DateTime? nextFollowUpAt,
    bool remind = false,
  }) => _write(
    'POST',
    '/api/v1/parties/$partyId/interactions',
    label: 'تسجيل تواصل',
    partyId: partyId,
    {
      'id': id,
      'channel': channel.name,
      'outcomeId': outcomeId,
      'notes': notes,
      'nextFollowUpAt': nextFollowUpAt?.toUtc().toIso8601String(),
      'remind': remind,
    },
  );

  Future<List<OrderItem>> orders(String customerId) async => (await _getList(
    '/api/v1/parties/$customerId/orders',
    customerId,
  )).map(OrderItem.fromJson).toList();

  Future<void> createOrder({
    required String id,
    required String customerId,
    required String orderDate,
    required OrderStage stage,
    required List<NewLine> lines,
    String? notes,
    String? locationId,
  }) =>
      _write('POST', '/api/v1/orders', label: 'طلب جديد', partyId: customerId, {
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

  Future<List<SupplyItem>> supplies(String supplierId) async => (await _getList(
    '/api/v1/parties/$supplierId/supplies',
    supplierId,
  )).map(SupplyItem.fromJson).toList();

  Future<void> createSupply({
    required String id,
    required String supplierId,
    required String supplyDate,
    required SupplyStatus status,
    required List<NewLine> lines,
    String? notes,
    String? locationId,
  }) => _write(
    'POST',
    '/api/v1/supplies',
    label: 'توريد جديد',
    partyId: supplierId,
    {
      'id': id,
      'supplierId': supplierId,
      'supplyDate': supplyDate,
      'status': status.name,
      'lines': [for (final l in lines) l.toJson()],
      'notes': notes,
      'loadingLocationId': locationId,
    },
  );

  Future<void> changeSupplyStatus(SupplyItem supply, SupplyStatus status) =>
      _api.post('/api/v1/supplies/${supply.id}/status', {
        'status': status.name,
        'version': supply.version,
      });

  // ---------------- الكتالوج ----------------

  /// يعيد الشركة الموجودة بنفس الاسم إن وُجدت بدل تكرارها.
  /// الإضافة تعمل دون اتصال: المعرف يولده التطبيق، ويُربط بالموجود عند المزامنة.
  Future<ManufacturerItem> createManufacturer(String name) async {
    final body = {'id': const Uuid().v7(), 'name': name.trim()};
    final result = await _write(
      'POST',
      '/api/v1/catalog/manufacturers',
      body,
      label: 'شركة مصنّعة: ${name.trim()}',
      partyId: body['id'],
      kind: 'catalog.manufacturer',
    );
    return ManufacturerItem.fromJson(
      identical(result, queuedOffline) ? body : result! as Json,
    );
  }

  /// نوع خامة أساسي (PP، ABS، PA...) بدون مصنع أو Grade.
  Future<MaterialItem> createMaterialType(
    String code, {
    String? nameAr,
    String? nameEn,
  }) async {
    final body = {
      'id': const Uuid().v7(),
      'code': code.trim().toUpperCase(),
      'nameAr': nameAr,
      'nameEn': nameEn,
    };
    final result = await _write(
      'POST',
      '/api/v1/catalog/materials',
      body,
      label: 'نوع خامة: ${body['code']}',
      partyId: body['id'],
      kind: 'catalog.material',
    );
    return MaterialItem.fromJson(
      identical(result, queuedOffline)
          ? {
              ...body,
              'nameAr': nameAr ?? body['code'],
              'grades': const <Object>[],
            }
          : result! as Json,
    );
  }

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
  }) async {
    final body = {
      'id': const Uuid().v7(),
      'materialId': materialId,
      'manufacturerId': manufacturerId,
      'code': code,
      'originIds': originIds,
      'confirmSimilar': confirmSimilar,
    };
    final result = await _write(
      'POST',
      '/api/v1/catalog/grades',
      body,
      label: 'Grade جديد: $code',
      partyId: body['id'] as String,
      kind: 'catalog.grade',
    );
    return CatalogGrade.fromJson(
      identical(result, queuedOffline)
          ? {...body, 'materialCode': '', 'isVerified': true}
          : result! as Json,
    );
  }

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
    final json = await _get('/api/v1/parties?$query') as Json;
    final items = (json['items'] as List)
        .cast<Json>()
        .map(RegistryItem.fromJson)
        .toList();
    // السجلات المحفوظة على الجهاز ولم تُزامن تظهر أولًا في القائمة المناسبة.
    final local = <RegistryItem>[
      if (skip == 0 && !filter.favorites && !filter.deleted)
        for (final op in await _pending())
          if (op.kind == 'party.create')
            if (_localDetail(op.body) case final p
                when (filter.role != 'customer' || p.isCustomer) &&
                    (filter.role != 'supplier' || p.isSupplier) &&
                    (filter.query.trim().isEmpty ||
                        p.name.contains(filter.query.trim())) &&
                    !items.any((i) => i.id == p.id))
              RegistryItem(
                id: p.id,
                name: p.name,
                isCustomer: p.isCustomer,
                isSupplier: p.isSupplier,
                primaryPhone: p.primaryPhone?.e164,
                activityId: p.customerActivityId ?? p.supplierActivityId,
              ),
    ];
    return RegistryPage([
      ...local,
      ...items,
    ], (json['total'] as int) + local.length);
  }

  Future<void> setFavorite(String partyId, bool favorite) => _write(
    favorite ? 'PUT' : 'DELETE',
    '/api/v1/parties/$partyId/favorite',
    null,
    label: favorite ? 'إضافة للمفضلة' : 'إزالة من المفضلة',
    partyId: partyId,
  );

  Future<List<HistoryEntry>> history(String partyId) async => (await _getList(
    '/api/v1/parties/$partyId/history',
    partyId,
  )).map(HistoryEntry.fromJson).toList();

  // ---------------- المواقع ----------------

  Future<List<PartyContact>> contacts(String partyId) async => (await _getList(
    '/api/v1/parties/$partyId/contacts',
    partyId,
  )).map(PartyContact.fromJson).toList();

  Future<void> addContact(String partyId, PartyContact contact) => _write(
    'POST',
    '/api/v1/parties/$partyId/contacts',
    contact.toJson(),
    label: 'جهة اتصال: ${contact.name}',
    partyId: partyId,
  );

  /// تعديل وحذف جهات الاتصال المحفوظة: للمدير العام فقط.
  Future<void> updateContact(PartyContact contact) =>
      _api.put('/api/v1/contacts/${contact.id}', contact.toJson());

  Future<void> removeContact(String id) => _api.delete('/api/v1/contacts/$id');

  Future<List<PartyLocation>> locations(String partyId) async =>
      (await _getList(
        '/api/v1/parties/$partyId/locations',
        partyId,
      )).map(PartyLocation.fromJson).toList();

  Future<PartyLocation> createLocation(
    String partyId,
    LocationDraft draft,
  ) async {
    final result = await _write(
      'POST',
      '/api/v1/parties/$partyId/locations',
      draft.toJson(),
      label: 'موقع جديد',
      partyId: partyId,
    );
    return PartyLocation.fromJson(
      identical(result, queuedOffline)
          ? {...draft.toJson(), 'partyId': partyId}
          : result! as Json,
    );
  }

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
      (await _getList(
        '/api/v1/parties/$partyId/attachments',
        partyId,
      )).map(AttachmentItem.fromJson).toList();

  Future<AttachmentItem> uploadAttachment({
    required String partyId,
    required String id,
    required AttachmentKind kind,
    required String filePath,
    required String fileName,
    String? gradeId,
    String? materialId,
  }) async {
    final result = await _upload(
      '/api/v1/parties/$partyId/attachments',
      {
        'id': id,
        'kind': kind.name,
        'gradeId': ?gradeId,
        'materialId': ?materialId,
      },
      filePath,
      fileName,
      label: 'ملف: $fileName',
      partyId: partyId,
    );
    return AttachmentItem.fromJson(
      identical(result, queuedOffline)
          ? {
              'id': id,
              'kind': kind.name,
              'fileName': fileName,
              'contentType': '',
              'sizeBytes': 0,
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            }
          : result! as Json,
    );
  }

  /// صورة الـ Grade (`photo`) أو ملف المواصفات PDF (`dataSheet`) في الكتالوج.
  Future<void> uploadGradeFile({
    required String gradeId,
    required String id,
    required String kind,
    required String filePath,
    required String fileName,
  }) => _upload(
    '/api/v1/catalog/grades/$gradeId/files',
    {'id': id, 'kind': kind},
    filePath,
    fileName,
    label: kind == 'dataSheet' ? 'ملف مواصفات: $fileName' : 'صورة Grade',
    // ينتظر بعد إضافة الـ Grade نفسه إن كان مضافًا دون اتصال.
    partyId: gradeId,
  );

  Future<Uint8List> gradeFileBytes(String id) =>
      _api.bytes('/api/v1/catalog/grade-files/$id/content');

  Future<void> removeGradeFile(String id) =>
      _api.delete('/api/v1/catalog/grade-files/$id');

  Future<Uint8List> attachmentBytes(String id) =>
      _api.bytes('/api/v1/attachments/$id/content');

  Future<void> removeAttachment(String id) =>
      _api.delete('/api/v1/attachments/$id');
}
