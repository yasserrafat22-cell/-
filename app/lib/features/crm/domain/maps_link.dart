/// روابط Google Maps: التحقق، واستخراج الإحداثيات إن كانت مكتوبة في الرابط،
/// وإنشاء رابط لموقع محفوظ. الروابط المختصرة (maps.app.goo.gl) لا تحتوي
/// إحداثيات، فتُحفظ كما هي دون أي طلب خارجي.
abstract final class MapsLink {
  static final _googleHost = RegExp(r'(^|\.)google\.[a-z]{2,3}(\.[a-z]{2})?$');

  static bool isGoogleMaps(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'goo.gl' ||
        host == 'maps.app.goo.gl' ||
        host == 'g.co' ||
        _googleHost.hasMatch(host);
  }

  static final _patterns = [
    // المكان نفسه في روابط /place/ (أدق من مركز الخريطة).
    RegExp(r'!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)'),
    RegExp(
      r'[?&](?:q|query|ll|destination|daddr|center)=(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)',
    ),
    RegExp(r'@(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)'),
    RegExp(r'^geo:(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)'),
  ];

  /// الإحداثيات إن وُجدت في الرابط، وإلا null.
  static (double, double)? coordinates(String url) {
    String text;
    try {
      text = Uri.decodeFull(url.trim());
    } on ArgumentError {
      text = url.trim();
    }
    for (final pattern in _patterns) {
      final m = pattern.firstMatch(text);
      if (m == null) continue;
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      if (valid(lat, lng)) return (lat!, lng!);
    }
    return null;
  }

  static bool valid(double? lat, double? lng) =>
      lat != null &&
      lng != null &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  /// رابط يُفتح أو يُشارك: الرابط الأصلي إن وُجد، ثم الإحداثيات، ثم العنوان.
  static String? forLocation({
    String? url,
    double? lat,
    double? lng,
    String? address,
  }) {
    if (url != null && url.isNotEmpty) return url;
    if (valid(lat, lng)) {
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
    if (address != null && address.trim().isNotEmpty) {
      return 'https://www.google.com/maps/search/?api=1&query='
          '${Uri.encodeQueryComponent(address.trim())}';
    }
    return null;
  }
}
