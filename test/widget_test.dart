import 'package:badminton_pro/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Widget app() => MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => const LoginScreen(),
          routes: [
            GoRoute(
              path: ':role',
              builder: (_, s) => Text('login:${s.pathParameters['role']}'),
            ),
          ],
        ),
      ],
    ),
  );

  testWidgets('shows the three public sign-in options, not developer', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Developer'), findsNothing);
  });

  testWidgets('tapping a role opens its login', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();
    expect(find.text('login:student'), findsOneWidget);
  });

  testWidgets('long-pressing the logo opens the hidden developer login', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.longPress(find.byKey(const Key('app-logo')));
    await tester.pumpAndSettle();
    expect(find.text('login:developer'), findsOneWidget);
  });
}
