import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../golden/crm_golden_test.dart' show crmScreenStates, pumpCrmScreen;

/// يصدّر صور شاشات العملاء والموردين الحالية (3×) إلى docs/phase4/full للمراجعة.
/// التشغيل: `EXPORT_SCREENSHOTS=1 flutter test test/screenshots`
void main() {
  final skip = Platform.environment['EXPORT_SCREENSHOTS'] != '1';
  final outDir = Directory('../docs/phase4/full');

  for (final MapEntry(key: name, value: (path, prepare))
      in crmScreenStates.entries) {
    testWidgets('export $name', skip: skip, (tester) async {
      debugDisableShadows = false;
      try {
        await pumpCrmScreen(tester, path, prepare: prepare);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first,
        );
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data!.buffer.asUint8List();
        });
        outDir.createSync(recursive: true);
        File('${outDir.path}/app_${name}_1170x2532.png')
            .writeAsBytesSync(bytes!);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
