import 'package:carecrew_app/src/input_validators.dart';
import 'package:carecrew_app/src/providers.dart';
import 'package:carecrew_app/src/repository.dart';
import 'package:carecrew_app/src/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _signInFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();
  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();
  final _signUpNameController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpMobileController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  final _signInMobileController = TextEditingController();

  bool _isLoginMode = true;
  bool _useEmailLogin = true;
  bool _isBusy = false;

  Future<void> _routeAfterSignIn(CareCrewRepository repo) async {
    // AuthGate listens to auth state and handles routing to pending invites,
    // patient picker, setup flow, or shell as needed.
    if (!mounted) return;
  }

  @override
  void dispose() {
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpEmailController.dispose();
    _signUpMobileController.dispose();
    _signUpPasswordController.dispose();
    _signInMobileController.dispose();
    super.dispose();
  }

  Future<void> _submitSignIn() async {
    final repo = ref.read(repositoryProvider);
    if (!_signInFormKey.currentState!.validate()) return;
    if (!_useEmailLogin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mobile OTP sign-in is not configured yet. Use email login for now.'),
        ),
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      await repo.signInWithEmail(
        email: _signInEmailController.text.trim(),
        password: _signInPasswordController.text.trim(),
      );
      await _routeAfterSignIn(repo);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _submitGoogleSignIn() async {
    final repo = ref.read(repositoryProvider);
    setState(() => _isBusy = true);
    try {
      await repo.signInWithGoogle();
      await _routeAfterSignIn(repo);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? error.code)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _submitSignUp() async {
    final repo = ref.read(repositoryProvider);
    if (!_signUpFormKey.currentState!.validate()) return;

    setState(() => _isBusy = true);
    try {
      await repo.createAccount(
        name: _signUpNameController.text.trim(),
        email: _signUpEmailController.text.trim(),
        password: _signUpPasswordController.text.trim(),
        mobileNumber: InputValidators.normalizePhone(_signUpMobileController.text),
      );
      await _routeAfterSignIn(repo);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD9EFFD),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  _BrandHeader(),
                  const SizedBox(height: 26),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.09),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _isLoginMode ? _buildLoginCard(context) : _buildSignUpCard(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => setState(() => _isLoginMode = !_isLoginMode),
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF26364B)),
                        children: [
                          TextSpan(text: _isLoginMode ? "Don’t have an account? " : 'Already have an account? '),
                          TextSpan(
                            text: _isLoginMode ? 'Create one' : 'Sign in',
                            style: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard(BuildContext context) {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Welcome Back',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
        ),
        const SizedBox(height: 6),
        Text(
          'Sign in to continue',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF1D2734)),
        ),
        const SizedBox(height: 18),
        _ModeSwitch(
          leftLabel: 'Email',
          rightLabel: 'Mobile',
          isLeftSelected: _useEmailLogin,
          onLeftTap: () => setState(() => _useEmailLogin = true),
          onRightTap: () => setState(() => _useEmailLogin = false),
        ),
        const SizedBox(height: 18),
        Form(
          key: _signInFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AuthField(
                controller: _useEmailLogin ? _signInEmailController : _signInMobileController,
                label: _useEmailLogin ? 'Email Address' : 'Mobile Number',
                hintText: _useEmailLogin ? 'hello@example.com' : '+91 1234567890',
                keyboardType: _useEmailLogin ? TextInputType.emailAddress : TextInputType.phone,
                icon: _useEmailLogin ? Icons.email_outlined : Icons.call_outlined,
                validator: (value) {
                  return _useEmailLogin
                      ? InputValidators.email(value)
                      : InputValidators.phone(value, fieldLabel: 'mobile number');
                },
              ),
              const SizedBox(height: 14),
              _AuthField(
                controller: _signInPasswordController,
                label: 'Password',
                hintText: '••••••••••',
                obscureText: true,
                icon: Icons.visibility_outlined,
                validator: (value) => InputValidators.password(value),
              ),
              const SizedBox(height: 20),
              CareCrewPrimaryButton(
                label: _isBusy ? 'Logging in...' : 'Log in',
                onPressed: _isBusy ? null : _submitSignIn,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _submitGoogleSignIn,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF1D2734)),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final email = _signInEmailController.text.trim();
                    if (InputValidators.email(email) != null) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Enter your email first to reset the password.')),
                      );
                      return;
                    }
                    try {
                      await ref.read(repositoryProvider).sendPasswordReset(email);
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Password reset link sent.')),
                        );
                      }
                    } on FirebaseAuthException catch (error) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text(error.message ?? error.code)),
                      );
                    } catch (error) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  },
                  child: const Text('Forgot Password?'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpCard(BuildContext context) {
    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign Up',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
        ),
        const SizedBox(height: 6),
        Text(
          'Create an account',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF1D2734)),
        ),
        const SizedBox(height: 18),
        Form(
          key: _signUpFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AuthField(
                controller: _signUpNameController,
                label: 'Full Name',
                hintText: 'Enter your name here',
                icon: Icons.person,
                validator: (value) => InputValidators.requiredText(value, fieldName: 'Name'),
              ),
              const SizedBox(height: 14),
              _AuthField(
                controller: _signUpMobileController,
                label: 'Mobile Number',
                hintText: '+91 1234567890',
                keyboardType: TextInputType.phone,
                icon: Icons.call_outlined,
                validator: (value) => InputValidators.phone(value, fieldLabel: 'mobile number'),
              ),
              const SizedBox(height: 14),
              _AuthField(
                controller: _signUpEmailController,
                label: 'Email Address',
                hintText: 'hello@example.com',
                keyboardType: TextInputType.emailAddress,
                icon: Icons.email_outlined,
                validator: (value) => InputValidators.email(value),
              ),
              const SizedBox(height: 14),
              _AuthField(
                controller: _signUpPasswordController,
                label: 'Password',
                hintText: '••••••••••',
                obscureText: true,
                icon: Icons.visibility_outlined,
                validator: (value) => InputValidators.password(value),
              ),
              const SizedBox(height: 20),
              CareCrewPrimaryButton(
                label: _isBusy ? 'Creating account...' : 'Sign up',
                onPressed: _isBusy ? null : _submitSignUp,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _submitGoogleSignIn,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.health_and_safety_rounded, size: 48, color: Color(0xFF103A86)),
        ),
        const SizedBox(height: 16),
        Text(
          'CareCrew',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
        ),
        const SizedBox(height: 6),
        Text(
          'Coordinating Care, Together',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF1D2734)),
        ),
      ],
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.leftLabel,
    required this.rightLabel,
    required this.isLeftSelected,
    required this.onLeftTap,
    required this.onRightTap,
  });

  final String leftLabel;
  final String rightLabel;
  final bool isLeftSelected;
  final VoidCallback onLeftTap;
  final VoidCallback onRightTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F2FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onLeftTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: isLeftSelected ? const Color(0xFF103A86) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isLeftSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  leftLabel,
                  style: TextStyle(
                    color: isLeftSelected ? Colors.white : const Color(0xFF0F2D66),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onRightTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: !isLeftSelected ? const Color(0xFF103A86) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: !isLeftSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  rightLabel,
                  style: TextStyle(
                    color: !isLeftSelected ? Colors.white : const Color(0xFF0F2D66),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          obscureText: _obscured,
          validator: widget.validator,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF12233A)),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(color: Color(0xFFB0B8C4), fontWeight: FontWeight.w500),
            suffixIcon: widget.obscureText
                ? IconButton(
                    icon: Icon(
                      _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: Colors.black,
                      size: 22,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : Icon(widget.icon, color: Colors.black, size: 22),
            filled: true,
            fillColor: const Color(0xFFE6F1F9),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF103A86), width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}
