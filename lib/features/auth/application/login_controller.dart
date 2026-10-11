import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/user_role.dart';
import '../data/auth_service.dart';
import 'auth_providers.dart';

enum LoginStep { details, otp }

class LoginState {
  const LoginState({
    this.step = LoginStep.details,
    this.busy = false,
    this.error,
    this.info,
    this.academyName,
    this.email,
    this.coachCode,
    this.fullName,
  });

  final LoginStep step;
  final bool busy;
  final String? error;
  final String? info;
  final String? academyName;
  final String? email;
  final String? coachCode;
  final String? fullName;

  LoginState copyWith({
    LoginStep? step,
    bool? busy,
    String? error,
    String? info,
    String? academyName,
    String? email,
    String? coachCode,
    String? fullName,
  }) => LoginState(
    step: step ?? this.step,
    busy: busy ?? this.busy,
    // Messages are one-shot: cleared unless explicitly set again.
    error: error,
    info: info,
    academyName: academyName ?? this.academyName,
    email: email ?? this.email,
    coachCode: coachCode ?? this.coachCode,
    fullName: fullName ?? this.fullName,
  );
}

/// Drives one Email + OTP login (coach, student, guest or developer):
/// details → code emailed → verified → account linked → profile refreshed.
class LoginController extends Notifier<LoginState> {
  LoginController(this.role);

  final UserRole role;

  AuthService get _service => ref.read(authServiceProvider);

  @override
  LoginState build() => const LoginState();

  Future<void> requestOtp({
    required String email,
    String? coachCode,
    String? fullName,
  }) => _run(() async {
    String? academy;
    if (role != UserRole.developer) {
      academy = await _service.lookupAcademy(coachCode!);
    }
    await _service.sendOtp(email);
    if (!ref.mounted) return;
    state = state.copyWith(
      step: LoginStep.otp,
      email: email,
      coachCode: coachCode,
      fullName: fullName,
      academyName: academy,
    );
  });

  Future<void> resendOtp() => _run(() async {
    await _service.sendOtp(state.email!);
    if (ref.mounted) {
      state = state.copyWith(info: 'A new code was sent to ${state.email}.');
    }
  });

  Future<void> verifyOtp(String token) async {
    final progress = ref.read(loginInProgressProvider.notifier)..set(true);
    try {
      await _run(() async {
        await _service.verifyOtp(state.email!, token);
        try {
          await _linkAccount();
        } catch (_) {
          // Never leave a half-linked session behind.
          try {
            await _service.signOut();
          } catch (_) {}
          rethrow;
        }
        ref.invalidate(currentUserProvider);
        await ref.read(currentUserProvider.future);
      });
    } finally {
      progress.set(false);
    }
  }

  void editDetails() => state = state.copyWith(step: LoginStep.details);

  Future<void> _linkAccount() async {
    if (role == UserRole.developer) {
      final profile = await _service.fetchProfile();
      if (profile == null ||
          profile.role != UserRole.developer ||
          !profile.isActive) {
        throw const AuthFailure('This account does not have developer access.');
      }
      return;
    }
    await _service.claimAccess(
      role,
      state.coachCode!,
      fullName: state.fullName,
    );
  }

  Future<void> _run(Future<void> Function() body) async {
    state = state.copyWith(busy: true);
    try {
      await body();
      if (ref.mounted) state = state.copyWith(busy: false, info: state.info);
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(busy: false, error: AuthService.messageFor(e));
      }
    }
  }
}

final loginControllerProvider = NotifierProvider.autoDispose
    .family<LoginController, LoginState, UserRole>(LoginController.new);
