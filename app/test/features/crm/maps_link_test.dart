import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/domain/maps_link.dart';

void main() {
  test('coordinates are read only when written in the link', () {
    expect(MapsLink.coordinates('https://maps.google.com/?q=30.2950,31.7420'), (
      30.295,
      31.742,
    ));
    expect(
      MapsLink.coordinates(
        'https://www.google.com/maps/place/X/@30.1,31.2,17z/data=!3m1!4b1!4m6!3m5!3d30.0444!4d31.2357',
      ),
      (30.0444, 31.2357),
    );
    expect(
      MapsLink.coordinates(
        'https://www.google.com/maps/search/?api=1&query=30.05%2C31.24',
      ),
      (30.05, 31.24),
    );
    expect(MapsLink.coordinates('https://www.google.com/maps/@29.9,31.1,15z'), (
      29.9,
      31.1,
    ));
    // الروابط المختصرة لا تحتوي إحداثيات: تُحفظ كما هي.
    expect(MapsLink.coordinates('https://maps.app.goo.gl/AbCdEf123'), isNull);
    expect(MapsLink.coordinates('https://maps.google.com/?q=95,31'), isNull);
  });

  test('only Google Maps links are accepted', () {
    expect(MapsLink.isGoogleMaps('https://maps.app.goo.gl/AbC'), isTrue);
    expect(
      MapsLink.isGoogleMaps('https://www.google.com.eg/maps/@1,2,3z'),
      isTrue,
    );
    expect(MapsLink.isGoogleMaps('https://google.evil.com/maps'), isFalse);
    expect(MapsLink.isGoogleMaps('javascript:alert(1)'), isFalse);
  });

  test('a link is built from coordinates or address when none was saved', () {
    expect(
      MapsLink.forLocation(lat: 30.1, lng: 31.2),
      'https://www.google.com/maps/search/?api=1&query=30.1,31.2',
    );
    expect(
      MapsLink.forLocation(address: 'العاشر من رمضان'),
      startsWith('https://www.google.com/maps/search/?api=1&query='),
    );
    expect(MapsLink.forLocation(), isNull);
  });
}
