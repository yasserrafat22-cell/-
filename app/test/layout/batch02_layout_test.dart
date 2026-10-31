import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../features/crm/crm_flow_test.dart' show pumpCrmApp;
import '../helpers/crm_fakes.dart';

/// تفاصيل العميل (الملخص والموظفون) وبطاقات «السجل» بأسماء طويلة حقيقية،
/// على مقاسات هواتف مختلفة وتكبير خط النظام، بالخط الفعلي للتطبيق (Cairo).
///
/// صور المراجعة: `EXPORT_SCREENSHOTS=1 SHOT_TAG=after flutter test test/layout/batch02_layout_test.dart`
/// تُكتب في docs/batch02 ولا تُكتب أثناء CI.
const cases = <(String, Size, double)>[
  ('390x844_1.0', Size(390, 844), 1.0),
  ('360x780_1.3', Size(360, 780), 1.3),
  ('320x640_1.15', Size(320, 640), 1.15),
  ('412x915_1.0', Size(412, 915), 1.0),
  ('800x1280_1.0', Size(800, 1280), 1.0),
];

const longName = 'مصنع عبدالرحمن علي حسن للصناعات البلاستيكية والتعبئة';

PartyDetail ownerLikeCustomer() => const PartyDetail(
  number: 123,
  id: 'party-long',
  version: 3,
  name: longName,
  isCustomer: true,
  isSupplier: false,
  phones: [Phone(e164: '+201001234567', isPrimary: true)],
  interests: [
    Interest(
      spec: MaterialSpec(
        materialId: 'mat-pp',
        materialCode: 'PP',
        gradeId: 'g-pp500',
        gradeCode: 'PP500',
        manufacturerId: 'man-a',
        manufacturerName: 'مصنع تجريبي أ',
        precision: SpecPrecision.exact,
      ),
    ),
    Interest(
      spec: MaterialSpec(
        materialId: 'mat-pvc',
        materialCode: 'PVC',
        gradeId: 'g-sg5',
        gradeCode: 'SG-5',
        precision: SpecPrecision.unknownManufacturer,
      ),
    ),
  ],
  products: [],
  canEdit: true,
  canAdd: true,
  customerActivityId: 'act-factory',
  representativeId: 'rep-me',
  representativeName: 'أحمد محمد',
  governorateId: 'gov-cairo',
  region: 'المنطقة الصناعية الثالثة',
  email: 'purchasing.department@example.com',
  customerSummary: PartySummary(status: PartyStatus.needsFollowUp),
);

const ownerContacts = [
  PartyContact(
    id: 'c-1',
    name: 'مكرم الدالي عبدالفتاح',
    jobTitle: 'مدير مشتريات',
    mobile: '+201001234567',
    isPrimary: true,
  ),
  PartyContact(
    id: 'c-2',
    name: 'محمد أحمد السيد إبراهيم',
    jobTitle: 'مالك المصنع',
    mobile: '+201112223334',
  ),
];

FakeCrmRepository ownerLikeRepo() =>
    FakeCrmRepository(parties: [ownerLikeCustomer(), sampleCustomer()])
      ..contactList['party-long'] = [...ownerContacts];

/// يشغّل [body] مع جمع أخطاء الرسم (مثل RenderFlex overflow) بدل إيقاف الاختبار
/// عند أولها، ثم يعيد المعالج الأصلي قبل أي expect. يعيد الأخطاء والملاحظات.
Future<List<String>> capture(
  Future<void> Function(List<String> problems) body,
) async {
  final problems = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) =>
      problems.add(d.exceptionAsString().split('\n').first);
  try {
    await body(problems);
  } finally {
    FlutterError.onError = previous;
  }
  return problems;
}

Future<void> pumpAt(
  WidgetTester tester,
  String path,
  Size size,
  double scale, {
  FakeCrmRepository? crm,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await pumpCrmApp(tester, at: path, crm: crm ?? ownerLikeRepo());
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  await tester.pumpAndSettle();
}

/// صورة الشاشة الحالية للمراجعة (عند EXPORT_SCREENSHOTS=1 فقط).
Future<void> shot(WidgetTester tester, String name) async {
  if (Platform.environment['EXPORT_SCREENSHOTS'] != '1') return;
  final tag = Platform.environment['SHOT_TAG'] ?? 'after';
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final dir = Directory('../docs/batch02')..createSync(recursive: true);
  File('${dir.path}/${tag}_$name.png').writeAsBytesSync(bytes!);
}

/// النص يظهر بكامل ارتفاعه (لا قص صامت) ولا تنكسر كلمة واحدة لأكثر من سطر.
void checkReadable(List<String> problems, Finder text, String what) {
  final elements = text.evaluate().toList();
  if (elements.isEmpty) problems.add('$what غير ظاهر');
  for (final element in elements) {
    final box = element.renderObject! as RenderParagraph;
    if (box.didExceedMaxLines || box.size.height < box.textSize.height - 0.5) {
      problems.add('$what مقصوص');
    }
    final words = box.text.toPlainText().split(RegExp(r'\s+'));
    final longest = words.fold<double>(0, (w, word) {
      final p = TextPainter(
        text: TextSpan(text: word, style: box.text.style),
        textDirection: TextDirection.rtl,
        textScaler: box.textScaler,
      )..layout();
      return p.width > w ? p.width : w;
    });
    if (box.size.width + 0.5 < longest) {
      problems.add(
        '$what: عرضه ${box.size.width.toStringAsFixed(0)} وأطول كلمة تحتاج ${longest.toStringAsFixed(0)}',
      );
    }
  }
}

void main() {
  for (final (name, size, scale) in cases) {
    testWidgets('customer details summary: $name', (tester) async {
      final problems = await capture((problems) async {
        await pumpAt(tester, CrmRoutes.party('party-long'), size, scale);
        await shot(tester, 'details_top_$name');
        checkReadable(problems, find.text(longName), 'اسم العميل');
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        await shot(tester, 'details_mid_$name');
        // أزرار الشريط السفلي كاملة.
        for (final label in ['تعديل', 'حذف السجل']) {
          checkReadable(problems, find.text(label), 'زر $label');
        }
      });
      expect(problems, isEmpty);
    });

    testWidgets('customer details employees: $name', (tester) async {
      final problems = await capture((problems) async {
        await pumpAt(tester, CrmRoutes.party('party-long'), size, scale);
        // التبويب قد يكون تحت الشريط السفلي في الشاشات الصغيرة: يُفعّل مباشرة.
        tester.widget<InkWell>(find.byKey(const Key('tab.2'))).onTap!();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('contact.c-2')));
        await tester.pumpAndSettle();
        await shot(tester, 'employees_$name');
        checkReadable(
          problems,
          find.text('الموظفون وجهات الاتصال'),
          'عنوان الموظفين',
        );
        for (final c in ownerContacts) {
          checkReadable(problems, find.text(c.name), 'اسم ${c.name}');
          for (final k in ['call', 'whatsapp', 'delete']) {
            if (find.byKey(Key('contact.$k.${c.id}')).evaluate().isEmpty) {
              problems.add('زر $k لـ ${c.name} غير موجود');
            }
          }
        }
      });
      expect(problems, isEmpty);
    });

    testWidgets('registry customer cards: $name', (tester) async {
      final problems = await capture((problems) async {
        await pumpAt(tester, CrmRoutes.registry, size, scale);
        await shot(tester, 'registry_$name');
        checkReadable(problems, find.text(longName), 'اسم العميل في السجل');
        checkReadable(
          problems,
          find.text('لم يتم الطلب بعد'),
          '«لم يتم الطلب بعد»',
        );
      });
      expect(problems, isEmpty);
    });
  }
}
