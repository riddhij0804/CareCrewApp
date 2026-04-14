import 'package:carecrew_app/src/providers.dart';
import 'package:carecrew_app/src/screens/auth_screen.dart';
import 'package:carecrew_app/src/screens/shell_screen.dart';
import 'package:carecrew_app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CareCrewApp extends StatelessWidget {
  const CareCrewApp({super.key, this.firebaseInitError});

  final String? firebaseInitError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CareCrew',
      theme: AppTheme.light,
      home: firebaseInitError == null ? const AuthGate() : FirebaseSetupScreen(error: firebaseInitError!),
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          return const AuthScreen();
        }
        return const ShellScreen();
      },
      loading: () => const _LoadingGate(),
      error: (error, stackTrace) => _GateError(message: error.toString()),
    );
  }
}

class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFF103A86)),
                      const SizedBox(height: 16),
                      Text('Firebase needs configuration', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Text(
                        'The app could not initialize Firebase with the current configuration.\n\n$error',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Run FlutterFire configure after creating your Firebase project, then replace lib/src/firebase_options.dart with the generated file.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingGate extends StatelessWidget {
  const _LoadingGate();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _GateError extends StatelessWidget {
  const _GateError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
