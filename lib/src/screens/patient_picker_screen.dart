import 'package:carecrew_app/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PatientPickerScreen extends ConsumerWidget {
  const PatientPickerScreen({
    super.key,
    required this.patientIds,
    required this.onSelected,
  });

  final List<String> patientIds;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Patient')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'You are associated with multiple patients. Choose which care dashboard to open.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 14),
          ...patientIds.map((patientId) {
            final patient = ref.watch(patientProfileProvider(patientId)).asData?.value;
            final title = (patient?.fullName.trim().isNotEmpty == true)
                ? patient!.fullName
                : 'Patient $patientId';
            final subtitle = patient == null
                ? 'No profile name found yet'
                : 'Condition: ${patient.condition.isEmpty ? 'Not specified' : patient.condition}';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onSelected(patientId),
              ),
            );
          }),
        ],
      ),
    );
  }
}
