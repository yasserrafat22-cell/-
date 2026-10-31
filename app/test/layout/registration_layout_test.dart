import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../features/crm/crm_flow_test.dart' show pumpCrmApp;

/// أحجام هواتف Android شائعة وتكبير الخط من إعدادات النظام.
const _cases = <(String, Size, double)>[
  ('390x844 خط 1.0', Size(390, 844), 1.0),
  ('360x780 خط 1.0', Size(360, 780), 1.0),
  ('360x780 خط 1.3', Size(360, 780), 1.3),
  ('320x640 خط 1.15', Size(320, 640), 1.15),
];

Future<void> _pump(WidgetTester tester, Size size, double scale) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await pumpCrmApp(tester, at: CrmRoutes.newCustomer);
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size, scale) in _cases) {
    testWidgets('registration layout: $name', (tester) async {
      await _pump(tester, size, scale);
      expect(tester.takeException(), isNull);

      // المحتوى يبدأ تحت الرأس لا تحته.
      final header = tester.getRect(find.text('تسجيل عميل'));
      final first = tester.getRect(find.byKey(const Key('register.name')));
      expect(first.top, greaterThan(header.bottom));

      // حقل الموبايل يتسع لـ 11 رقمًا كاملة.
      for (final key in ['register.phone', 'register.employee.0.phone']) {
        await tester.enterText(find.byKey(Key(key)), '01012345678');
        await tester.pumpAndSettle();
        final field = tester.renderObject<RenderBox>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(EditableText),
          ),
        );
        final painter = TextPainter(
          text: TextSpan(
            text: '01012345678',
            style: tester
                .widget<EditableText>(
                  find.descendant(
                    of: find.byKey(Key(key)),
                    matching: find.byType(EditableText),
                  ),
                )
                .style,
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout();
        expect(
          field.size.width,
          greaterThanOrEqualTo(painter.width),
          reason: '$key عرضه ${field.size.width} والرقم يحتاج ${painter.width}',
        );
      }

      // لا نص مقصوص بصمت: كل عنوان يظهر بكامل ارتفاعه داخل بطاقته.
      for (final label in [
        'مشاركة بيانات التواصل',
        'تعديل البيانات واستكمالها',
        'اسم الموظف الأساسي',
        'رقم الهاتف الأساسي',
        'الخامات الرئيسية',
      ]) {
        final text = find.text(label);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        final box = tester.renderObject<RenderParagraph>(text);
        expect(
          box.didExceedMaxLines || box.size.height < box.textSize.height - 0.5,
          isFalse,
          reason: 'النص «$label» مقصوص',
        );
      }

      // التمرير حتى آخر النموذج دون أي RenderFlex overflow.
      await tester.drag(
        find.byKey(const Key('register.list')),
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('register.discard')), findsOneWidget);
    });
  }
}
