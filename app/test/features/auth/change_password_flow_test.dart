import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/app/app.dart';
import 'package:qadisiyah/features/auth/application/auth_controller.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';
import 'package:qadisiyah/features/auth/presentation/change_password_screen.dart';
import 'package:qadisiyah/features/auth/presentation/login_screen.dart';
import 'package:qadisiyah/features/home/presentation/home_screen.dart';

import '../../helpers/test_app.dart';

Future<void> pumpApp(WidgetTester tester, FakeAuthRepository auth) async {
  await loadAppFonts();
  tester.view
    ..physicalSize = referencePhone * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const QadisiyahApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> loginWithTemporaryPassword(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login.username')), 'rep1');
  await tester.enterText(find.byKey(const Key('login.password')), 'Temp1234');
  await tester.tap(find.byKey(const Key('login.submit')));
  await tester.pumpAndSettle();
}

Future<void> fill(
  WidgetTester tester, {
  String current = 'Temp1234',
  String next = 'Valid2026',
  String? confirm,
}) async {
  await tester.enterText(
    find.byKey(const Key('changePassword.current')),
    current,
  );
  await tester.enterText(find.byKey(const Key('changePassword.new')), next);
  await tester.enterText(
    find.byKey(const Key('changePassword.confirm')),
    confirm ?? next,
  );
  await tester.pump();
}

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('changePassword.submit')));
  await tester.tap(find.byKey(const Key('changePassword.submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('temporary password login lands on change password, not home', (
    tester,
  ) async {
    await pumpApp(tester, FakeAuthRepository(loginUser: temporaryPasswordUser));
    await loginWithTemporaryPassword(tester);

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('restored session that must change password is forced too', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeAuthRepository(
        restored: const ActiveSession(temporaryPasswordUser, offline: false),
      ),
    );
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('rules update while typing', (tester) async {
    await pumpApp(tester, FakeAuthRepository(loginUser: temporaryPasswordUser));
    await loginWithTemporaryPassword(tester);

    expect(
      find.byKey(const Key('changePassword.rule.minLength.pending')),
      findsOneWidget,
    );
    await fill(tester, next: 'abc', confirm: 'abd');
    expect(
      find.byKey(const Key('changePassword.rule.minLength.false')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('changePassword.rule.matchesConfirmation.false')),
      findsOneWidget,
    );

    await fill(tester);
    for (final rule in [
      'minLength',
      'lettersAndDigits',
      'differsFromCurrent',
      'matchesConfirmation',
    ]) {
      expect(find.byKey(Key('changePassword.rule.$rule.true')), findsOneWidget);
    }
  });

  testWidgets('invalid input is blocked before contacting the server', (
    tester,
  ) async {
    final auth = FakeAuthRepository(loginUser: temporaryPasswordUser);
    await pumpApp(tester, auth);
    await loginWithTemporaryPassword(tester);

    await submit(tester);
    expect(find.text('أكمل جميع الحقول'), findsOneWidget);

    await fill(tester, confirm: 'Different2026');
    await submit(tester);
    expect(find.text('كلمة المرور الجديدة لا تحقق كل الشروط'), findsOneWidget);
    expect(auth.lastPasswordChange, isNull);
  });

  testWidgets('wrong current password shows the server error', (tester) async {
    final auth = FakeAuthRepository(
      loginUser: temporaryPasswordUser,
      changePasswordError: const AuthException(
        AuthFailure.wrongCurrentPassword,
      ),
    );
    await pumpApp(tester, auth);
    await loginWithTemporaryPassword(tester);

    await fill(tester);
    await submit(tester);

    expect(find.text('كلمة المرور الحالية غير صحيحة'), findsOneWidget);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('server rejection detail is shown as is', (tester) async {
    await pumpApp(
      tester,
      FakeAuthRepository(
        loginUser: temporaryPasswordUser,
        changePasswordError: const AuthException(
          AuthFailure.weakPassword,
          detail: 'كلمة المرور الجديدة يجب أن تختلف عن الحالية',
        ),
      ),
    );
    await loginWithTemporaryPassword(tester);
    await fill(tester);
    await submit(tester);
    expect(
      find.text('كلمة المرور الجديدة يجب أن تختلف عن الحالية'),
      findsOneWidget,
    );
  });

  testWidgets('revoked device during change returns to login with reason', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeAuthRepository(
        loginUser: temporaryPasswordUser,
        changePasswordError: const AuthException(AuthFailure.deviceRevoked),
      ),
    );
    await loginWithTemporaryPassword(tester);
    await fill(tester);
    await submit(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(AuthFailure.deviceRevoked.message), findsOneWidget);
  });

  testWidgets('successful change opens home with the new session', (
    tester,
  ) async {
    final auth = FakeAuthRepository(loginUser: temporaryPasswordUser);
    await pumpApp(tester, auth);
    await loginWithTemporaryPassword(tester);

    await fill(tester);
    await submit(tester);

    expect(auth.lastPasswordChange, ('Temp1234', 'Valid2026'));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('logout from the change screen returns to login', (tester) async {
    final auth = FakeAuthRepository(loginUser: temporaryPasswordUser);
    await pumpApp(tester, auth);
    await loginWithTemporaryPassword(tester);

    await tester.ensureVisible(find.byKey(const Key('changePassword.logout')));
    await tester.tap(find.byKey(const Key('changePassword.logout')));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(auth.logoutCalls, 1);
  });

  testWidgets('each field toggles its own visibility', (tester) async {
    await pumpApp(tester, FakeAuthRepository(loginUser: temporaryPasswordUser));
    await loginWithTemporaryPassword(tester);

    bool obscured(String key) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(Key('changePassword.$key')),
            matching: find.byType(EditableText),
          ),
        )
        .obscureText;

    await tester.tap(find.byKey(const Key('changePassword.new.toggle')));
    await tester.pump();
    expect(obscured('new'), isFalse);
    expect(obscured('current'), isTrue);
    expect(obscured('confirm'), isTrue);
  });
}
