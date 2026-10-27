import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/app/app.dart';
import 'package:qadisiyah/core/config/server_address.dart';
import 'package:qadisiyah/core/storage/secure_store.dart';
import 'package:qadisiyah/features/auth/application/auth_controller.dart';
import 'package:qadisiyah/features/auth/presentation/server_settings.dart';

import '../../helpers/test_app.dart';

void main() {
  late InMemorySecureStore store;
  late ProviderContainer container;
  final checked = <String>[];

  Future<void> pumpApp(WidgetTester tester, {bool reachable = true}) async {
    await loadAppFonts();
    tester.view
      ..physicalSize = referencePhone * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    store = InMemorySecureStore();
    checked.clear();
    container = ProviderContainer(
      overrides: [
        serverAddressStoreProvider.overrideWithValue(store),
        serverHealthCheckProvider.overrideWithValue((url) async {
          checked.add(url);
          return reachable;
        }),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const QadisiyahApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('trial.serverChip')));
    await tester.tap(find.byKey(const Key('trial.serverChip')));
    await tester.pumpAndSettle();
  }

  testWidgets('trial build shows the server chip on login', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('نسخة تجريبية'), findsOneWidget);
  });

  testWidgets('invalid address is rejected and not saved', (tester) async {
    await pumpApp(tester);
    await openDialog(tester);
    await tester.enterText(
      find.byKey(const Key('trial.serverUrl')),
      '192.168.1.50',
    );
    await tester.tap(find.byKey(const Key('trial.saveServer')));
    await tester.pumpAndSettle();

    expect(find.textContaining('العنوان غير صحيح'), findsOneWidget);
    expect(store.values, isEmpty);
  });

  testWidgets('connection test reports the result', (tester) async {
    await pumpApp(tester, reachable: false);
    await openDialog(tester);
    await tester.enterText(
      find.byKey(const Key('trial.serverUrl')),
      'http://192.168.1.50:5080',
    );
    await tester.tap(find.byKey(const Key('trial.testServer')));
    await tester.pumpAndSettle();

    expect(checked, ['http://192.168.1.50:5080']);
    expect(find.textContaining('تعذر الوصول للسيرفر'), findsOneWidget);
  });

  testWidgets('saving updates the API client and survives restart', (
    tester,
  ) async {
    await pumpApp(tester);
    await openDialog(tester);
    await tester.enterText(
      find.byKey(const Key('trial.serverUrl')),
      'http://192.168.1.50:5080/',
    );
    await tester.tap(find.byKey(const Key('trial.saveServer')));
    await tester.pumpAndSettle();

    expect(
      container.read(dioProvider).options.baseUrl,
      'http://192.168.1.50:5080',
    );
    expect(find.textContaining('http://192.168.1.50:5080'), findsOneWidget);
    expect(await ServerAddress.load(store), 'http://192.168.1.50:5080');
  });
}
