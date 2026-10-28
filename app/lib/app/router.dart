import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/crm/domain/crm_models.dart';
import '../features/crm/presentation/catalog_screen.dart';
import '../features/crm/presentation/crm_routes.dart';
import '../features/crm/presentation/edit_party_screen.dart';
import '../features/crm/presentation/new_contact_screen.dart';
import '../features/crm/presentation/new_record_screen.dart';
import '../features/crm/presentation/party_profile_screen.dart';
import '../features/crm/presentation/quick_add_party_screen.dart';
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
      GoRoute(
        path: CrmRoutes.catalog,
        builder: (context, state) => const CatalogScreen(),
      ),
      GoRoute(
        path: CrmRoutes.newCustomer,
        builder: (context, state) =>
            const QuickAddPartyScreen(isCustomer: true),
      ),
      GoRoute(
        path: CrmRoutes.newSupplier,
        builder: (context, state) =>
            const QuickAddPartyScreen(isCustomer: false),
      ),
      GoRoute(
        path: CrmRoutes.partyPattern,
        builder: (context, state) => PartyProfileScreen(
          partyId: state.pathParameters['id']!,
          asSupplier: roleFromQuery(state.uri.queryParameters['role']),
        ),
        routes: [
          GoRoute(
            path: 'order',
            builder: (context, state) => NewRecordScreen(
              partyId: state.pathParameters['id']!,
              supply: false,
            ),
          ),
          GoRoute(
            path: 'supply',
            builder: (context, state) => NewRecordScreen(
              partyId: state.pathParameters['id']!,
              supply: true,
            ),
          ),
          GoRoute(
            path: 'contact',
            builder: (context, state) => NewContactScreen(
              partyId: state.pathParameters['id']!,
              channel: ContactChannel.values
                  .where((c) => c.name == state.uri.queryParameters['channel'])
                  .firstOrNull,
            ),
          ),
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                EditPartyScreen(partyId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});
