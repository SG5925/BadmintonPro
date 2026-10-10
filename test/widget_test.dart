import 'package:badminton_pro/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login placeholder renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Badminton Pro'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
