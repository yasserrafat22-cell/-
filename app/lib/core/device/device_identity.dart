import 'package:uuid/uuid.dart';

import '../storage/secure_store.dart';

/// معرف ثابت لكل تثبيت للتطبيق، يستخدمه السيرفر لربط الجلسات بالجهاز
/// وإلغاء صلاحيته عند الحاجة.
class DeviceIdentity {
  DeviceIdentity(this._store);

  final SecureStore _store;
  static const _key = 'device_id';

  String? _cached;

  Future<String> id() async {
    final cached = _cached;
    if (cached != null) return cached;
    var value = await _store.read(_key);
    if (value == null) {
      value = const Uuid().v7();
      await _store.write(_key, value);
    }
    return _cached = value;
  }
}
