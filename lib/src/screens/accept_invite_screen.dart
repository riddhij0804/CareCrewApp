import 'package:carecrew_app/src/providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({
    super.key,
    required this.inviteCode,
    required this.email,
    required this.ownerUid,
    this.ownerName,
  });

  final String inviteCode;
  final String email;
  final String ownerUid;
  final String? ownerName;

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showPassword = false;
  bool _accepting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _acceptInvite() async {
    setState(() => _error = null);

    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validation
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }

    if (password.isEmpty) {
      setState(() => _error = 'Password cannot be empty.');
      return;
    }

    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    if (password != confirmPassword) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() => _accepting = true);

    try {
      final repo = ref.read(repositoryProvider);

      // Create user with email and password via Firebase Auth
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: widget.email,
        password: password,
      );

      final newUid = userCredential.user!.uid;

      // Update user display name
      await userCredential.user?.updateDisplayName(name);
      await userCredential.user?.reload();

      // Create user profile in Firestore
      await repo.ensureUserProfile(FirebaseAuth.instance.currentUser!);

      // Mark invitation as accepted in the owner's caregivers collection
      await repo.acceptCaregiverInvite(
        ownerUid: widget.ownerUid,
        caregiverEmail: widget.email,
        caregiverUid: newUid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation accepted! Welcome to CareCrew.')),
        );
        // App will auto-navigate via AuthGate after successful auth
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'email-already-in-use') {
          _error = 'This email is already registered. Please sign in instead.';
        } else if (e.code == 'weak-password') {
          _error = 'Password is too weak. Please try another one.';
        } else {
          _error = e.message ?? 'Failed to accept invitation.';
        }
      });
    } catch (e) {
      setState(() => _error = 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accept Invitation'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
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
                    const Icon(Icons.check_circle_outline_rounded, size: 48, color: Color(0xFF103A86)),
                    const SizedBox(height: 16),
                    Text('Welcome to CareCrew!', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                      'You\'ve been invited to join the care circle for ${widget.ownerName ?? "a patient"}.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Email: ${widget.email}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          border: Border.all(color: Colors.red[200]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red[900]),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Your Full Name',
                        hintText: 'e.g., John Doe',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      enabled: !_accepting,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'At least 6 characters',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        suffixIcon: IconButton(
                          icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      enabled: !_accepting,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        hintText: 'Re-enter your password',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      enabled: !_accepting,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _accepting ? null : _acceptInvite,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF103A86),
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        child: Text(
                          _accepting ? 'Setting up your account...' : 'Accept Invitation',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'By accepting, you agree to the Terms of Service',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
