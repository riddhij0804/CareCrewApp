import 'package:carecrew_app/src/input_validators.dart';
import 'package:carecrew_app/src/models.dart';
import 'package:carecrew_app/src/providers.dart';
import 'package:carecrew_app/src/screens/shell_screen.dart';
import 'package:carecrew_app/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SetupFlowScreen extends StatelessWidget {
  const SetupFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PatientProfileSetupScreen();
  }
}

class PatientProfileSetupScreen extends ConsumerStatefulWidget {
  const PatientProfileSetupScreen({super.key});

  @override
  ConsumerState<PatientProfileSetupScreen> createState() => _PatientProfileSetupScreenState();
}

class _PatientProfileSetupScreenState extends ConsumerState<PatientProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _conditionController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _dischargeDateController = TextEditingController();

  DateTime? _dischargeDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _ageController.dispose();
    _conditionController.dispose();
    _emergencyContactController.dispose();
    _dischargeDateController.dispose();
    super.dispose();
  }

  String? _uid() => ref.read(repositoryProvider).currentUser?.uid;

  Future<void> _pickDischargeDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _dischargeDate ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dischargeDate = picked;
        _dischargeDateController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  Future<void> _savePatientProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dischargeDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a discharge date.')),
      );
      return;
    }
    final uid = _uid();
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User not authenticated')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final profile = PatientProfile(
        id: 'main',
        fullName: _fullNameController.text.trim(),
        age: int.parse(_ageController.text.trim()),
        dischargeDate: _dischargeDate!,
        condition: _conditionController.text.trim(),
        emergencyContact: InputValidators.normalizePhone(_emergencyContactController.text),
      );
      
      await ref.read(repositoryProvider).savePatientProfile(
            uid: uid,
            profile: profile,
          );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient profile saved successfully!')),
      );
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CareGiversSetupScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save profile: ${error.toString()}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD9EFFD),
      appBar: AppBar(
        title: const Text('Who are we caring for?'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Column(
            children: [
              const _StepPill(label: 'Step 1 of 2'),
              const SizedBox(height: 18),
              AppSectionCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '1. Patient Profile',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          const CircleAvatar(
                            radius: 22,
                            backgroundColor: Color(0xFFEAF4FB),
                            child: Icon(Icons.person_rounded, color: Color(0xFF103A86)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      CareCrewTextField(
                        controller: _fullNameController,
                        label: 'Patient Full Name',
                        hintText: 'e.g. Ram Mishra',
                        validator: (value) => InputValidators.requiredText(value, fieldName: 'Patient name'),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: CareCrewTextField(
                              controller: _ageController,
                              label: 'Age',
                              hintText: '58',
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'Age is required';
                                final parsed = int.tryParse(value.trim());
                                if (parsed == null || parsed <= 0) return 'Enter a valid age';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CareCrewTextField(
                              controller: _dischargeDateController,
                              label: 'Discharge Date',
                              hintText: 'dd/mm/yyyy',
                              readOnly: true,
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_month_rounded),
                                onPressed: _pickDischargeDate,
                              ),
                              onTap: _pickDischargeDate,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      CareCrewTextField(
                        controller: _conditionController,
                        label: 'Primary Condition / Diagnosis',
                        hintText: 'e.g. Post-op recovery',
                        maxLines: 3,
                        validator: (value) => InputValidators.requiredText(value, fieldName: 'Condition'),
                      ),
                      const SizedBox(height: 14),
                      CareCrewTextField(
                        controller: _emergencyContactController,
                        label: 'Emergency Contact Number',
                        hintText: 'e.g. +91 9876543210',
                        keyboardType: TextInputType.phone,
                        validator: (value) => InputValidators.phone(value, fieldLabel: 'emergency contact number'),
                      ),
                      const SizedBox(height: 16),
                      CareCrewPrimaryButton(
                        label: _isSaving ? 'Saving...' : 'Save Profile',
                        onPressed: _isSaving ? null : _savePatientProfile,
                        leading: const Icon(Icons.save_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CareGiversSetupScreen extends ConsumerStatefulWidget {
  const CareGiversSetupScreen({super.key});

  @override
  ConsumerState<CareGiversSetupScreen> createState() => _CareGiversSetupScreenState();
}

class _CareGiversSetupScreenState extends ConsumerState<CareGiversSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _relationshipController = TextEditingController();
  CaregiverRole? _selectedRole = CaregiverRole.editor;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  String? _uid() => ref.read(repositoryProvider).currentUser?.uid;

  Future<void> _addCaregiver() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a role for the caregiver.')),
      );
      return;
    }
    final uid = _uid();
    if (uid == null) return;

    setState(() => _isSaving = true);
    try {
      final inviteCode = DateTime.now().millisecondsSinceEpoch.toString().substring(6);
      await ref.read(repositoryProvider).saveCaregiver(
            uid: uid,
            caregiver: CaregiverEntry(
              id: '',
              name: _nameController.text.trim(),
              contact: _emailController.text.trim().toLowerCase(),
              mobile: InputValidators.normalizePhone(_mobileController.text),
              role: _selectedRole!.name,
              relationship: _relationshipController.text.trim(),
              inviteStatus: 'pending',
              inviteCode: inviteCode,
            ),
          );
      _nameController.clear();
      _emailController.clear();
      _mobileController.clear();
      _relationshipController.clear();
      setState(() => _selectedRole = CaregiverRole.editor);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caregiver added. You can add more or complete setup.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _completeSetup() async {
    if (!mounted) return;
    final uid = ref.read(repositoryProvider).currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are not signed in.')));
      return;
    }

    try {
      final snap = await ref.read(repositoryProvider).firestore.collection('users').doc(uid).collection('patient').doc('main').get();
      if (!snap.exists) {
        // Patient profile missing — prompt the user to return and save profile first.
        if (!mounted) return;
        final goBack = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Patient profile missing'),
            content: const Text('You have not saved a patient profile yet. Please save the patient profile first to complete setup.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Stay')),
              TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Go to profile')),
            ],
          ),
        );
        if (goBack == true) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PatientProfileSetupScreen()));
        }
        return;
      }
    } catch (e) {
      // If we couldn't check, show an error but allow continuation to be safe.
      // ignore: avoid_print
      print('Warning: could not verify patient profile on complete setup: $e');
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ShellScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).value?.uid;
    final caregiversAsync = uid == null ? const AsyncValue<List<CaregiverEntry>>.loading() : ref.watch(caregiversProvider(uid));

    return Scaffold(
      backgroundColor: const Color(0xFFD9EFFD),
      appBar: AppBar(
        title: const Text('Build your Care Crew'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Column(
            children: [
              const _StepPill(label: 'Step 2 of 2'),
              const SizedBox(height: 18),
              AppSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '2. Invite Caregivers',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SoftChip(label: 'Optional', color: Color(0xFFF7D7E6), textColor: Color(0xFF8B3A68)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Invite family or professionals to help manage care. You can skip this step and complete setup now.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          CareCrewTextField(
                            controller: _nameController,
                            label: 'Caregiver Name',
                            hintText: 'Enter name',
                            validator: (value) => InputValidators.requiredText(value, fieldName: 'Caregiver name'),
                          ),
                          const SizedBox(height: 14),
                          CareCrewTextField(
                            controller: _emailController,
                            label: 'Email',
                            hintText: 'caregiver@example.com',
                            validator: (value) => InputValidators.email(value),
                          ),
                          const SizedBox(height: 14),
                          CareCrewTextField(
                            controller: _mobileController,
                            label: 'Mobile Number',
                            hintText: '+1-XXX-XXX-XXXX',
                            keyboardType: TextInputType.phone,
                            validator: (value) => InputValidators.phone(value, required: false, fieldLabel: 'mobile number'),
                          ),
                          const SizedBox(height: 14),
                          CareCrewTextField(
                            controller: _relationshipController,
                            label: 'Relationship',
                            hintText: 'Daughter, spouse, nurse, etc.',
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<CaregiverRole>(
                            initialValue: _selectedRole,
                            items: CaregiverRole.values
                                .map(
                                  (role) => DropdownMenuItem(
                                    value: role,
                                    child: Text(role.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() => _selectedRole = value),
                            decoration: const InputDecoration(
                              labelText: 'Assign Role',
                              hintText: 'Choose role',
                            ),
                          ),
                          const SizedBox(height: 16),
                          CareCrewPrimaryButton(
                            label: _isSaving ? 'Adding...' : 'Add Caregiver',
                            onPressed: _isSaving ? null : _addCaregiver,
                            leading: const Icon(Icons.group_add_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    caregiversAsync.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (error, stackTrace) => Text(error.toString()),
                      data: (caregivers) {
                        if (caregivers.isEmpty) {
                          return const Text('No caregivers added yet.');
                        }
                        return Column(
                          children: caregivers
                              .map(
                                (caregiver) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _CaregiverPreviewRow(caregiver: caregiver),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    CareCrewPrimaryButton(
                      label: 'Complete Setup',
                      onPressed: _completeSetup,
                      leading: const Icon(Icons.verified_rounded),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _completeSetup,
                        child: const Text('Skip for now'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2D66B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE1C243)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _CaregiverPreviewRow extends StatelessWidget {
  const _CaregiverPreviewRow({required this.caregiver});

  final CaregiverEntry caregiver;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFF2D6EA),
            child: Icon(Icons.person, color: Color(0xFF103A86)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caregiver.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(caregiver.contact, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          SoftChip(
            label: caregiver.roleValue.label,
            color: const Color(0xFFF7D7E6),
            textColor: const Color(0xFF8B3A68),
          ),
        ],
      ),
    );
  }
}
