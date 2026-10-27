import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class QadisiyahApp extends ConsumerWidget {
  const QadisiyahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'القادسية',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
