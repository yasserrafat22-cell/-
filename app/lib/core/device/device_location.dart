import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message);

  final String message;
}

/// موقع الهاتف الحالي، بإذن المستخدم وعند الطلب فقط.
class DeviceLocation {
  const DeviceLocation();

  Future<(double, double)> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
        'شغّل خدمة الموقع (GPS) في الهاتف ثم أعد المحاولة',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException('لم يُسمح بالوصول إلى الموقع');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        'الوصول إلى الموقع مرفوض دائمًا. فعّله من إعدادات التطبيق في الهاتف',
      );
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return (p.latitude, p.longitude);
    } on Exception {
      throw const DeviceLocationException(
        'تعذر تحديد الموقع الآن. حاول في مكان مفتوح',
      );
    }
  }
}

final deviceLocationProvider = Provider<DeviceLocation>(
  (ref) => const DeviceLocation(),
);
