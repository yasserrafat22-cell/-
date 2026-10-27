import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/app/app.dart';
import 'package:qadisiyah/features/auth/application/auth_controller.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';
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

void main() {
  testWidgets('app opens on login when there is no stored session', (
    tester,
  ) async {
    await pumpApp(tester, FakeAuthRepository());
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('app opens on home when a session is restored', (tester) async {
    await pumpApp(
      tester,
      FakeAuthRepository(
        restored: const ActiveSession(testUser, offline: false),
      ),
    );
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('offline restored session shows the offline notice', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeAuthRepository(
        restored: const ActiveSession(testUser, offline: true),
      ),
    );
    expect(find.text('تعمل دون اتصال بالسيرفر'), findsOneWidget);
  });

  testWidgets('revoked device lands on login with the reason', (tester) async {
    await pumpApp(
      tester,
      FakeAuthRepository(restored: const NoSession(AuthFailure.deviceRevoked)),
    );
    expect(find.text(AuthFailure.deviceRevoked.message), findsOneWidget);
  });

  testWidgets('empty fields show validation and do not call the server', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth);

    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();

    expect(find.text('أدخل اسم المستخدم'), findsOneWidget);
    expect(find.text('أدخل كلمة المرور'), findsOneWidget);
    expect(auth.lastUsername, isNull);
  });

  testWidgets('wrong credentials show the error and stay on login', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      loginFailure: AuthFailure.invalidCredentials,
    );
    await pumpApp(tester, auth);

    await tester.enterText(find.byKey(const Key('login.username')), 'admin');
    await tester.enterText(find.byKey(const Key('login.password')), 'wrong');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();

    expect(find.text(AuthFailure.invalidCredentials.message), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('successful login navigates home and logout returns', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth);

    await tester.enterText(find.byKey(const Key('login.username')), 'admin');
    await tester.enterText(find.byKey(const Key('login.password')), 'secret');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    for (final section in HomeSection.values) {
      expect(find.byKey(Key('home.${section.name}')), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('home.logout')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(auth.logoutCalls, 1);
  });

  testWidgets('password visibility toggles', (tester) async {
    await pumpApp(tester, FakeAuthRepository());

    EditableText passwordField() => tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('login.password')),
        matching: find.byType(EditableText),
      ),
    );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byKey(const Key('login.togglePassword')));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('forgot password explains admin reset', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pumpAndSettle();
    expect(find.textContaining('مدير النظام'), findsOneWidget);
  });
}
