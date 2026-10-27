@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/auth/presentation/change_password_screen.dart';

import '../helpers/test_app.dart';
import 'screens_golden_test.dart' show withShadows;

/// حالات الشاشة المنفذة، لمقارنتها بالتصميم المعتمد
/// (`test/design_proposals/goldens`).
final changePasswordStates =
    <String, (FakeAuthRepository, Future<void> Function(WidgetTester))>{
      'empty': (FakeAuthRepository(), (_) async {}),
      'validating': (
        FakeAuthRepository(),
        (tester) async {
          await _fill(tester, confirm: 'Valid2027');
        },
      ),
      'error': (
        FakeAuthRepository(
          changePasswordError: const AuthException(
            AuthFailure.wrongCurrentPassword,
          ),
        ),
        (tester) async {
          await _fill(tester);
          await tester.ensureVisible(
            find.byKey(const Key('changePassword.submit')),
          );
          await tester.tap(find.byKey(const Key('changePassword.submit')));
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, 400),
          );
          await tester.pumpAndSettle();
        },
      ),
    };

Future<void> _fill(WidgetTester tester, {String? confirm}) async {
  await tester.enterText(
    find.byKey(const Key('changePassword.current')),
    'Temp1234',
  );
  await tester.enterText(
    find.byKey(const Key('changePassword.new')),
    'Valid2026',
  );
  await tester.enterText(
    find.byKey(const Key('changePassword.confirm')),
    confirm ?? 'Valid2026',
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final MapEntry(key: name, value: (auth, prepare))
      in changePasswordStates.entries) {
    testWidgets(
      'change password $name',
      (tester) => withShadows(() async {
        await pumpScreen(tester, const ChangePasswordScreen(), auth: auth);
        await prepare(tester);
        await expectLater(
          find.byType(ChangePasswordScreen),
          matchesGoldenFile('goldens/change_password_${name}_390x844.png'),
        );
      }),
    );
  }
}
