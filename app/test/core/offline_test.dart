import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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

class _Auth extends FakeAuthRepository {
  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'token';
}

void main() {
  late _Server server;
  late OfflineStore store;
  late MemoryBlobStorage blob;
  late InMemorySecureStore keys;

  CrmRepository repo({String user = 'user-1'}) => CrmRepository(
    ApiClient(
      dio: Dio(BaseOptions(baseUrl: 'http://server'))
        ..httpClientAdapter = server,
      auth: _Auth(),
      onSessionEnded: (_) {},
    ),
    offline: store,
    userId: user,
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
}
