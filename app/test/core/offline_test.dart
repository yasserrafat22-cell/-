import 'dart:convert';
import 'dart:typed_data';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:qadisiyah/core/device/file_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/core/offline/offline_store.dart';
import 'package:qadisiyah/core/storage/secure_store.dart';
import 'package:qadisiyah/features/crm/data/crm_repository.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';

import '../helpers/test_app.dart';

/// سيرفر وهمي: كل طلب يُرد بالدالة المسجلة له، أو انقطاع اتصال إن كان [online] خطأ.
class _Server implements HttpClientAdapter {
  bool online = true;
  final requests = <String>[];
  ResponseBody Function(RequestOptions) handler = (_) =>
      _json(200, <String, Object?>{});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    if (!online) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    requests.add('${options.method} ${options.path}');
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// نسخ الملفات المنتظرة في مجلد مؤقت للاختبار.
class _Files extends FileServices {
  _Files(this.dir);

  final Directory dir;

  @override
  Future<String> keepForUpload(String path, String id) async =>
      (await File(path).copy('${dir.path}/$id')).path;

  @override
  Future<void> discardUpload(String path) async => File(path).deleteSync();
}

class _Auth extends FakeAuthRepository {
  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'token';
}

void main() {
  late _Server server;
  late OfflineStore store;
  late MemoryBlobStorage blob;
  late InMemorySecureStore keys;
  late _Files files;

  CrmRepository repo({String user = 'user-1'}) => CrmRepository(
    ApiClient(
      dio: Dio(BaseOptions(baseUrl: 'http://server'))
        ..httpClientAdapter = server,
      auth: _Auth(),
      onSessionEnded: (_) {},
    ),
    offline: store,
    userId: user,
    files: files,
  );

  const customer = NewParty(
    id: 'p-new',
    name: 'مصنع الأمل',
    phone: '01009876543',
    isCustomer: true,
    activityId: 'act-factory',
  );

  setUp(() {
    server = _Server();
    blob = MemoryBlobStorage();
    keys = InMemorySecureStore();
    store = OfflineStore(keys: keys, storage: blob);
    files = _Files(Directory.systemTemp.createTempSync('uploads'));
  });

  test('the local database is encrypted and survives a restart', () async {
    server.online = false;
    await repo().createParty(customer);

    final raw = utf8.decode(blob.bytes!, allowMalformed: true);
    expect(raw, isNot(contains('مصنع الأمل')));
    expect(raw, isNot(contains('01009876543')));

    final reopened = OfflineStore(keys: keys, storage: blob);
    expect((await reopened.ops('user-1')).single.label, contains('مصنع الأمل'));
    // مفتاح مختلف (مثل جهاز آخر) لا يقرأ شيئًا ولا ينهار.
    final stranger = OfflineStore(keys: InMemorySecureStore(), storage: blob);
    expect(await stranger.ops('user-1'), isEmpty);
  });

  test('without a connection a new customer is saved on the device and shown '
      'in the registry', () async {
    server.online = false;
    final crm = repo();
    final local = await crm.createParty(customer);
    expect(local!.name, 'مصنع الأمل');
    expect(local.phones.single.e164, '+201009876543');
    expect((await crm.party('p-new')).id, 'p-new');
    expect(await crm.locations('p-new'), isEmpty);

    // عمليات نفس السجل تنتظر بعده حتى لو عاد الاتصال.
    server.online = true;
    await crm.addContact(
      'p-new',
      const PartyContact(id: 'c-1', name: 'م. سامي', mobile: '01112345678'),
    );
    expect(server.requests, isEmpty);
    expect((await crm.pendingOps()).map((o) => o.path), [
      '/api/v1/parties',
      '/api/v1/parties/p-new/contacts',
    ]);
    // بيانات مستخدم آخر على نفس الجهاز منفصلة.
    expect(await repo(user: 'user-2').pendingOps(), isEmpty);
  });

  test('sync sends the saved operations in order, once', () async {
    server.online = false;
    final crm = repo();
    await crm.createParty(customer);
    await crm.addContact('p-new', const PartyContact(id: 'c-1', name: 'سامي'));

    server
      ..online = true
      ..handler = (o) =>
          _json(o.path == '/api/v1/parties' ? 201 : 200, {'id': 'p-new'});
    final result = await crm.syncPending();
    expect(result.sent, 2);
    expect(server.requests, [
      'POST /api/v1/parties',
      'POST /api/v1/parties/p-new/contacts',
    ]);
    expect(await crm.pendingOps(), isEmpty);

    await crm.syncPending();
    expect(server.requests, hasLength(2));
  });

  test(
    'a rejected operation needs review and holds the rest of that record',
    () async {
      server.online = false;
      final crm = repo();
      await crm.createParty(customer);
      await crm.addContact(
        'p-new',
        const PartyContact(id: 'c-1', name: 'سامي'),
      );

      server
        ..online = true
        ..handler = (_) => _json(409, {
          'code': 'party.duplicate_phone_hidden',
          'detail': 'رقم الهاتف مسجل بالفعل في النظام',
        });
      final result = await crm.syncPending();
      expect(result.sent, 0);
      expect(result.needsReview, 1);
      final ops = await crm.pendingOps();
      expect(ops.first.status, PendingStatus.needsReview);
      expect(ops.first.error, 'رقم الهاتف مسجل بالفعل في النظام');
      expect(ops.last.status, PendingStatus.pending);
      expect(server.requests, ['POST /api/v1/parties']);

      await crm.discardOp(ops.last);
      await crm.discardOp(ops.first);
      expect(await crm.pendingOps(), isEmpty);
    },
  );

  test('a lost connection during sync keeps the operation for later', () async {
    server.online = false;
    final crm = repo();
    await crm.createParty(customer);
    final result = await crm.syncPending();
    expect(result.sent, 0);
    expect((await crm.pendingOps()).single.status, PendingStatus.pending);
  });

  test(
    'screens viewed before show their last copy without a connection',
    () async {
      server.handler = (_) => _json(200, [
        {
          'id': 'l-1',
          'partyId': 'p-1',
          'kind': 'factory',
          'addressLine': 'العاشر من رمضان',
          'isDefault': true,
          'version': 1,
        },
      ]);
      final crm = repo();
      expect(
        (await crm.locations('p-1')).single.addressLine,
        'العاشر من رمضان',
      );
      server.online = false;
      expect(
        (await crm.locations('p-1')).single.addressLine,
        'العاشر من رمضان',
      );
      await expectLater(
        crm.locations('p-other'),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'network', true),
        ),
      );
    },
  );

  test('device data backup is encrypted, restores only for its owner and '
      'never duplicates', () async {
    server.online = false;
    await repo().createParty(customer);
    final file = await repo().deviceBackup('Device-Secret-1');
    expect(
      utf8.decode(file, allowMalformed: true),
      isNot(contains('مصنع الأمل')),
    );

    // جهاز جديد (قاعدة فارغة) لنفس المستخدم.
    store = OfflineStore(
      keys: InMemorySecureStore(),
      storage: MemoryBlobStorage(),
    );
    await expectLater(
      repo().importDeviceBackup(file, 'wrong-password'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      repo(user: 'user-2').importDeviceBackup(file, 'Device-Secret-1'),
      throwsA(isA<FormatException>()),
    );
    expect(await repo().importDeviceBackup(file, 'Device-Secret-1'), 1);
    expect(await repo().importDeviceBackup(file, 'Device-Secret-1'), 0);
    expect((await repo().pendingOps()).single.label, contains('مصنع الأمل'));
  });

  test('a record no longer allowed is removed from the device copy', () async {
    server.handler = (_) => _json(200, [
      {'id': 'l-1', 'partyId': 'p-1', 'kind': 'factory', 'version': 1},
    ]);
    final crm = repo();
    await crm.locations('p-1');
    // سُحبت الصلاحية: السيرفر يعيد 404، فتُحذف النسخة المحلية.
    server.handler = (_) =>
        _json(404, {'code': 'not_found', 'detail': 'غير موجود'});
    await expectLater(crm.locations('p-1'), throwsA(isA<ApiException>()));
    server.online = false;
    await expectLater(
      crm.locations('p-1'),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)),
    );
  });

  Json bundle() => {
    'materials': [
      {'id': 'mat-pp', 'code': 'PP', 'nameAr': 'بولي بروبلين', 'grades': []},
    ],
    'manufacturers': [],
    'units': [],
    'activityTypes': [],
    'contactOutcomes': [],
    'governorates': [],
    'countries': [],
    'representatives': [],
    'lookups': [],
  };

  test('a material, manufacturer and grade added offline are usable at once '
      'and sent in order', () async {
    server.handler = (_) => _json(200, bundle());
    final crm = repo();
    await crm.reference();
    server.online = false;
    final abs = await crm.createMaterialType('abs', nameAr: 'إيه بي إس');
    final maker = await crm.createManufacturer('سابك');
    final grade = await crm.createGrade(
      materialId: abs.id,
      manufacturerId: maker.id,
      code: '500P',
    );
    final refs = await crm.reference();
    expect(refs.material(abs.id)!.code, 'ABS');
    expect(refs.grade(grade.id)!.code, '500P');
    expect(refs.manufacturer(maker.id)!.name, 'سابك');

    // عاد الاتصال: إضافة الـ Grade لعميل تنتظر خلف إضافته للكتالوج.
    server.online = true;
    await crm.addInterest(
      'party-1',
      SpecChoice(materialId: abs.id, gradeId: grade.id),
    );
    expect(server.requests, ['GET /api/v1/reference']);

    server.handler = (o) => _json(201, {'id': (o.data as Map)['id']});
    final result = await crm.syncPending();
    expect(result.sent, 4);
    expect(server.requests.skip(1), [
      'POST /api/v1/catalog/materials',
      'POST /api/v1/catalog/manufacturers',
      'POST /api/v1/catalog/grades',
      'POST /api/v1/parties/party-1/interests',
    ]);
  });

  test(
    'the same grade added on two devices is linked, not duplicated',
    () async {
      server.online = false;
      final crm = repo();
      final grade = await crm.createGrade(
        materialId: 'mat-pp',
        manufacturerId: 'man-a',
        code: '500P',
      );
      await crm.addInterest(
        'party-1',
        SpecChoice(materialId: 'mat-pp', gradeId: grade.id),
      );
      server
        ..online = true
        ..handler = (o) => o.path.endsWith('/grades')
            ? _json(200, {'id': 'g-existing-on-server'})
            : _json(200, {'ok': true});
      final sentBodies = <Object?>[];
      final inner = server.handler;
      server.handler = (o) {
        sentBodies.add(o.data);
        return inner(o);
      };
      await crm.syncPending();
      expect(await crm.pendingOps(), isEmpty);
      expect((sentBodies.last as Map)['gradeId'], 'g-existing-on-server');
    },
  );

  test(
    'a grade photo picked offline waits in the queue and uploads later',
    () async {
      final source = File('${files.dir.path}/photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      server.online = false;
      final crm = repo();
      await crm.uploadGradeFile(
        gradeId: 'g-1',
        id: 'file-1',
        kind: 'photo',
        filePath: source.path,
        fileName: 'photo.jpg',
      );
      source.deleteSync(); // ملف المعرض المؤقت قد يُحذف؛ النسخة المحفوظة تبقى.
      final op = (await crm.pendingOps()).single;
      expect(
        File(((op.body! as Map)['upload'] as Map)['path'] as String)
            .existsSync(),
        isTrue,
      );

      server.online = true;
      String? contentType;
      server.handler = (o) {
        contentType = o.contentType;
        return _json(201, {'id': 'file-1'});
      };
      expect((await crm.syncPending()).sent, 1);
      expect(contentType, startsWith('multipart/form-data'));
      expect(files.dir.listSync().whereType<File>(), isEmpty);
    },
  );

  test('a grade rejected as similar can be confirmed from review', () async {
    server.online = false;
    final crm = repo();
    await crm.createGrade(
      materialId: 'mat-pp',
      manufacturerId: 'man-a',
      code: '129H',
    );
    server
      ..online = true
      ..handler = (o) => (o.data as Map)['confirmSimilar'] == true
          ? _json(201, {'id': (o.data as Map)['id']})
          : _json(409, {
              'code': 'catalog.similar_grade',
              'detail': 'يوجد Grade بنفس الكود',
            });
    await crm.syncPending();
    final op = (await crm.pendingOps()).single;
    expect(op.errorCode, 'catalog.similar_grade');
    await crm.retryOp(op, confirmSimilar: true);
    expect((await crm.syncPending()).sent, 1);
    expect(await crm.pendingOps(), isEmpty);
  });
}
