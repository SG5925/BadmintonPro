import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/models/user_role.dart';

/// A login error safe to show the user as-is.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// All Supabase Auth + login-linking calls. Login is Email + OTP only.
/// Every method throws [AuthFailure] with a user-facing message on error.
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;
  Session? get currentSession => _auth.currentSession;

  /// Returns the academy's display name, or throws if the code is unknown or
  /// the academy is inactive.
  Future<String> lookupAcademy(String coachCode) => _guard(() async {
    final result = await _client.rpc(
      'lookup_coach_code',
      params: {'p_coach_code': coachCode.trim()},
    );
    if (result == null) {
      throw const AuthFailure(
        'Invalid coach code. Please check and try again.',
      );
    }
    return (result as Map<String, dynamic>)['academy_name'] as String;
  });

  /// Emails a one-time code. New addresses get an account created (Supabase
  /// sends the "Confirm sign up" template); existing ones get "Magic Link".
  Future<void> sendOtp(String email) =>
      _guard(() => _auth.signInWithOtp(email: email, shouldCreateUser: true));

  Future<void> verifyOtp(String email, String token) => _guard(() async {
    await _auth.verifyOTP(email: email, token: token, type: OtpType.email);
  });

  /// Links the signed-in account to the academy for [role]. The database
  /// checks the coach code against the account's verified email.
  Future<void> claimAccess(
    UserRole role,
    String coachCode, {
    String? fullName,
  }) => _guard(() async {
    final code = coachCode.trim();
    switch (role) {
      case UserRole.coach:
        await _client.rpc('claim_coach_access', params: {'p_coach_code': code});
      case UserRole.student:
        await _client.rpc(
          'claim_student_access',
          params: {'p_coach_code': code},
        );
      case UserRole.guest:
        await _client.rpc(
          'claim_guest_access',
          params: {'p_coach_code': code, 'p_full_name': fullName},
        );
      case UserRole.developer:
        throw const AuthFailure('Developer access cannot be claimed.');
    }
  });

  /// The signed-in user's profile, or null when signed out.
  Future<AppUser?> fetchProfile() => _guard(() async {
    final uid = _auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('users')
        .select(
          'id, role, tenant_id, full_name, email, phone, is_active, '
          'tenants(name, academy_name, coach_code)',
        )
        .eq('id', uid)
        .maybeSingle();
    return row == null ? null : AppUser.fromMap(row);
  });

  Future<void> signOut() => _guard(_auth.signOut);

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw AuthFailure(messageFor(e));
    }
  }

  static String messageFor(Object error) {
    if (error is AuthFailure) return error.message;
    if (error is AuthRetryableFetchException) return _offline;
    if (error is AuthException) {
      return switch (error.code) {
        'otp_expired' =>
          'That code is wrong or has expired. Please request a new one.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' =>
          'Too many attempts. Please wait a minute and try again.',
        'email_provider_disabled' =>
          'Email sign-in is not enabled yet. Please contact support.',
        'otp_disabled' || 'signup_disabled' =>
          'New sign-ins are currently disabled. Please contact support.',
        'email_address_invalid' ||
        'validation_failed' => 'Please check the email address.',
        _ => error.message,
      };
    }
    if (error is PostgrestException) {
      // PGRST202: RPC missing from the API (migration not applied).
      if (error.code == 'PGRST202') {
        return 'Sign-in is temporarily unavailable. Please try again later.';
      }
      // RPC errors carry the friendly messages raised in the SQL functions.
      return error.message;
    }
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return _offline;
    }
    return 'Something went wrong. Please try again.';
  }

  static const _offline =
      "Couldn't reach the server. Check your internet connection and try again.";
}
