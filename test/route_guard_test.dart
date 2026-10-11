import 'package:badminton_pro/core/router/app_routes.dart';
import 'package:badminton_pro/core/router/route_guard.dart';
import 'package:badminton_pro/shared/models/app_user.dart';
import 'package:badminton_pro/shared/models/user_role.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser user(UserRole role, {String? tenant = 't1', bool active = true}) =>
    AppUser(id: 'u1', role: role, tenantId: tenant, isActive: active);

String? go(
  String location,
  AsyncValue<AppUser?> u, {
  bool inProgress = false,
}) => resolveRedirect(location: location, user: u, loginInProgress: inProgress);

void main() {
  group('while loading', () {
    test('first load sends everything to splash', () {
      expect(go('/dashboard', const AsyncLoading()), AppRoutes.splash);
      expect(go(AppRoutes.splash, const AsyncLoading()), isNull);
    });

    test('load error with no cached profile stays on splash', () {
      expect(
        go('/login', AsyncError(Exception('offline'), StackTrace.empty)),
        AppRoutes.splash,
      );
    });
  });

  group('signed out', () {
    const signedOut = AsyncData<AppUser?>(null);

    test('protected pages redirect to login', () {
      for (final path in [
        '/',
        '/dashboard',
        '/student',
        '/guest',
        '/developer',
      ]) {
        expect(go(path, signedOut), AppRoutes.login, reason: path);
      }
    });

    test('login pages are allowed, including hidden developer login', () {
      for (final path in ['/login', '/login/coach', '/login/developer']) {
        expect(go(path, signedOut), isNull, reason: path);
      }
    });
  });

  group('signed in but not linked to an academy', () {
    test('fresh OTP account (guest, no tenant) stays on login', () {
      final unlinked = AsyncData<AppUser?>(user(UserRole.guest, tenant: null));
      expect(go('/login/student', unlinked), isNull);
      expect(go('/guest', unlinked), AppRoutes.login);
    });

    test('deactivated account is treated as unlinked', () {
      final inactive = AsyncData<AppUser?>(user(UserRole.coach, active: false));
      expect(go('/dashboard', inactive), AppRoutes.login);
    });
  });

  group('signed in and linked', () {
    test('each role lands on its own home from login and splash', () {
      final homes = {
        UserRole.developer: '/developer',
        UserRole.coach: '/dashboard',
        UserRole.student: '/student',
        UserRole.guest: '/guest',
      };
      homes.forEach((role, home) {
        final u = AsyncData<AppUser?>(
          user(role, tenant: role == UserRole.developer ? null : 't1'),
        );
        expect(go('/login/${role.name}', u), home, reason: role.name);
        expect(go(AppRoutes.splash, u), home, reason: role.name);
        expect(go(home, u), isNull, reason: role.name);
      });
    });

    test("roles can't open other roles' pages", () {
      final student = AsyncData<AppUser?>(user(UserRole.student));
      expect(go('/dashboard', student), '/student');
      expect(go('/developer', student), '/student');

      final coach = AsyncData<AppUser?>(user(UserRole.coach));
      expect(go('/developer', coach), '/dashboard');
      expect(go('/dashboard/members', coach), isNull);
    });

    test('a path that only shares a prefix is not treated as home', () {
      final student = AsyncData<AppUser?>(user(UserRole.student));
      expect(go('/students-admin', student), '/student');
    });
  });

  test('router holds still while a login is being linked', () {
    final unlinked = AsyncData<AppUser?>(user(UserRole.guest, tenant: null));
    expect(go('/login/coach', unlinked, inProgress: true), isNull);
    final linked = AsyncData<AppUser?>(user(UserRole.coach));
    expect(go('/login/coach', linked, inProgress: true), isNull);
  });
}
