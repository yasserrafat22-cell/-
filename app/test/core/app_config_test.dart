import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/config/app_config.dart';

void main() {
  group('server address validation', () {
    test('trial build accepts local HTTP addresses', () {
      for (final url in [
        'http://192.168.1.50:5080',
        'http://10.0.2.2:5080/',
        'https://trial.example.com',
      ]) {
        expect(
          AppConfig.validateServerUrl(url, trial: true),
          isNull,
          reason: url,
        );
      }
    });

    test('release build accepts HTTPS only', () {
      expect(
        AppConfig.validateServerUrl('http://192.168.1.50:5080', trial: false),
        isNotNull,
      );
      expect(
        AppConfig.validateServerUrl('https://api.example.com', trial: false),
        isNull,
      );
    });

    test('rejects malformed addresses', () {
      for (final url in [
        '',
        '192.168.1.50:5080',
        'ftp://192.168.1.50',
        'http://192.168.1.50:5080/api',
        'http://',
      ]) {
        expect(
          AppConfig.validateServerUrl(url, trial: true),
          isNotNull,
          reason: url,
        );
      }
    });

    test('normalizes trailing slash', () {
      expect(
        AppConfig.normalizeServerUrl(' http://192.168.1.50:5080/ '),
        'http://192.168.1.50:5080',
      );
    });
  });

  group('Android network security', () {
    String read(String variant) =>
        File('android/app/src/$variant/res/xml/network_security_config.xml')
            .readAsStringSync();

    test('release (main) forbids cleartext traffic', () {
      expect(read('main'), contains('cleartextTrafficPermitted="false"'));
      expect(read('main'), isNot(contains('cleartextTrafficPermitted="true"')));
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
    });

    test('only the debug variant allows cleartext', () {
      expect(read('debug'), contains('cleartextTrafficPermitted="true"'));
      expect(
        Directory('android/app/src/profile/res').existsSync(),
        isFalse,
        reason: 'profile must use the main (HTTPS-only) config',
      );
      for (final manifest in ['main', 'debug', 'profile']) {
        expect(
          File('android/app/src/$manifest/AndroidManifest.xml')
              .readAsStringSync(),
          isNot(contains('usesCleartextTraffic')),
          reason: manifest,
        );
      }
    });
  });
}
