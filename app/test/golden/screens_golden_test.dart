@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';
import 'package:qadisiyah/features/auth/presentation/login_screen.dart';
import 'package:qadisiyah/features/home/presentation/home_screen.dart';

import '../helpers/test_app.dart';

/// اختبارات Flutter تعطّل الظلال افتراضيًا؛ نعيدها هنا لتطابق الصورة الجهاز.
Future<void> withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// صور مرجعية للشاشات المعتمدة للمراجعة البصرية مقابل ص4 وص5.
/// التحديث بعد تغيير مقصود: `flutter test --update-goldens --tags golden`.
void main() {
  const sizes = {
    'phone_390x844': referencePhone,
    'small_360x640': Size(360, 640),
    'tablet_800x1280': Size(800, 1280),
  };

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets(
      'login $name',
      (tester) => withShadows(() async {
        await pumpScreen(tester, const LoginScreen(), size: size);
        await expectLater(
          find.byType(LoginScreen),
          matchesGoldenFile('goldens/login_$name.png'),
        );
      }),
    );

    testWidgets(
      'home $name',
      (tester) => withShadows(() async {
        await pumpScreen(
          tester,
          const HomeScreen(),
          size: size,
          auth: FakeAuthRepository(
            restored: const ActiveSession(testUser, offline: false),
          ),
        );
        await expectLater(
          find.byType(HomeScreen),
          matchesGoldenFile('goldens/home_$name.png'),
        );
      }),
    );
  }

  testWidgets(
    'login with error message',
    (tester) => withShadows(() async {
      await pumpScreen(
        tester,
        const LoginScreen(
          initialMessage: 'اسم المستخدم أو كلمة المرور غير صحيحة',
        ),
      );
      await expectLater(
        find.byType(LoginScreen),
        matchesGoldenFile('goldens/login_error_phone_390x844.png'),
      );
    }),
  );
}
