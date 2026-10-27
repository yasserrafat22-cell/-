import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/home/presentation/home_screen.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const changePassword = '/change-password';
  static const home = '/';
}

/// يربط المسارات بحالة الدخول: لا يمكن الوصول لأي شاشة داخلية دون جلسة.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref
    ..listen(authControllerProvider, (_, next) => refresh.value = next)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = refresh.value;
      final location = state.matchedLocation;
      return switch (auth) {
        AuthRestoring() => location == Routes.splash ? null : Routes.splash,
        Unauthenticated() => location == Routes.login ? null : Routes.login,
        // كلمة مرور مؤقتة: لا وصول لأي شاشة أخرى قبل تغييرها.
        Authenticated(:final user) when user.mustChangePassword =>
          location == Routes.changePassword ? null : Routes.changePassword,
        Authenticated() =>
          location == Routes.login ||
                  location == Routes.splash ||
                  location == Routes.changePassword
              ? Routes.home
              : null,
      };
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) {
          final auth = refresh.value;
          return LoginScreen(
            initialMessage: auth is Unauthenticated
                ? auth.reason?.message
                : null,
            showServerSettings: AppConfig.isTrialBuild,
          );
        },
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});
