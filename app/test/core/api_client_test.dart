import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/network/api_client.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';

import '../helpers/test_app.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final responses = <ResponseBody Function(RequestOptions)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add(options);
    if (responses.isEmpty) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return responses.removeAt(0)(options);
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

class _TokenAuth extends FakeAuthRepository {
  final forced = <bool>[];
  AuthException? refreshError;

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    forced.add(forceRefresh);
    if (forceRefresh && refreshError != null) throw refreshError!;
    return forceRefresh ? 'fresh' : 'stale';
  }
}

void main() {
  late _Adapter adapter;
  late _TokenAuth auth;
  late List<AuthFailure> ended;

  ApiClient client() => ApiClient(
    dio: Dio(BaseOptions(baseUrl: 'http://server'))
      ..httpClientAdapter = adapter,
    auth: auth,
    onSessionEnded: ended.add,
  );

  setUp(() {
    adapter = _Adapter();
    auth = _TokenAuth();
    ended = [];
  });

  test('sends the bearer token', () async {
    adapter.responses.add((_) => _json(200, {'ok': true}));
    expect(await client().get('/api/v1/reference'), {'ok': true});
    expect(adapter.requests.single.headers['Authorization'], 'Bearer stale');
  });

  test('a rejected token is refreshed once and the request retried', () async {
    adapter.responses
      ..add((_) => _json(401, {}))
      ..add((_) => _json(200, {'ok': true}));

    expect(await client().post('/api/v1/parties', {'a': 1}), {'ok': true});
    expect(auth.forced, [false, true]);
    expect(adapter.requests.last.headers['Authorization'], 'Bearer fresh');
    expect(adapter.requests.last.data, {'a': 1});
  });

  test('server errors keep their code, Arabic message and data', () async {
    adapter.responses.add(
      (_) => _json(409, {
        'code': 'party.duplicate_phone',
        'detail': 'رقم الهاتف مسجل بالفعل',
        'data': {'partyId': 'p1'},
      }),
    );
    await expectLater(
      client().post('/api/v1/parties', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'party.duplicate_phone')
            .having((e) => e.message, 'message', 'رقم الهاتف مسجل بالفعل')
            .having((e) => e.status, 'status', 409)
            .having((e) => (e.data! as Map)['partyId'], 'data', 'p1'),
      ),
    );
  });

  test('no connection is reported as a network error', () async {
    await expectLater(
      client().get('/api/v1/reference'),
      throwsA(
        isA<ApiException>().having((e) => e.isNetwork, 'network', isTrue),
      ),
    );
  });

  test('a revoked session ends the session in the app', () async {
    auth.refreshError = const AuthException(AuthFailure.deviceRevoked);
    adapter.responses.add((_) => _json(401, {}));

    await expectLater(
      client().get('/api/v1/reference'),
      throwsA(isA<ApiException>()),
    );
    expect(ended, [AuthFailure.deviceRevoked]);
  });
}
