import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/auth/domain/auth_repository.dart';
import 'package:qadisiyah/features/auth/presentation/login_screen.dart';
import 'package:qadisiyah/features/home/presentation/home_screen.dart';

import '../design_proposals/change_password_proposal_test.dart'
    show proposalStates;
import '../helpers/test_app.dart';

/// يصدّر صورًا عالية الدقة (3×) للمراجعة إلى docs/phase2/full.
/// التشغيل: `EXPORT_SCREENSHOTS=1 flutter test test/screenshots`
/// لا يعمل ضمن `flutter test` العادي حتى لا يكتب ملفات أثناء CI.
void main() {
  final skip = Platform.environment['EXPORT_SCREENSHOTS'] != '1';
  final outDir = Directory('../docs/phase2/full');

  Future<void> export(
    WidgetTester tester,
    Widget screen,
    String name, {
    FakeAuthRepository? auth,
  }) async {
    debugDisableShadows = false;
    try {
      await pumpScreen(tester, RepaintBoundary(child: screen), auth: auth);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      outDir.createSync(recursive: true);
      File('${outDir.path}/$name.png').writeAsBytesSync(bytes!);
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('export login', skip: skip, (tester) async {
    await export(tester, const LoginScreen(), 'app_login_1170x2532');
  });

  testWidgets('export home', skip: skip, (tester) async {
    await export(
      tester,
      const HomeScreen(),
      'app_home_1170x2532',
      auth: FakeAuthRepository(
        restored: const ActiveSession(testUser, offline: false),
      ),
    );
  });

  for (final MapEntry(key: name, value: screen) in proposalStates.entries) {
    testWidgets('export proposal $name', skip: skip, (tester) async {
      await export(
        tester,
        screen,
        'proposal_change_password_${name}_1170x2532',
      );
    });
  }
}
