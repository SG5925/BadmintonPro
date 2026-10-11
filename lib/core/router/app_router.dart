import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/dashboard/presentation/coach_dashboard_screen.dart';
import '../../features/dashboard/presentation/student_dashboard_screen.dart';
import '../../features/developer/presentation/developer_panel_screen.dart';
import '../../features/guests/presentation/guest_view_screen.dart';
import '../../shared/models/user_role.dart';
import 'app_routes.dart';
import 'route_guard.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever the profile or login progress changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(currentUserProvider, (_, _) => refresh.value++);
  ref.listen(loginInProgressProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      location: state.matchedLocation,
      user: ref.read(currentUserProvider),
      loginInProgress: ref.read(loginInProgressProvider),
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
        routes: [
          for (final role in UserRole.values)
            GoRoute(
              path: role.name,
              builder: (context, state) => OtpLoginScreen(role: role),
            ),
        ],
      ),
      GoRoute(
        path: AppRoutes.coachDashboard,
        builder: (context, state) => const CoachDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.studentDashboard,
        builder: (context, state) => const StudentDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.guestView,
        builder: (context, state) => const GuestViewScreen(),
      ),
      GoRoute(
        path: AppRoutes.developerPanel,
        builder: (context, state) => const DeveloperPanelScreen(),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
