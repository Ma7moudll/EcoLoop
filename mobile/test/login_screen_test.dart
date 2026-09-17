import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecoloop/providers/providers.dart';
import 'package:ecoloop/screens/login_screen.dart';
import 'package:ecoloop/screens/register_screen.dart';

import 'helpers.dart';

void main() {
  testWidgets('login form validates empty submit', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LoginScreen()),
    ));
    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('valid email+password submits without client-side errors',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
      child: const MaterialApp(home: LoginScreen()),
    ));

    await tester.enterText(
        find.byKey(const ValueKey('Email address')), 'sara@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('Password')), 'secret123');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    // Successful fake auth leaves no validation errors and no error banner.
    expect(find.text('Enter your email address.'), findsNothing);
    expect(find.text('Enter your password.'), findsNothing);
    expect(find.textContaining('Invalid email or password'), findsNothing);
  });

  testWidgets('Create account opens the registration screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LoginScreen()),
    ));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    // The faculty picker is part of the form and is required before submit.
    expect(find.text('FACULTY'), findsOneWidget);
    expect(find.text('Select your faculty'), findsWidgets);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });
}