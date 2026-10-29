import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/theme/app_theme.dart';
import 'package:qadisiyah/core/widgets/qadisiyah_logo.dart';
import 'package:qadisiyah/features/auth/application/auth_controller.dart';
import 'package:qadisiyah/features/auth/domain/auth_models.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';

/// مقاس الموبايل المرجعي في المتطلبات.
const referencePhone = Size(390, 844);

bool _fontsLoaded = false;

/// يحمّل خط Cairo وأيقونات Material حتى تطابق صور الاختبار ما يظهر على الجهاز.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

const testUser = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000001',
  username: 'admin',
  displayName: 'مدير النظام',
  roles: ['system_admin'],
  // يرى الكل (ومنهم الموردون)؛ اختيار المسؤول والحذف تختبرها اختبارات الصلاحيات.
  permissions: {'users.manage', 'parties.view_all'},
  mustChangePassword: false,
);

/// مستخدم دخل بكلمة مرور مؤقتة.
const temporaryPasswordUser = AuthUser(
  id: '0192f0c0-0000-7000-8000-000000000002',
  username: 'rep1',
  displayName: 'مندوب',
  roles: ['representative'],
  permissions: {'customers.view'},
  mustChangePassword: true,
);

AuthSession sessionFor(AuthUser user) => AuthSession(
  user: user,
  tokens: AuthTokens(
    accessToken: 'access',
    accessTokenExpiresAt: DateTime(2030),
    refreshToken: 'refresh',
    refreshTokenExpiresAt: DateTime(2030),
  ),
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.restored = const NoSession(),
    this.loginFailure,
    this.loginUser = testUser,
    this.changePasswordError,
  });

  RestoredSession restored;
  AuthFailure? loginFailure;
  AuthUser loginUser;
  AuthException? changePasswordError;
  int logoutCalls = 0;
  String? lastUsername;
  (String, String)? lastPasswordChange;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    lastUsername = username;
    final failure = loginFailure;
    if (failure != null) throw AuthException(failure);
    return sessionFor(loginUser);
  }

  @override
  Future<AuthSession> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    lastPasswordChange = (currentPassword, newPassword);
    final error = changePasswordError;
    if (error != null) throw error;
    return sessionFor(
      AuthUser(
        id: loginUser.id,
        username: loginUser.username,
        displayName: loginUser.displayName,
        roles: loginUser.roles,
        permissions: loginUser.permissions,
        mustChangePassword: false,
      ),
    );
  }

  @override
  Future<RestoredSession> restoreSession() async => restored;

  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'access';

  @override
  Future<void> logout() async => logoutCalls++;
}

/// يضبط مقاس الشاشة ويحمّل الخطوط والشعار قبل عرض [child].
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  Size size = referencePhone,
  FakeAuthRepository? auth,
}) async {
  await loadAppFonts();
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    ),
  );
  await precacheLogo(tester);
}

Future<void> precacheLogo(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  await tester.runAsync(
    () => precacheImage(const AssetImage(QadisiyahLogo.assetPath), context),
  );
  await tester.pumpAndSettle();
}
