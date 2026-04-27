import 'package:carecrew_app/src/input_validators.dart';
import 'package:carecrew_app/src/models.dart';
import 'package:carecrew_app/src/providers.dart';
import 'package:carecrew_app/src/screens/shell_screen.dart';
import 'package:carecrew_app/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SetupFlowScreen extends ConsumerStatefulWidget {
  const SetupFlowScreen({super.key});

  @override
  ConsumerState<SetupFlowScreen> createState() => _SetupFlowScreenState();
}

class _SetupFlowScreenState extends ConsumerState<SetupFlowScreen> {
  final _patientFormKey = GlobalKey<FormState>();
  final _caregiverFormKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _conditionController = TextEditingController();
  final _caregiverNameController = TextEditingController();
  final _caregiverContactController = TextEditingController();
  final _caregiverRelationshipController = TextEditingController();
  final _dischargeDateController = TextEditingController();

  DateTime? _dischargeDate;
  CaregiverRole? _selectedRole;
  bool _isSavingPatient = false;
  bool _isSavingCaregiver = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _ageController.dispose();
    _conditionController.dispose();
    _caregiverNameController.dispose();
    _caregiverContactController.dispose();
    _caregiverRelationshipController.dispose();
    _dischargeDateController.dispose();
    super.dispose();
  }

  String get _todayLabel => 'Step 1 of 2';

  String? _emailOrPhoneValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Contact info is required';
    if (InputValidators.email(raw, required: false) == null) return null;
    if (InputValidators.phone(raw, required: false, fieldLabel: 'mobile number') == null) return null;
    return 'Enter a valid email or 10-digit mobile number';
  }

  Future<String?> _uid() async {
    final auth = ref.read(authStateProvider).value;
    return auth?.uid;
  }

  Future<void> _savePatient() async {
    if (!_patientFormKey.currentState!.validate()) return;
    if (_dischargeDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a discharge date.')),
      );
      return;
    }
    final uid = await _uid();
    if (uid == null) return;

    setState(() => _isSavingPatient = true);
    try {
      await ref.read(repositoryProvider).savePatientProfile(
            uid: uid,
            profile: PatientProfile(
              id: 'main',
              fullName: _fullNameController.text.trim(),
              age: int.parse(_ageController.text.trim()),
              dischargeDate: _dischargeDate!,
              condition: _conditionController.text.trim(),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient profile saved. Continue to caregiver setup.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isSavingPatient = false);
    }
  }

  Future<void> _saveCaregiver() async {
    if (!_caregiverFormKey.currentState!.validate()) return;
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a role for the caregiver.')),
      );
      return;
    }
    final uid = await _uid();
    if (uid == null) return;

    setState(() => _isSavingCaregiver = true);
    try {
      await ref.read(repositoryProvider).saveCaregiver(
            uid: uid,
            caregiver: CaregiverEntry(
              id: '',
              name: _caregiverNameController.text.trim(),
              contact: _caregiverContactController.text.trim(),
              mobile: '',
              role: _selectedRole!.name,
              relationship: _caregiverRelationshipController.text.trim(),
              inviteStatus: 'pending',
            ),
          );
      _caregiverNameController.clear();
      _caregiverContactController.clear();
      _caregiverRelationshipController.clear();
      setState(() => _selectedRole = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caregiver added. You can add more or continue.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isSavingCaregiver = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).value?.uid;
    final caregiversAsync = uid == null ? const AsyncValue<List<CaregiverEntry>>.loading() : ref.watch(caregiversProvider(uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Who are we caring for?'),
        centerTitle: true,
      ),
      body: CareCrewBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(
              children: [
              _StepPill(label: _todayLabel),
              const SizedBox(height: 18),
              AppSectionCard(
                child: Form(
                  key: _patientFormKey,
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
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                                    initialDate: _dischargeDate ?? DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _dischargeDate = picked;
                                      _dischargeDateController.text = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                                    });
                                  }
                                },
                              ),
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
                      const SizedBox(height: 16),
                      CareCrewPrimaryButton(
                        label: _isSavingPatient ? 'Saving...' : 'Save Patient Profile',
                        onPressed: _isSavingPatient ? null : _savePatient,
                        leading: const Icon(Icons.save_rounded),
                      ),
                    ],
                  ),
                ),
              ),
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
                      'Invite family or professionals to help manage care. You can add more people later.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _caregiverFormKey,
                      child: Column(
                        children: [
                          CareCrewTextField(
                            controller: _caregiverNameController,
                            label: 'Caregiver Name',
                            hintText: 'Enter name',
                            validator: (value) => InputValidators.requiredText(value, fieldName: 'Caregiver name'),
                          ),
                          const SizedBox(height: 14),
                          CareCrewTextField(
                            controller: _caregiverContactController,
                            label: 'Email or Mobile Number',
                            hintText: 'contact info',
                            validator: _emailOrPhoneValidator,
                          ),
                          const SizedBox(height: 14),
                          CareCrewTextField(
                            controller: _caregiverRelationshipController,
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
                            label: _isSavingCaregiver ? 'Adding...' : 'Add Caregiver',
                            onPressed: _isSavingCaregiver ? null : _saveCaregiver,
                            leading: const Icon(Icons.group_add_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    caregiversAsync.when(
                      loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
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
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Setup saved. Your dashboard will open automatically.')),
                        );
                        if (!mounted) return;
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const ShellScreen()),
                          (route) => false,
                        );
                      },
                      leading: const Icon(Icons.verified_rounded),
                    ),
                  ],
                ),
              ),
              ],
            ),
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
