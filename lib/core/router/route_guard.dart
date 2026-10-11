import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/app_user.dart';
import 'app_routes.dart';

/// Decides where the router should send the user. Pure, so it is unit tested.
///
/// * profile still loading (or failed with nothing cached) → splash
/// * signed out, or signed in but not yet linked to an academy → login pages
/// * linked → that role's home; any other role's pages bounce back home
String? resolveRedirect({
  required String location,
  required AsyncValue<AppUser?> user,
  required bool loginInProgress,
}) {
  final onLogin =
      location == AppRoutes.login || location.startsWith('${AppRoutes.login}/');
  final onSplash = location == AppRoutes.splash;

  // Mid-login the profile is briefly "signed in but unlinked"; wait for the
  // login flow to finish linking instead of routing on that state.
  if (loginInProgress) return null;

  if (!user.hasValue) return onSplash ? null : AppRoutes.splash;

  final profile = user.value;
  if (profile == null || !profile.isLinked) {
    return onLogin ? null : AppRoutes.login;
  }

  final home = AppRoutes.homeFor(profile.role);
  if (onLogin || onSplash) return home;
  if (location != home && !location.startsWith('$home/')) return home;
  return null;
}
