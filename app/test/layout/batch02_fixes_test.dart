import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/presentation/backup_actions.dart';
import 'package:qadisiyah/features/crm/presentation/crm_routes.dart';

import '../features/crm/crm_flow_test.dart' show pumpCrmApp;

/// صورتا الهاتف: حوار كلمة مرور النسخة مع لوحة المفاتيح، ورسالة الحفظ فوق شريط التنقل.
void main() {
  testWidgets('backup password dialog fits above the keyboard', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      askBackupPassword(context, title: 'نسخة احتياطية كاملة'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // لوحة مفاتيح الهاتف تأخذ نحو نصف الشاشة.
    t.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.byKey(const Key('backup.passwordAgain')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('backup.confirm')).hitTestable(),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('registration save hint stays above the system nav bar', (
    t,
  ) async {
    await pumpCrmApp(t, at: CrmRoutes.newCustomer);
    t.view
      ..physicalSize = const Size(390, 844) * 2
      ..devicePixelRatio = 2
      ..padding =
          const FakeViewPadding(bottom: 96) // 48dp أزرار التنقل
      ..viewPadding = const FakeViewPadding(bottom: 96);
    addTearDown(t.view.resetPadding);
    addTearDown(t.view.resetViewPadding);
    await t.pumpAndSettle();
    await t.drag(
      find.byKey(const Key('register.list')),
      const Offset(0, -6000),
    );
    await t.pumpAndSettle();
    final hint = t.getRect(find.byKey(const Key('register.missing')));
    expect(hint.bottom, lessThanOrEqualTo(844 - 48));
  });
}
