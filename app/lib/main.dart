import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/server_address.dart';
import 'core/storage/secure_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const store = FlutterSecureStore();
  final serverUrl = await ServerAddress.load(store);
  runApp(
    ProviderScope(
      overrides: [
        initialServerUrlProvider.overrideWithValue(serverUrl),
        serverAddressStoreProvider.overrideWithValue(store),
      ],
      child: const QadisiyahApp(),
    ),
  );
}
