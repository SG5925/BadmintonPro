import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/models/user_role.dart';
import '../application/login_controller.dart';

/// Two-step Email + OTP login used by every role:
///   1. details — coach code (not for developer) + email
///   2. otp     — enter the code that was emailed
class OtpLoginScreen extends ConsumerStatefulWidget {
  const OtpLoginScreen({super.key, required this.role});

  final UserRole role;

  @override
  ConsumerState<OtpLoginScreen> createState() => _OtpLoginScreenState();
}

class _OtpLoginScreenState extends ConsumerState<OtpLoginScreen> {
  final _detailsKey = GlobalKey<FormState>();
  final _otpKey = GlobalKey<FormState>();
  final _coachCode = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _otp = TextEditingController();

  UserRole get role => widget.role;
  bool get _needsCoachCode => role != UserRole.developer;
  bool get _isGuest => role == UserRole.guest;

  LoginController get _controller =>
      ref.read(loginControllerProvider(role).notifier);

  @override
  void dispose() {
    for (final c in [_coachCode, _email, _name, _otp]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sendOtp() {
    if (!_detailsKey.currentState!.validate()) return;
    final name = _name.text.trim();
    _controller.requestOtp(
      email: _email.text.trim().toLowerCase(),
      coachCode: _needsCoachCode ? _coachCode.text : null,
      fullName: name.isEmpty ? null : name,
    );
  }

  void _verify() {
    if (!_otpKey.currentState!.validate()) return;
    _controller.verifyOtp(_otp.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider(role));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('${role.label} sign in')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.error != null)
                      _Banner(message: state.error!, isError: true),
                    if (state.info != null)
                      _Banner(message: state.info!, isError: false),
                    if (state.step == LoginStep.details)
                      _buildDetails(state, theme)
                    else
                      _buildOtp(state, theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(LoginState state, ThemeData theme) {
    return Form(
      key: _detailsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_detailsHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          if (_needsCoachCode) ...[
            TextFormField(
              key: const Key('coach-code-field'),
              controller: _coachCode,
              enabled: !state.busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Coach code',
                hintText: 'BP-COACH-0042',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: Validators.coachCodeError,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
          ],
          if (_isGuest) ...[
            TextFormField(
              controller: _name,
              enabled: !state.busy,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Your name (optional)',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('email-field'),
            controller: _email,
            enabled: !state.busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: Validators.emailError,
            onFieldSubmitted: (_) => _sendOtp(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.busy ? null : _sendOtp,
            child: state.busy
                ? const _ButtonSpinner()
                : const Text('Send code'),
          ),
        ],
      ),
    );
  }

  Widget _buildOtp(LoginState state, ThemeData theme) {
    return Form(
      key: _otpKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.academyName != null) ...[
            Text(
              state.academyName!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
          ],
          Text(
            'Enter the code we emailed to ${state.email}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            "Can't find it? Check your spam folder.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _otp,
            enabled: !state.busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
            decoration: const InputDecoration(hintText: '••••••'),
            validator: (v) =>
                Validators.isOtp(v ?? '') ? null : 'Enter the 6-digit code',
            onFieldSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.busy ? null : _verify,
            child: state.busy
                ? const _ButtonSpinner()
                : const Text('Verify & sign in'),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: state.busy
                    ? null
                    : () {
                        _otp.clear();
                        _controller.editDetails();
                      },
                child: const Text('Change details'),
              ),
              TextButton(
                onPressed: state.busy ? null : _controller.resendOtp,
                child: const Text('Resend code'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _detailsHint => switch (role) {
    UserRole.coach =>
      'Enter your coach code and the email registered with Badminton Pro.',
    UserRole.student =>
      "Enter your coach's code and the email your coach registered for you.",
    UserRole.guest =>
      "Enter the academy's coach code and your email. We'll send you a code.",
    UserRole.developer => 'Developer access. Enter your email.',
  };
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: foreground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
