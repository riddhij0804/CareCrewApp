import 'package:carecrew_app/src/providers.dart';
import 'package:carecrew_app/src/screens/accept_invite_screen.dart';
import 'package:carecrew_app/src/screens/auth_screen.dart';
import 'package:carecrew_app/src/screens/patient_picker_screen.dart';
import 'package:carecrew_app/src/screens/pending_invites_screen.dart';
import 'package:carecrew_app/src/screens/shell_screen.dart';
import 'package:carecrew_app/src/screens/setup_flow_screens.dart';
import 'package:carecrew_app/src/theme.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CareCrewApp extends StatefulWidget {
  const CareCrewApp({super.key, this.firebaseInitError, this.appLinks});

  final String? firebaseInitError;
  final AppLinks? appLinks;

  @override
  State<CareCrewApp> createState() => _CareCrewAppState();
}

class _CareCrewAppState extends State<CareCrewApp> {
  late final AppLinks _appLinks;
  String? _inviteCode;
  String? _inviteEmail;
  String? _inviteOwnerUid;

  @override
  void initState() {
    super.initState();
    _appLinks = widget.appLinks ?? AppLinks();
    _setupDeepLinkListener();
  }

  void _setupDeepLinkListener() {
    _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Deep link error: $err');
      },
    );
  }

  void _handleDeepLink(Uri uri) {
    // Parse carecrew://accept-invite/{code}?email={email}&uid={ownerUid}
    if (uri.scheme == 'carecrew' && uri.host == 'accept-invite') {
      final code = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.join('/')
          : '';
      final email = uri.queryParameters['email'] ?? '';
      final ownerUid = uri.queryParameters['uid'] ?? '';

      setState(() {
        _inviteCode = code;
        _inviteEmail = email;
        _inviteOwnerUid = ownerUid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If there's a pending invite, show the accept screen
    if (_inviteCode != null &&
        _inviteEmail != null &&
        _inviteOwnerUid != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CareCrew',
        theme: AppTheme.light,
        home: AcceptInviteScreen(
          inviteCode: _inviteCode!,
          email: _inviteEmail!,
          ownerUid: _inviteOwnerUid!,
        ),
      );
    }

    // Otherwise, show normal app
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CareCrew',
      theme: AppTheme.light,
      home: widget.firebaseInitError == null
          ? const AuthGate()
          : FirebaseSetupScreen(error: widget.firebaseInitError!),
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  String? _selectedCareContextUid;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          return const AuthScreen();
        }

        final invitesState = ref.watch(pendingInvitesProvider(user.uid));
        if (invitesState.isLoading) {
          return const _LoadingGate();
        }
        final pendingInvites = invitesState.asData?.value ?? const [];
        if (pendingInvites.isNotEmpty) {
          return PendingInvitesScreen(uid: user.uid, invites: pendingInvites);
        }

        final patientIdsState = ref.watch(userPatientIdsProvider(user.uid));
        if (patientIdsState.isLoading) {
          return const _LoadingGate();
        }

        final patientIds = patientIdsState.asData?.value ?? const <String>[];
        final availablePatientIds = patientIds.isEmpty ? <String>[user.uid] : patientIds;

        if (_selectedCareContextUid != null && !availablePatientIds.contains(_selectedCareContextUid)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedCareContextUid = null);
          });
        }

        if (availablePatientIds.length > 1 && _selectedCareContextUid == null) {
          return PatientPickerScreen(
            patientIds: availablePatientIds,
            onSelected: (patientId) {
              if (!mounted) return;
              setState(() => _selectedCareContextUid = patientId);
            },
          );
        }

        final careContextUid = _selectedCareContextUid ?? availablePatientIds.first;

        final patientState = ref.watch(patientProfileProvider(careContextUid));
        return patientState.when(
          data: (patient) {
            if (patient == null) {
              return const SetupFlowScreen();
            }
            return ShellScreen(forcedCareUid: careContextUid);
          },
          loading: () => const _LoadingGate(),
          error: (_, __) {
            // Default to setup on profile-read failures so onboarding is not skipped.
            return const SetupFlowScreen();
          },
        );
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
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 48,
                        color: Color(0xFF103A86),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Firebase needs configuration',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The app could not initialize Firebase with the current configuration.\n\n$error',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'If you need a different Firebase project, update the Android app registration and replace the Firebase values in lib/src/firebase_options.dart or pass them with --dart-define-from-file.',
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
