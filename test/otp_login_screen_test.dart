import 'package:badminton_pro/features/auth/presentation/otp_login_screen.dart';
import 'package:badminton_pro/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget screen(UserRole role) => ProviderScope(
    child: MaterialApp(home: OtpLoginScreen(role: role)),
  );

  for (final role in [UserRole.coach, UserRole.student, UserRole.guest]) {
    testWidgets('${role.name}: coach code + email only', (tester) async {
      await tester.pumpWidget(screen(role));

      expect(find.byKey(const Key('coach-code-field')), findsOneWidget);
      expect(find.byKey(const Key('email-field')), findsOneWidget);
      expect(find.textContaining('Mobile'), findsNothing);
      expect(find.textContaining('without OTP'), findsNothing);
    });
  }

  testWidgets('developer: email only, no coach code', (tester) async {
    await tester.pumpWidget(screen(UserRole.developer));

    expect(find.byKey(const Key('coach-code-field')), findsNothing);
    expect(find.byKey(const Key('email-field')), findsOneWidget);
  });

  testWidgets('invalid input is caught before any network call', (
    tester,
  ) async {
    await tester.pumpWidget(screen(UserRole.student));

    await tester.enterText(find.byKey(const Key('coach-code-field')), 'XYZ');
    await tester.enterText(find.byKey(const Key('email-field')), 'nope');
    await tester.tap(find.text('Send code'));
    await tester.pump();

    expect(find.text('Coach codes look like BP-COACH-0042'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    // Still on the details step: no code was requested.
    expect(find.text('Verify & sign in'), findsNothing);
  });
}
