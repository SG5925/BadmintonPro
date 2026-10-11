import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/app_user.dart';
import '../../../supabase/supabase_client.dart';
import '../data/auth_service.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(supabaseClientProvider)),
);

/// Supabase auth events (initial session, sign in, sign out, token refresh).
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authServiceProvider).authStateChanges,
);

/// Id of the signed-in auth user. Falls back to the restored session until
/// the first auth event arrives, so a cold start doesn't flash the login page.
final sessionUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth.hasValue) return auth.requireValue.session?.user.id;
  return ref.read(authServiceProvider).currentSession?.user.id;
});

/// The signed-in user's profile (role, tenant, academy); null when signed out.
/// Refetched when the session user changes; invalidate it after linking.
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  if (userId == null) return null;
  return ref.read(authServiceProvider).fetchProfile();
});

/// True while a login flow is between "OTP verified" and "account linked".
/// The router holds still during that window so it doesn't route on a
/// half-finished profile.
final loginInProgressProvider = NotifierProvider<LoginInProgress, bool>(
  LoginInProgress.new,
);

class LoginInProgress extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
