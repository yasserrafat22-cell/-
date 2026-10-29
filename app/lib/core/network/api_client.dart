import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../features/auth/domain/auth_models.dart';
import '../../features/auth/domain/auth_repository.dart';

/// خطأ من السيرفر: كود ثابت (مثل `party.duplicate_phone`) ورسالة عربية
/// وبيانات إضافية اختيارية.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status, this.data});

  final String code;
  final String message;
  final int? status;
  final Object? data;

  static const network = ApiException(
    'network',
    'تعذر الاتصال بالسيرفر. تحقق من الاتصال ثم أعد المحاولة',
  );

  bool get isNetwork => code == 'network';

  @override
  String toString() => 'ApiException($code)';
}

/// يرسل طلبات الـ API برمز الدخول، ويجدده مرة واحدة عند رفضه. إذا انتهت
/// الجلسة يُبلغ [onSessionEnded] ليعيد التطبيق المستخدم لشاشة الدخول.
class ApiClient {
  ApiClient({
    required this._dio,
    required this._auth,
    required this._onSessionEnded,
  });

  final Dio _dio;
  final AuthRepository _auth;
  final void Function(AuthFailure reason) _onSessionEnded;

  Future<Object?> get(String path, {Map<String, Object?>? query}) =>
      _send('GET', path, query: query);

  Future<Object?> post(String path, Object? body) =>
      _send('POST', path, body: body);

  Future<Object?> put(String path, Object? body) =>
      _send('PUT', path, body: body);

  Future<Object?> delete(String path) => _send('DELETE', path);

  /// طلب POST يعيد ملفًا (مثل النسخة الاحتياطية الكاملة).
  Future<Uint8List> postBytes(String path, Object? body) async =>
      Uint8List.fromList(
        (await _send(
              'POST',
              path,
              body: body,
              responseType: ResponseType.bytes,
            ))!
            as List<int>,
      );

  /// إعادة إرسال عملية محفوظة على الجهاز (مزامنة) بنفس المسار والمحتوى.
  Future<Object?> send(String method, String path, Object? body) =>
      _send(method, path, body: body);

  /// محتوى ملف (مرفق) كبايتات، بنفس المصادقة.
  Future<Uint8List> bytes(String path) async => Uint8List.fromList(
    (await _send('GET', path, responseType: ResponseType.bytes))! as List<int>,
  );

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    ResponseType? responseType,
  }) async {
    Future<Response<Object?>> attempt({required bool forceRefresh}) async {
      final token = await _auth.accessToken(forceRefresh: forceRefresh);
      return _dio.request<Object?>(
        path,
        // نموذج الملفات لا يُرسل مرتين؛ إعادة المحاولة تستخدم نسخة منه.
        data: forceRefresh && body is FormData ? body.clone() : body,
        queryParameters: query?..removeWhere((_, v) => v == null),
        options: Options(
          method: method,
          headers: {'Authorization': 'Bearer $token'},
          responseType: responseType,
        ),
      );
    }

    try {
      try {
        return (await attempt(forceRefresh: false)).data;
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
        return (await attempt(forceRefresh: true)).data;
      }
    } on AuthException catch (e) {
      if (e.failure == AuthFailure.network) throw ApiException.network;
      if (e.endsSession) _onSessionEnded(e.failure);
      throw ApiException('auth', e.message);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  static ApiException _map(DioException e) {
    final response = e.response;
    if (response == null) return ApiException.network;
    var data = response.data;
    // طلبات الملفات تعيد الخطأ كبايتات؛ تُقرأ رسالة السيرفر منها.
    if (data is List<int>) {
      try {
        data = jsonDecode(utf8.decode(data));
      } on FormatException {
        data = null;
      }
    }
    if (data is Map) {
      return ApiException(
        data['code'] as String? ?? 'error',
        data['detail'] as String? ?? 'حدث خطأ غير متوقع',
        status: response.statusCode,
        data: data['data'],
      );
    }
    return ApiException(
      'error',
      response.statusCode == 403
          ? 'ليست لديك صلاحية لهذه العملية'
          : 'حدث خطأ في السيرفر. حاول مرة أخرى',
      status: response.statusCode,
    );
  }
}
