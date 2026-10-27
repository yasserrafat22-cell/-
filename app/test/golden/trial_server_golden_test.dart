@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/presentation/login_screen.dart';

import '../helpers/test_app.dart';
import 'screens_golden_test.dart' show withShadows;

/// شاشة الدخول في نسخة التجربة (Debug) مع شارة السيرفر ونافذة إعداده.
void main() {
  testWidgets(
    'login trial build',
    (tester) => withShadows(() async {
      await pumpScreen(tester, const LoginScreen(showServerSettings: true));
      await expectLater(
        find.byType(LoginScreen),
        matchesGoldenFile('goldens/login_trial_390x844.png'),
      );
    }),
  );

  testWidgets(
    'server settings dialog',
    (tester) => withShadows(() async {
      await pumpScreen(tester, const LoginScreen(showServerSettings: true));
      await tester.ensureVisible(find.byKey(const Key('trial.serverChip')));
      await tester.tap(find.byKey(const Key('trial.serverChip')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('trial.serverUrl')),
        'http://192.168.1.50:5080',
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/server_settings_390x844.png'),
      );
    }),
  );
}
