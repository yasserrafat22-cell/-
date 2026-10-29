import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/reminder_scheduler.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/application/auth_controller.dart';
import 'router.dart';

class QadisiyahApp extends ConsumerWidget {
  const QadisiyahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // تسجيل الخروج يلغي كل إشعارات المتابعة على هذا الجهاز.
    ref.listen(authControllerProvider, (previous, next) {
      if (previous is Authenticated && next is! Authenticated) {
        ref.read(reminderSchedulerProvider).clear();
      }
    });
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
