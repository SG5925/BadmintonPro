/// Input validation shared by the login forms.
abstract final class Validators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _coachCode = RegExp(r'^(BP-COACH-)?\d{1,6}$');

  static bool isEmail(String input) => _email.hasMatch(input.trim());

  static bool isCoachCode(String input) =>
      _coachCode.hasMatch(input.trim().toUpperCase().replaceAll(' ', ''));

  /// Supabase OTPs are 6 digits by default (configurable up to 10).
  static bool isOtp(String input) => RegExp(r'^\d{6,10}$').hasMatch(input);

  static String? coachCodeError(String? v) => v == null || v.trim().isEmpty
      ? 'Enter your coach code'
      : isCoachCode(v)
      ? null
      : 'Coach codes look like BP-COACH-0042';

  static String? emailError(String? v) => v == null || v.trim().isEmpty
      ? 'Enter your email'
      : isEmail(v)
      ? null
      : 'Enter a valid email';
}
