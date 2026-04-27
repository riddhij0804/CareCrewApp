import 'dart:math' as math;

import 'package:carecrew_app/src/input_validators.dart';
import 'package:carecrew_app/src/models.dart';
import 'package:carecrew_app/src/providers.dart';
import 'package:carecrew_app/src/widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

String _shortDate(DateTime value) => DateFormat('MMM d, yyyy').format(value);
String _longDate(DateTime value) => DateFormat('EEE, MMM d, yyyy').format(value);
String _shortTime(DateTime value) => DateFormat('h:mm a').format(value);
DateTime _startOfDay(DateTime value) => DateTime(value.year, value.month, value.day);
String _dayKey(DateTime value) => DateFormat('yyyy-MM-dd').format(value.toLocal());
String _relativeTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'taken':
    case 'completed':
      return const Color(0xFF28A745);
    case 'missed':
    case 'cancelled':
      return const Color(0xFFB01E24);
    case 'viewer':
      return const Color(0xFF8AA0BD);
    case 'doctor':
      return const Color(0xFF3E7CA6);
    case 'editor':
      return const Color(0xFFB477E7);
    case 'admin':
      return const Color(0xFF103A86);
    default:
      return const Color(0xFFF0C84B);
  }
}

Future<void> _launchExternal(String url) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _patientWithMe = false;
  bool _updatingPatientLocation = false;
  String? _lastPatientLocation;
  String? _patientLocationError;

  Future<void> _updatePatientLocation() async {
    setState(() {
      _updatingPatientLocation = true;
      _patientLocationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        setState(() {
          _patientLocationError = 'Location service is off. Please enable GPS.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _patientLocationError = 'Location permission denied.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _patientLocationError = 'Location permission permanently denied. Allow it from settings.';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final locationString =
          'Lat: ${pos.latitude.toStringAsFixed(6)}, Lng: ${pos.longitude.toStringAsFixed(6)}';
      setState(() {
        _lastPatientLocation = locationString;
      });

      await ref.read(repositoryProvider).setLastPatientLocation(uid: widget.uid, location: locationString);
    } catch (_) {
      setState(() {
        _patientLocationError = 'Unable to fetch GPS location right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _updatingPatientLocation = false;
        });
      }
    }
  }
  bool _synced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_synced) return;
    _synced = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(repositoryProvider).syncMedicationStatuses(widget.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final patientAsync = ref.watch(patientProfileProvider(widget.uid));
    final medsAsync = ref.watch(medicationsProvider(widget.uid));
    final apptsAsync = ref.watch(appointmentsProvider(widget.uid));
    final vitalsAsync = ref.watch(vitalsProvider(widget.uid));
    final role = ref.watch(careRoleProvider(widget.uid)).asData?.value ?? CaregiverRole.admin;
    final canEdit = role.canEdit;

    // Get the authenticated user's UID for profile navigation
    final authUser = ref.watch(authStateProvider).value;
    final myUid = authUser?.uid;

    // Handle any errors from the patient profile stream
    if (patientAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('CareCrew')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Error loading patient profile'),
            const SizedBox(height: 8),
            Text(patientAsync.error.toString(), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(patientProfileProvider(widget.uid)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final meds = medsAsync.value ?? const <MedicationEntry>[];
    final appts = apptsAsync.value ?? const <AppointmentEntry>[];
    final vitals = vitalsAsync.value ?? const <VitalEntry>[];
    final patient = patientAsync.value;

    final todayMeds = meds;
    final takenToday = todayMeds.where((med) => med.status == 'taken').length;
    final completedTasks = takenToday + vitals.where((vital) => vital.createdAt != null && _dayKey(vital.createdAt!) == _dayKey(DateTime.now())).length;
    final totalTasks = math.max(todayMeds.length + 1, 1);
    final progress = totalTasks == 0 ? 0.0 : math.min(completedTasks / totalTasks, 1.0);
    final recoveryLabel = progress >= 0.8 ? 'Recovery on track' : progress >= 0.5 ? 'Needs attention' : 'Early recovery';
    final nextAppointment = appts.where((appointment) => appointment.appointmentDateTime.isAfter(DateTime.now())).toList()..sort((a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));
    final upcoming = nextAppointment.isNotEmpty ? nextAppointment.first : null;

    final primaryMed = todayMeds.isNotEmpty ? todayMeds.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFFCFE6F7),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(repositoryProvider).syncMedicationStatuses(widget.uid);
          ref.invalidate(patientProfileProvider(widget.uid));
          ref.invalidate(medicationsProvider(widget.uid));
          ref.invalidate(activityLogsProvider(widget.uid));
          ref.invalidate(appointmentsProvider(widget.uid));
          ref.invalidate(vitalsProvider(widget.uid));
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
              decoration: const BoxDecoration(
                color: Color(0xFF0D2F7A),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        ),
                        const Spacer(),
                        Text(
                          'CareCrew',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            if (myUid != null) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: myUid)));
                            }
                          },
                          icon: const Icon(Icons.settings_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Stack(
                          children: [
                            const CircleAvatar(
                              radius: 30,
                              backgroundColor: Color(0xFFEAF2FF),
                              child: Icon(Icons.person_rounded, size: 34, color: Color(0xFF4469A9)),
                            ),
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8D658),
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(color: const Color(0xFF0D2F7A), width: 1.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                patient?.fullName ?? 'Patient Dashboard',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFC7D5),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '• ${progress >= 0.8 ? 'Post-op Recovery: Week 3' : recoveryLabel}',
                                  style: const TextStyle(
                                    color: Color(0xFF0D2F7A),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Goals',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: const Color(0xFF0D2F7A),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$completedTasks of $totalTasks tasks completed',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 140,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFE9E9E9),
                                  valueColor: const AlwaysStoppedAnimation(Color(0xFFE4C43F)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _patientWithMe,
                              onChanged: _updatingPatientLocation
                                  ? null
                                  : (val) async {
                                      final checked = val ?? false;
                                      setState(() {
                                        _patientWithMe = checked;
                                        if (!checked) {
                                          _patientLocationError = null;
                                        }
                                      });
                                      if (checked) {
                                        await _updatePatientLocation();
                                      }
                                    },
                            ),
                            Expanded(
                              child: Text(
                                'Patient Currently with Me',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (_updatingPatientLocation)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        if (_patientWithMe && _lastPatientLocation != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12, bottom: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Last Recorded Patient Location',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _lastPatientLocation!,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_patientWithMe && _patientLocationError != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12, bottom: 4),
                              child: Text(
                                _patientLocationError!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF8A1120)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Today\'s Care',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: const Color(0xFF0D2F7A),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AppointmentsScreen(uid: widget.uid))),
                              child: const Text('+ Add New'),
                            ),
                          ],
                        ),
                        if (primaryMed != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F4E8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Color(0xFFF4C53A),
                                  child: Icon(Icons.medication_liquid_rounded, color: Colors.white),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(primaryMed.name, style: Theme.of(context).textTheme.titleMedium),
                                      Text(primaryMed.dosage, style: Theme.of(context).textTheme.bodySmall),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2D94E),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.14),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(primaryMed.timeLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          CareCrewPrimaryButton(
                            label: !canEdit
                                ? 'Read only'
                                : (primaryMed.canBeMarkedTaken ? 'Mark as taken' : 'Already taken'),
                            onPressed: canEdit && primaryMed.canBeMarkedTaken
                                ? () async {
                                    await ref.read(repositoryProvider).markMedicationTaken(uid: widget.uid, medication: primaryMed);
                                    ref.invalidate(medicationsProvider(widget.uid));
                                    ref.invalidate(activityLogsProvider(widget.uid));
                                  }
                                : null,
                            leading: const Icon(Icons.check_circle_rounded),
                          ),
                        ] else ...[
                          const SizedBox(height: 10),
                          EmptyStateCard(
                            title: 'No medications scheduled yet',
                            subtitle: 'Add the first medication to start tracking daily care.',
                            action: CareCrewPrimaryButton(
                              label: 'Add Medication',
                              onPressed: canEdit
                                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MedicationsScreen(uid: widget.uid)))
                                  : null,
                              leading: const Icon(Icons.medication_rounded),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3ECF0),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_rounded, color: Color(0xFF2B2A2F)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  upcoming == null
                                      ? 'No upcoming appointments'
                                      : '${upcoming.doctorName} ${DateFormat('MMM d, h:mm a').format(upcoming.appointmentDateTime)}',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Quick Actions',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF0D2F7A),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _QuickActionTile(
                        icon: Icons.medication_rounded,
                        label: 'Meds',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MedicationsScreen(uid: widget.uid))),
                      ),
                      _QuickActionTile(
                        icon: Icons.monitor_heart_rounded,
                        label: 'Symptoms',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VitalsScreen(uid: widget.uid))),
                      ),
                      _QuickActionTile(
                        icon: Icons.note_alt_rounded,
                        label: 'Documents',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocumentsScreen(uid: widget.uid))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final emergencyNumber = (patient?.emergencyContact ?? '').trim();
                        if (emergencyNumber.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Add emergency contact in patient profile first.')),
                          );
                          return;
                        }

                        final digitsOnly = emergencyNumber.replaceAll(RegExp(r'\D'), '');
                        final dialNumber = digitsOnly.length == 10
                            ? '+91$digitsOnly'
                            : emergencyNumber.replaceAll(RegExp(r'[^0-9+]'), '');
                        final Uri emergencyUri = Uri(scheme: 'tel', path: dialNumber);
                        try {
                          if (await canLaunchUrl(emergencyUri)) {
                            await launchUrl(
                              emergencyUri,
                              mode: LaunchMode.externalApplication,
                            );
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Unable to make call on this device')),
                              );
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF8E0B2A),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(60),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      ),
                      icon: const Icon(Icons.add_ic_call_rounded),
                      label: const Text(
                        'EMERGENCY CALL',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 100,
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE8F0FA),
                border: Border.all(color: const Color(0xFF1B2D4B), width: 1.2),
              ),
              child: Icon(icon, color: const Color(0xFF0D2F7A), size: 38),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class MedicationsScreen extends ConsumerStatefulWidget {
  const MedicationsScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends ConsumerState<MedicationsScreen> {
  final TextEditingController _numDaysController = TextEditingController(text: '1');
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _stockController = TextEditingController();
  final _notesController = TextEditingController();
  final _timeDisplayController = TextEditingController();
  final _medStartDateDisplayController = TextEditingController();
  TimeOfDay? _timeOfDay;
  DateTime _selectedDay = _startOfDay(DateTime.now());
  DateTime _medStartDate = _startOfDay(DateTime.now());
  bool _saving = false;
  bool _showAddMedicationForm = false;

  List<DateTime> get _calendarDays {
    // Show 30 days centered around today for scrolling
    final today = _startOfDay(DateTime.now());
    return List.generate(30, (i) => today.subtract(Duration(days: 15 - i)));
  }

  @override
  void initState() {
    super.initState();
    _medStartDateDisplayController.text = DateFormat('MMM d, yyyy').format(_medStartDate);
  }

  @override
  void dispose() {
    _numDaysController.dispose();
    _nameController.dispose();
    _dosageController.dispose();
    _stockController.dispose();
    _notesController.dispose();
    _timeDisplayController.dispose();
    _medStartDateDisplayController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _timeOfDay ?? TimeOfDay.now());
    if (picked != null) {
      setState(() {
        _timeOfDay = picked;
        _timeDisplayController.text = picked.format(context);
      });
    }
  }

  Future<void> _pickSelectedDay() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _selectedDay,
    );
    if (picked != null) {
      setState(() => _selectedDay = _startOfDay(picked));
    }
  }

  Future<void> _openMedicationEditor(MedicationEntry medication) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: medication.name);
    final dosageController = TextEditingController(text: medication.dosage);
    final stockController = TextEditingController(text: medication.currentStock?.toString() ?? '');
    final notesController = TextEditingController(text: medication.notes);
    final timeController = TextEditingController(
      text: TimeOfDay(hour: medication.scheduledHour, minute: medication.scheduledMinute).format(context),
    );
    var timeOfDay = TimeOfDay(hour: medication.scheduledHour, minute: medication.scheduledMinute);
    var isTaken = medication.status == 'taken';
    var saving = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> submit() async {
                if (!formKey.currentState!.validate()) return;
                setDialogState(() => saving = true);
                try {
                  await ref.read(repositoryProvider).updateMedication(
                        uid: widget.uid,
                        medication: MedicationEntry(
                          id: medication.id,
                          name: nameController.text.trim(),
                          dosage: dosageController.text.trim(),
                          currentStock: int.parse(stockController.text.trim()),
                          scheduledHour: timeOfDay.hour,
                          scheduledMinute: timeOfDay.minute,
                          notes: notesController.text.trim(),
                          status: isTaken ? 'taken' : 'pending',
                          lastTakenAt: isTaken ? (medication.lastTakenAt ?? DateTime.now()) : null,
                          lastTakenDateKey: isTaken
                              ? (medication.lastTakenDateKey ?? _dayKey(medication.createdAt ?? DateTime.now()))
                              : null,
                          lastMissedDateKey: medication.lastMissedDateKey,
                          createdAt: medication.createdAt,
                          updatedAt: medication.updatedAt,
                        ),
                      );
                  ref.invalidate(medicationsProvider(widget.uid));
                  ref.invalidate(activityLogsProvider(widget.uid));
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => saving = false);
                  }
                }
              }

              return AlertDialog(
                title: const Text('Edit Medication'),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CareCrewTextField(
                          controller: nameController,
                          label: 'Medicine Name',
                          hintText: 'e.g. Metformin',
                          validator: (value) => value == null || value.trim().isEmpty ? 'Medication name required' : null,
                        ),
                        const SizedBox(height: 14),
                        CareCrewTextField(
                          controller: dosageController,
                          label: 'Dosage',
                          hintText: '500mg • 1 pill',
                          validator: (value) => value == null || value.trim().isEmpty ? 'Dosage required' : null,
                        ),
                        const SizedBox(height: 14),
                        CareCrewTextField(
                          controller: stockController,
                          label: 'Current Stock',
                          hintText: 'e.g. 12',
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Current stock required';
                            final parsed = int.tryParse(value.trim());
                            if (parsed == null || parsed < 0) return 'Enter a valid stock count';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        CareCrewTextField(
                          controller: timeController,
                          label: 'Time',
                          hintText: 'Choose time',
                          readOnly: true,
                          onTap: () async {
                            final picked = await showTimePicker(context: dialogContext, initialTime: timeOfDay);
                            if (picked != null) {
                              setDialogState(() {
                                timeOfDay = picked;
                                timeController.text = picked.format(dialogContext);
                              });
                            }
                          },
                          suffixIcon: IconButton(
                            onPressed: () async {
                              final picked = await showTimePicker(context: dialogContext, initialTime: timeOfDay);
                              if (picked != null) {
                                setDialogState(() {
                                  timeOfDay = picked;
                                  timeController.text = picked.format(dialogContext);
                                });
                              }
                            },
                            icon: const Icon(Icons.schedule_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        CareCrewTextField(
                          controller: notesController,
                          label: 'Notes',
                          hintText: 'With food, before bedtime, etc.',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Mark as Taken'),
                                selected: isTaken,
                                onSelected: (selected) {
                                  setDialogState(() => isTaken = true);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Mark as Not Taken'),
                                selected: !isTaken,
                                onSelected: (selected) {
                                  setDialogState(() => isTaken = false);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving ? null : submit,
                    child: Text(saving ? 'Saving...' : 'Update'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      dosageController.dispose();
      stockController.dispose();
      notesController.dispose();
      timeController.dispose();
    }
  }

  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate()) return;
    final parsedNumDays = int.tryParse(_numDaysController.text.trim());
    if (parsedNumDays == null || parsedNumDays < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Number of days must be at least 1.')));
      return;
    }
    if (_timeOfDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a medication time.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      for (int i = 0; i < parsedNumDays; i++) {
        final medDate = _medStartDate.add(Duration(days: i));
        await ref.read(repositoryProvider).saveMedication(
          uid: widget.uid,
          medication: MedicationEntry(
            id: '',
            name: _nameController.text.trim(),
            dosage: _dosageController.text.trim(),
            currentStock: int.parse(_stockController.text.trim()),
            scheduledHour: _timeOfDay!.hour,
            scheduledMinute: _timeOfDay!.minute,
            notes: _notesController.text.trim(),
            status: 'pending',
            createdAt: DateTime(medDate.year, medDate.month, medDate.day, now.hour, now.minute, now.second),
          ),
        );
      }
      _nameController.clear();
      _dosageController.clear();
      _stockController.clear();
      _notesController.clear();
      setState(() {
        _timeOfDay = null;
        _timeDisplayController.clear();
        _numDaysController.text = '1';
        _medStartDate = _startOfDay(DateTime.now());
        _medStartDateDisplayController.text = DateFormat('MMM d, yyyy').format(_medStartDate);
      });
      ref.invalidate(medicationsProvider(widget.uid));
      ref.invalidate(activityLogsProvider(widget.uid));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(careRoleProvider(widget.uid)).asData?.value ?? CaregiverRole.admin;
    final canEdit = role.canEdit;
    final medsAsync = ref.watch(medicationsProvider(widget.uid));
    final meds = medsAsync.value ?? const <MedicationEntry>[];
    final selectedDayMeds = meds.where((medication) => medication.createdAt != null && DateUtils.isSameDay(medication.createdAt!, _selectedDay)).toList();
    final calendarDays = _calendarDays;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medication'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text(
                'C',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          Text(
            DateFormat('EEEE, MMM d, yyyy').format(_selectedDay),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Showing entries added on ${DateFormat('MMM d, yyyy').format(_selectedDay)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E779B)),
                ),
              ),
              IconButton(
                onPressed: _pickSelectedDay,
                icon: const Icon(Icons.calendar_month_rounded),
                tooltip: 'Pick a day',
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: calendarDays.map((dayDate) {
                final selected = DateUtils.isSameDay(dayDate, _selectedDay);
                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = _startOfDay(dayDate)),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF103A86) : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${dayDate.day}',
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF103A86),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat('EEE').format(dayDate).toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF5E779B)),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          AppSectionCard(
            borderColor: const Color(0xFFDDE9F6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Added on ${DateFormat('MMM d').format(_selectedDay)}',
                  action: const SoftChip(label: 'Calendar linked'),
                ),
                const SizedBox(height: 10),
                if (selectedDayMeds.isEmpty)
                  const Text('No medications were added on this day.')
                else
                  ...selectedDayMeds.map(
                    (medication) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: medication.status == 'missed'
                              ? const Color(0xFFFCE7E8)
                              : medication.status == 'taken'
                                  ? const Color(0xFFE6F7E9)
                                  : const Color(0xFFF8FBFF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF103A86),
                                  child: Text(
                                    medication.name.isNotEmpty ? medication.name[0].toUpperCase() : 'M',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(medication.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                      Text('${medication.dosage} • ${medication.timeLabel}'),
                                      if (medication.notes.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(medication.notes),
                                      ],
                                    ],
                                  ),
                                ),
                                SoftChip(
                                  label: medication.status,
                                  color: _statusColor(medication.status).withValues(alpha: 0.16),
                                  textColor: _statusColor(medication.status),
                                ),
                                IconButton(
                                  onPressed: () => _openMedicationEditor(medication),
                                  icon: const Icon(Icons.edit_rounded),
                                  tooltip: 'Edit medication',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: CareCrewPrimaryButton(
                                    label: medication.status == 'taken' ? 'Mark as Not Taken' : 'Mark as Taken',
                                    onPressed: !canEdit
                                        ? null
                                        : () async {
                                            if (medication.status == 'taken') {
                                              await ref.read(repositoryProvider).markMedicationNotTaken(
                                                    uid: widget.uid,
                                                    medication: medication,
                                                  );
                                            } else {
                                              await ref.read(repositoryProvider).markMedicationTaken(
                                                    uid: widget.uid,
                                                    medication: medication,
                                                  );
                                            }
                                            ref.invalidate(medicationsProvider(widget.uid));
                                            ref.invalidate(activityLogsProvider(widget.uid));
                                          },
                                    leading: Icon(
                                      medication.status == 'taken' ? Icons.undo_rounded : Icons.check_circle_rounded,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppSectionCard(
            child: InkWell(
              onTap: canEdit ? () => setState(() => _showAddMedicationForm = !_showAddMedicationForm) : null,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add Medication',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Icon(
                      _showAddMedicationForm ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: const Color(0xFF103A86),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_showAddMedicationForm) ...[
            const SizedBox(height: 12),
            AppSectionCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CareCrewTextField(
                      controller: _nameController,
                      label: 'Medicine Name',
                      hintText: 'e.g. Metformin',
                      validator: (value) => value == null || value.trim().isEmpty ? 'Medication name required' : null,
                    ),
                    const SizedBox(height: 14),
                    CareCrewTextField(
                      controller: _dosageController,
                      label: 'Dosage',
                      hintText: '500mg • 1 pill',
                      validator: (value) => value == null || value.trim().isEmpty ? 'Dosage required' : null,
                    ),
                    const SizedBox(height: 14),
                    CareCrewTextField(
                      controller: _stockController,
                      label: 'Current Stock',
                      hintText: 'e.g. 12',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Current stock required';
                        final parsed = int.tryParse(value.trim());
                        if (parsed == null || parsed < 0) return 'Enter a valid stock count';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: CareCrewTextField(
                            controller: _medStartDateDisplayController,
                            label: 'Start Date',
                            hintText: 'Pick start date',
                            readOnly: true,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _medStartDate,
                                firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                                lastDate: DateTime.now().add(const Duration(days: 3650)),
                              );
                              if (picked != null) {
                                setState(() {
                                  _medStartDate = _startOfDay(picked);
                                  _medStartDateDisplayController.text = DateFormat('MMM d, yyyy').format(_medStartDate);
                                });
                              }
                            },
                            suffixIcon: IconButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _medStartDate,
                                  firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _medStartDate = _startOfDay(picked);
                                    _medStartDateDisplayController.text = DateFormat('MMM d, yyyy').format(_medStartDate);
                                  });
                                }
                              },
                              icon: const Icon(Icons.calendar_month_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CareCrewTextField(
                            controller: _numDaysController,
                            label: 'Number of Days',
                            hintText: 'e.g. 7',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    CareCrewTextField(
                      controller: _timeDisplayController,
                      label: 'Time',
                      hintText: 'Choose time',
                      readOnly: true,
                      onTap: _pickTime,
                      suffixIcon: IconButton(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded)),
                      validator: (_) => _timeOfDay == null ? 'Pick a medication time' : null,
                    ),
                    const SizedBox(height: 14),
                    CareCrewTextField(
                      controller: _notesController,
                      label: 'Notes',
                      hintText: 'With food, before bedtime, etc.',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    CareCrewPrimaryButton(
                      label: _saving ? 'Saving...' : 'Save Medication',
                      onPressed: _saving || !canEdit ? null : _saveMedication,
                      leading: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ],
        ),
      );
  }
}

class VitalsScreen extends ConsumerStatefulWidget {
  const VitalsScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends ConsumerState<VitalsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _temperatureController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _notesController = TextEditingController();
  final _selectedDayDisplayController = TextEditingController();
  int _painLevel = 3;
  PlatformFile? _pickedPhoto;
  DateTime _selectedDay = _startOfDay(DateTime.now());
  bool _saving = false;

  List<DateTime> get _weekDays {
    final startOfWeek = _selectedDay.subtract(Duration(days: _selectedDay.weekday - 1));
    return List.generate(7, (index) => startOfWeek.add(Duration(days: index)));
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _notesController.dispose();
    _selectedDayDisplayController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.pickFiles(type: FileType.image, allowMultiple: false, withData: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedPhoto = result.files.single);
    }
  }

  Future<void> _pickSelectedDay() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _selectedDay,
    );
    if (picked != null) {
      setState(() {
        _selectedDay = _startOfDay(picked);
        _selectedDayDisplayController.text = _shortDate(_selectedDay);
      });
    }
  }

  Future<void> _openVitalEditor(VitalEntry entry) async {
    final formKey = GlobalKey<FormState>();
    final temperatureController = TextEditingController(text: entry.temperature.toStringAsFixed(1));
    final systolicController = TextEditingController(text: entry.systolic.toString());
    final diastolicController = TextEditingController(text: entry.diastolic.toString());
    final notesController = TextEditingController(text: entry.notes);
    var painLevel = entry.painLevel;
    var saving = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> submit() async {
                if (!formKey.currentState!.validate()) return;
                setDialogState(() => saving = true);
                try {
                  await ref.read(repositoryProvider).updateVitalEntry(
                        uid: widget.uid,
                        entry: VitalEntry(
                          id: entry.id,
                          temperature: double.parse(temperatureController.text.trim()),
                          systolic: int.parse(systolicController.text.trim()),
                          diastolic: int.parse(diastolicController.text.trim()),
                          painLevel: painLevel,
                          notes: notesController.text.trim(),
                          photoUrl: entry.photoUrl,
                          photoPath: entry.photoPath,
                          createdAt: entry.createdAt,
                        ),
                      );
                  ref.invalidate(vitalsProvider(widget.uid));
                  ref.invalidate(activityLogsProvider(widget.uid));
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => saving = false);
                  }
                }
              }

              return AlertDialog(
                title: const Text('Edit Vitals'),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CareCrewTextField(
                          controller: temperatureController,
                          label: 'Temperature (°F)',
                          hintText: '98.6',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) => value == null || double.tryParse(value.trim()) == null ? 'Enter a valid temperature' : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: CareCrewTextField(
                                controller: systolicController,
                                label: 'Systolic',
                                hintText: '120',
                                keyboardType: TextInputType.number,
                                validator: (value) => value == null || int.tryParse(value.trim()) == null ? 'Enter systolic' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CareCrewTextField(
                                controller: diastolicController,
                                label: 'Diastolic',
                                hintText: '80',
                                keyboardType: TextInputType.number,
                                validator: (value) => value == null || int.tryParse(value.trim()) == null ? 'Enter diastolic' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pain Level', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            Slider(
                              value: painLevel.toDouble(),
                              min: 0,
                              max: 10,
                              divisions: 10,
                              label: painLevel.toString(),
                              onChanged: (value) => setDialogState(() => painLevel = value.round()),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text('$painLevel / 10', style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        CareCrewTextField(
                          controller: notesController,
                          label: 'Additional Notes',
                          hintText: 'Describe symptoms or observations',
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving ? null : submit,
                    child: Text(saving ? 'Saving...' : 'Update'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      temperatureController.dispose();
      systolicController.dispose();
      diastolicController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _saveVitals() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    String? photoUrl;
    String? photoPath;
    try {
      final now = DateTime.now();
      if (_pickedPhoto != null) {
        final uploaded = await ref.read(repositoryProvider).uploadVitalPhoto(
              uid: widget.uid,
              file: _pickedPhoto!,
            );
        photoPath = uploaded['storagePath'];
        photoUrl = uploaded['downloadUrl'];
      }

      await ref.read(repositoryProvider).saveVitalEntry(
            uid: widget.uid,
            entry: VitalEntry(
              id: '',
              temperature: double.parse(_temperatureController.text.trim()),
              systolic: int.parse(_systolicController.text.trim()),
              diastolic: int.parse(_diastolicController.text.trim()),
              painLevel: _painLevel,
              notes: _notesController.text.trim(),
              photoUrl: photoUrl,
              photoPath: photoPath,
              createdAt: DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, now.hour, now.minute, now.second),
            ),
          );
      _temperatureController.clear();
      _systolicController.clear();
      _diastolicController.clear();
      _notesController.clear();
      setState(() {
        _painLevel = 3;
        _pickedPhoto = null;
      });
      ref.invalidate(vitalsProvider(widget.uid));
      ref.invalidate(activityLogsProvider(widget.uid));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedDayDisplayController.text = _shortDate(_selectedDay);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(careRoleProvider(widget.uid)).asData?.value ?? CaregiverRole.admin;
    final canEdit = role.canEdit;
    final vitalsAsync = ref.watch(vitalsProvider(widget.uid));
    final thresholdsAsync = ref.watch(thresholdsProvider(widget.uid));
    final latestVitals = vitalsAsync.value ?? const <VitalEntry>[];
    final thresholds = thresholdsAsync.value;
    final selectedVitals = latestVitals.where((vital) => vital.createdAt != null && DateUtils.isSameDay(vital.createdAt!, _selectedDay)).toList();
    final selectedLatest = selectedVitals.isNotEmpty ? selectedVitals.first : null;
    final weekDays = _weekDays;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitals'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text('C', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          Text(
            DateFormat('EEEE, MMM d, yyyy').format(_selectedDay),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Showing entries added on ${DateFormat('MMM d, yyyy').format(_selectedDay)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E779B)),
                ),
              ),
              IconButton(
                onPressed: _pickSelectedDay,
                icon: const Icon(Icons.calendar_month_rounded),
                tooltip: 'Pick a day',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekDays.map((dayDate) {
              final selected = DateUtils.isSameDay(dayDate, _selectedDay);
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = _startOfDay(dayDate)),
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF103A86) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${dayDate.day}',
                        style: TextStyle(
                          color: selected ? Colors.white : const Color(0xFF103A86),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('EEE').format(dayDate).toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF5E779B)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          AppSectionCard(
            borderColor: const Color(0xFFDDE9F6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Vitals added on ${DateFormat('MMM d').format(_selectedDay)}',
                  action: const SoftChip(label: 'Calendar linked'),
                ),
                const SizedBox(height: 10),
                if (selectedVitals.isEmpty)
                  const Text('No vitals were added on this day.')
                else
                  ...selectedVitals.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppSectionCard(
                        borderColor: entry.hasAlert ? const Color(0xFFB01E24) : const Color(0xFFDDE9F6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: entry.hasAlert ? const Color(0xFFF7D2D4) : const Color(0xFFE6F7E9),
                                  child: Icon(entry.hasAlert ? Icons.priority_high_rounded : Icons.favorite_rounded, color: entry.hasAlert ? const Color(0xFF8A1120) : const Color(0xFF1E7E3E)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.hasAlert ? (entry.alertLabel ?? 'Alert') : 'Vitals logged',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                      ),
                                      Text(_relativeTime(entry.createdAt ?? DateTime.now())),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _openVitalEditor(entry),
                                  icon: const Icon(Icons.edit_rounded),
                                  tooltip: 'Edit vitals',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('Temperature: ${entry.temperature.toStringAsFixed(1)}°F'),
                            Text('Blood Pressure: ${entry.systolic}/${entry.diastolic} mmHg'),
                            Text('Pain Level: ${entry.painLevel}/10'),
                            if (entry.notes.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(entry.notes),
                            ],
                            if (entry.photoUrl != null) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.network(entry.photoUrl!, height: 160, width: double.infinity, fit: BoxFit.cover),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (selectedLatest != null)
            AppSectionCard(
              borderColor: selectedLatest.hasAlert ? const Color(0xFFB01E24) : const Color(0xFFDDE9F6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: selectedLatest.hasAlert ? const Color(0xFFF7D2D4) : const Color(0xFFE6F7E9),
                    child: Icon(selectedLatest.hasAlert ? Icons.warning_amber_rounded : Icons.verified_rounded, color: selectedLatest.hasAlert ? const Color(0xFF8A1120) : const Color(0xFF1E7E3E)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedLatest.hasAlert ? selectedLatest.alertLabel ?? 'Alert' : 'Vitals within range', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('Logged ${_relativeTime(selectedLatest.createdAt ?? DateTime.now())}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          AppSectionCard(
            borderColor: thresholds == null || !thresholds.hasAnyThreshold ? const Color(0xFFDDE9F6) : const Color(0xFF103A86),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'Record Vitals', action: thresholds == null || !thresholds.hasAnyThreshold ? const SoftChip(label: 'No thresholds set') : const SoftChip(label: 'Thresholds active')),
                const SizedBox(height: 14),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CareCrewTextField(
                              controller: _temperatureController,
                              label: 'Temperature (°F)',
                              hintText: '98.6',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (value) => value == null || double.tryParse(value.trim()) == null ? 'Enter a valid temperature' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CareCrewTextField(
                              controller: _systolicController,
                              label: 'Systolic',
                              hintText: '120',
                              keyboardType: TextInputType.number,
                              validator: (value) => value == null || int.tryParse(value.trim()) == null ? 'Enter systolic' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: CareCrewTextField(
                              controller: _diastolicController,
                              label: 'Diastolic',
                              hintText: '80',
                              keyboardType: TextInputType.number,
                              validator: (value) => value == null || int.tryParse(value.trim()) == null ? 'Enter diastolic' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Pain Level', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                Slider(
                                  value: _painLevel.toDouble(),
                                  min: 0,
                                  max: 10,
                                  divisions: 10,
                                  label: _painLevel.toString(),
                                  onChanged: canEdit ? (value) => setState(() => _painLevel = value.round()) : null,
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text('$_painLevel / 10', style: const TextStyle(fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      CareCrewTextField(
                        controller: _notesController,
                        label: 'Additional Notes',
                        hintText: 'Describe symptoms or observations',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 14),
                      AppSectionCard(
                        backgroundColor: const Color(0xFFF8FBFF),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF103A86).withValues(alpha: 0.12),
                              child: const Icon(Icons.photo_camera_outlined, color: Color(0xFF103A86)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_pickedPhoto?.name ?? 'Optional photo', style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text(_pickedPhoto == null ? 'Tap to upload a photo of wounds, rashes or visible symptoms' : 'Selected photo will be stored in Firebase Storage', style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: canEdit ? _pickPhoto : null,
                              icon: const Icon(Icons.upload_rounded),
                              label: const Text('Upload'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      CareCrewPrimaryButton(
                        label: _saving ? 'Saving...' : 'Save Entry',
                        onPressed: _saving || !canEdit ? null : _saveVitals,
                        leading: const Icon(Icons.save_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (latestVitals.isEmpty)
            const EmptyStateCard(
              title: 'No vitals logged yet',
              subtitle: 'Add the first reading so alerts and trends can update in real time.',
              icon: Icons.monitor_heart_rounded,
            )
          else
            ...latestVitals.take(5).map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppSectionCard(
                  borderColor: entry.hasAlert ? const Color(0xFFB01E24) : const Color(0xFFDDE9F6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: entry.hasAlert ? const Color(0xFFF7D2D4) : const Color(0xFFE6F7E9),
                            child: Icon(entry.hasAlert ? Icons.priority_high_rounded : Icons.favorite_rounded, color: entry.hasAlert ? const Color(0xFF8A1120) : const Color(0xFF1E7E3E)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.hasAlert ? (entry.alertLabel ?? 'Alert') : 'Vitals logged',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                Text(_relativeTime(entry.createdAt ?? DateTime.now())),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Temperature: ${entry.temperature.toStringAsFixed(1)}°F'),
                      Text('Blood Pressure: ${entry.systolic}/${entry.diastolic} mmHg'),
                      Text('Pain Level: ${entry.painLevel}/10'),
                      if (entry.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(entry.notes),
                      ],
                      if (entry.photoUrl != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(entry.photoUrl!, height: 160, width: double.infinity, fit: BoxFit.cover),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _viewIndex = 0;

  Future<void> _clearHistory() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This will remove all activity feed entries for this care account.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear')),
        ],
      ),
    );

    if (shouldClear != true) return;
    try {
      await ref.read(repositoryProvider).clearActivityHistory(widget.uid);
      ref.invalidate(activityLogsProvider(widget.uid));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('History cleared successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear history: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(careRoleProvider(widget.uid)).asData?.value ?? CaregiverRole.admin;
    final canEdit = role.canEdit;
    final authUser = ref.watch(authStateProvider).value;
    final logs = ref.watch(activityLogsProvider(authUser?.uid ?? widget.uid)).value ?? const <ActivityLogEntry>[];
    final meds = ref.watch(medicationsProvider(widget.uid)).value ?? const <MedicationEntry>[];
    final appointments = ref.watch(appointmentsProvider(widget.uid)).value ?? const <AppointmentEntry>[];
    final vitals = ref.watch(vitalsProvider(widget.uid)).value ?? const <VitalEntry>[];
    final patient = ref.watch(patientProfileProvider(widget.uid)).value;
    final repo = ref.read(repositoryProvider);
    final today = _startOfDay(DateTime.now());
    final trendDays = List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));

    final thirtyDaysAgo = repo.thirtyDaysAgo();
    final sevenDaysAgo = repo.sevenDaysAgo();
    final recentLogs = repo.logsForRange(logs, thirtyDaysAgo);
    final recentVitals = repo.vitalsForRange(vitals, sevenDaysAgo);
    final adherence = repo.medicationAdherencePercent(recentLogs);
    final attendance = repo.appointmentAttendancePercent(appointments);
    final missedCount = recentLogs.where((log) => log.type == 'medication_missed').length;
    final alerts = recentLogs.where((log) => log.type == 'critical_alert').toList();
    String? mostMissedMedicationName;
    var mostMissedMedicationCount = 0;
    for (final medication in meds) {
      final missedForMedication = recentLogs.where((log) => log.type == 'medication_missed' && log.details.contains(medication.name)).length;
      if (missedForMedication > mostMissedMedicationCount) {
        mostMissedMedicationCount = missedForMedication;
        mostMissedMedicationName = medication.name;
      }
    }
    final latestRecentVital = recentVitals.isNotEmpty ? recentVitals.first : null;
    final vitalsByDay = <String, VitalEntry>{};
    for (final entry in recentVitals) {
      final createdAt = entry.createdAt;
      if (createdAt == null) continue;
      final key = _dayKey(createdAt);
      final existing = vitalsByDay[key];
      if (existing == null || (existing.createdAt != null && createdAt.isAfter(existing.createdAt!))) {
        vitalsByDay[key] = entry;
      }
    }
    final systolicSpots = <FlSpot>[];
    final temperatureSpots = <FlSpot>[];
    for (var index = 0; index < trendDays.length; index++) {
      final key = _dayKey(trendDays[index]);
      final entry = vitalsByDay[key];
      final previousSystolic = systolicSpots.isNotEmpty ? systolicSpots.last.y : null;
      final previousTemperature = temperatureSpots.isNotEmpty ? temperatureSpots.last.y : null;
      systolicSpots.add(FlSpot(index.toDouble(), entry?.systolic.toDouble() ?? previousSystolic ?? 0));
      temperatureSpots.add(FlSpot(index.toDouble(), entry?.temperature ?? previousTemperature ?? 0));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            onPressed: canEdit ? _clearHistory : null,
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear History',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text('C', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE3EAF3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SegmentedButton<int>(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? const Color(0xFF103A86) : Colors.transparent,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? Colors.white : Colors.black,
                ),
              ),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Care History')),
                ButtonSegment(value: 1, label: Text('Doctor\'s View')),
              ],
              selected: {_viewIndex},
              onSelectionChanged: (selection) => setState(() => _viewIndex = selection.first),
            ),
          ),
          const SizedBox(height: 18),
          if (_viewIndex == 0) ...[
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: '30-Day Overview'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      StatCard(label: 'Medication Adherence', value: '$adherence%', subtitle: 'Last 30 days', color: const Color(0xFFF9F2C8), icon: Icons.check_circle_rounded),
                      const SizedBox(width: 12),
                      StatCard(label: 'Appointments Kept', value: '${appointments.where((a) => a.statusValue == AppointmentStatus.completed).length}', subtitle: '${appointments.length} tracked', color: const Color(0xFFDDE3F7), icon: Icons.event_available_rounded),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: 'Medication Adherence', action: const SoftChip(label: 'Summary only')),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F2C8),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Medication adherence: $adherence%', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF103A86))),
                        const SizedBox(height: 4),
                        Text('Missed doses (30 days): $missedCount', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Text(
                          mostMissedMedicationName == null || mostMissedMedicationCount == 0
                              ? 'Most missed: None'
                              : 'Most missed: $mostMissedMedicationName ($mostMissedMedicationCount time${mostMissedMedicationCount == 1 ? '' : 's'})',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Appointment Attendance'),
                  const SizedBox(height: 14),
                  if (appointments.isEmpty)
                    const Text('No appointments recorded yet.')
                  else
                    ...appointments.take(3).map(
                      (appointment) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFFF9F6EA), borderRadius: BorderRadius.circular(18)),
                          child: Row(
                            children: [
                              const CircleAvatar(backgroundColor: Color(0xFF103A86), child: Icon(Icons.check_rounded, color: Colors.white)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${appointment.doctorName} - ${appointment.location}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    Text(_shortDate(appointment.appointmentDateTime)),
                                  ],
                                ),
                              ),
                              SoftChip(label: appointment.statusValue.label, color: const Color(0xFFDDE9F6)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text('$attendance% attendance rate', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (vitals.isNotEmpty)
              AppSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Latest Clinical Note'),
                    const SizedBox(height: 10),
                    Text(vitals.first.notes.isEmpty ? 'No note added.' : vitals.first.notes),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            CareCrewPrimaryButton(
              label: 'Activity Feed →',
              leading: const Icon(Icons.receipt_long_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(uid: widget.uid))),
            ),
          ] else ...[
            Text(
              'Summary for ${patient?.fullName.isNotEmpty == true ? patient!.fullName : 'this care account'} (Last 7 Days)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: const Color(0xFF4A678A), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            AppSectionCard(
              borderColor: alerts.isEmpty ? const Color(0xFFDDE9F6) : const Color(0xFF8A1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Critical Events'),
                  const SizedBox(height: 10),
                  if (alerts.isEmpty)
                    const Text('No critical alerts in the last 30 days.')
                  else
                    ...alerts.take(3).map((alert) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SoftChip(label: alert.title, color: const Color(0xFFF7D2D4), textColor: const Color(0xFF8A1120)),
                        )),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Recent Medications'),
                  const SizedBox(height: 10),
                  if (meds.isEmpty)
                    const Text('No medications added yet.')
                  else
                    ...meds.take(4).map(
                      (medication) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: medication.status == 'missed' ? const Color(0xFFFCE7E8) : const Color(0xFFFFF6D5),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(backgroundColor: Color(0xFF103A86), child: Icon(Icons.medication, color: Colors.white)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(medication.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    Text('${medication.dosage} • ${medication.timeLabel}'),
                                  ],
                                ),
                              ),
                              Text(medication.status.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (missedCount > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7DDE0),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$missedCount Missed Doses (Last 30 Days)',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A1120)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            mostMissedMedicationName == null || mostMissedMedicationCount == 0
                                ? 'Most missed: None'
                                : 'Most missed: $mostMissedMedicationName ($mostMissedMedicationCount time${mostMissedMedicationCount == 1 ? '' : 's'})',
                            style: const TextStyle(color: Color(0xFF8A1120)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: '7-Day Trend'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _TrendSummaryCard(
                          label: 'Blood Pressure',
                          value: latestRecentVital == null ? '0/0' : '${latestRecentVital.systolic}/${latestRecentVital.diastolic}',
                          color: const Color(0xFFDDE3F7),
                          points: systolicSpots.map((spot) => spot.y).toList(),
                          valueStyleSize: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TrendSummaryCard(
                          label: 'Temperature',
                          value: latestRecentVital == null ? '0.0°' : '${latestRecentVital.temperature.toStringAsFixed(1)}°F',
                          color: const Color(0xFFFFF6D5),
                          points: temperatureSpots.map((spot) => spot.y).toList(),
                          valueStyleSize: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Latest Clinical Note'),
                  const SizedBox(height: 10),
                  Text(vitals.isEmpty || vitals.first.notes.isEmpty ? 'No recent clinical note.' : vitals.first.notes),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CareCrewPrimaryButton(
              label: 'Export Report',
              leading: const Icon(Icons.upload_file_rounded),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export feature can be wired to PDF generation if needed.')));
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendSummaryCard extends StatelessWidget {
  const _TrendSummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.points,
    required this.valueStyleSize,
  });

  final String label;
  final String value;
  final Color color;
  final List<double> points;
  final double valueStyleSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6B7E9B)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: valueStyleSize, fontWeight: FontWeight.w900, color: const Color(0xFF103A86)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, 34),
                  painter: _SparklinePainter(
                    points: points,
                    color: const Color(0xFF103A86),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final maxValue = points.reduce(math.max);
    final minValue = points.reduce(math.min);
    final range = (maxValue - minValue).abs() < 0.001 ? 1.0 : maxValue - minValue;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1 ? size.width / 2 : (index / (points.length - 1)) * size.width;
      final normalized = (points[index] - minValue) / range;
      final y = size.height - (normalized * (size.height - 4)) - 2;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

class CareCircleScreen extends ConsumerStatefulWidget {
  const CareCircleScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<CareCircleScreen> createState() => _CareCircleScreenState();
}

class _CareCircleScreenState extends ConsumerState<CareCircleScreen> {
  final _noteController = TextEditingController();
  bool _savingNote = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _addCareNote() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a note first.')));
      return;
    }

    setState(() => _savingNote = true);
    try {
      final actor = ref.read(currentUserProfileProvider(widget.uid)).value?.displayName;
      await ref.read(repositoryProvider).addActivityLog(
            uid: widget.uid,
            type: 'care_note_added',
            title: 'Care note added',
            details: note,
            actor: (actor == null || actor.isEmpty) ? 'Caregiver' : actor,
          );
      _noteController.clear();
      ref.invalidate(activityLogsProvider(widget.uid));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note added to latest updates.')),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _openAddNoteDialog() async {
    _noteController.clear();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(
          controller: _noteController,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Write an update for the care circle...'),
        ),
        actions: [
          TextButton(
            onPressed: _savingNote ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _savingNote
                ? null
                : () async {
                    await _addCareNote();
                    if (context.mounted) Navigator.pop(context);
                  },
            child: Text(_savingNote ? 'Saving...' : 'Save Note'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(careRoleProvider(widget.uid)).asData?.value ?? CaregiverRole.admin;
    final canEdit = role.canEdit;
    final caregivers = ref.watch(caregiversProvider(widget.uid)).value ?? const <CaregiverEntry>[];
    final logs = ref.watch(activityLogsProvider(widget.uid)).value ?? const <ActivityLogEntry>[];
    ActivityLogEntry? latestCareNote;
    for (final entry in logs) {
      if (entry.type == 'care_note_added') {
        latestCareNote = entry;
        break;
      }
    }
    ActivityLogEntry? latestClinical;
    for (final entry in logs) {
      if (entry.type == 'medication_taken' || entry.type == 'vitals_logged') {
        latestClinical = entry;
        break;
      }
    }
    final latestUpdate = latestCareNote ?? latestClinical;

    return Scaffold(
      backgroundColor: const Color(0xFFCFE6F7),
      appBar: AppBar(
        title: const Text('Care Circle'),
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Icon(Icons.person_rounded, color: Color(0xFF103A86)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
        children: [
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SoftChip(label: 'Latest Update', color: Color(0xFFF7D7E6), textColor: Color(0xFF8B3A68)),
                const SizedBox(height: 12),
                Text(
                  latestUpdate == null ? 'No updates yet' : '"${latestUpdate.details}"',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (latestUpdate?.actor.isNotEmpty == true)
                  Text('Posted by ${latestUpdate!.actor} • ${_relativeTime(latestUpdate.createdAt ?? DateTime.now())}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: canEdit ? _openAddNoteDialog : null,
                    icon: const Icon(Icons.note_add_rounded),
                    label: const Text('Add Note'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionHeader(
            title: 'Team Members (${caregivers.length})',
          ),
          const SizedBox(height: 10),
          if (caregivers.isEmpty)
            const EmptyStateCard(
              title: 'No caregivers added yet',
              subtitle: 'Invite family or professionals to keep everyone aligned.',
              icon: Icons.groups_rounded,
            )
          else
            ...caregivers.map(
              (caregiver) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppSectionCard(
                  backgroundColor: caregiver.inviteStatus == 'pending' ? const Color(0xFFE7F3FD) : Colors.white,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFFF2D7E8),
                        child: Text(caregiver.name.isNotEmpty ? caregiver.name[0].toUpperCase() : 'C', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(caregiver.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                            Text(
                              caregiver.inviteStatus == 'pending'
                                  ? 'Invite sent'
                                  : (caregiver.relationship.trim().isEmpty ? caregiver.contact : caregiver.relationship),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                SoftChip(label: caregiver.roleValue.label, color: _statusColor(caregiver.role).withValues(alpha: 0.16), textColor: _statusColor(caregiver.role)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (canEdit && caregiver.canEdit)
                        IconButton(
                          onPressed: () async {
                            await ref.read(repositoryProvider).deleteCaregiver(uid: widget.uid, caregiverId: caregiver.id);
                            ref.invalidate(caregiversProvider(widget.uid));
                            ref.invalidate(activityLogsProvider(widget.uid));
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        )
                      else
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.lock_outline_rounded),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: canEdit
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AddCaregiverScreen(uid: widget.uid)),
                    )
                : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Invite to Circle'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              backgroundColor: const Color(0xFF103A86),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class AddCaregiverScreen extends ConsumerStatefulWidget {
  const AddCaregiverScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<AddCaregiverScreen> createState() => _AddCaregiverScreenState();
}

class _AddCaregiverScreenState extends ConsumerState<AddCaregiverScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _relationshipController = TextEditingController();
  CaregiverRole _role = CaregiverRole.editor;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  String _generateInviteCode() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return random.substring(random.length - 6);
  }

  Future<void> _inviteCaregiver() async {
    if (_nameController.text.trim().isEmpty || _emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter caregiver name and email.')));
      return;
    }

    final inviteEmail = _emailController.text.trim().toLowerCase();
    final emailError = InputValidators.email(inviteEmail);
    if (emailError != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email address.')));
      return;
    }

    final mobileError = InputValidators.phone(
      _mobileController.text,
      required: false,
      fieldLabel: 'mobile number',
    );
    if (mobileError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mobileError)));
      return;
    }

    setState(() => _saving = true);
    try {
      final inviteCode = _generateInviteCode();
      await ref.read(repositoryProvider).saveCaregiver(
            uid: widget.uid,
            caregiver: CaregiverEntry(
              id: '',
              name: _nameController.text.trim(),
              contact: inviteEmail,
              mobile: InputValidators.normalizePhone(_mobileController.text),
              role: _role.name,
              relationship: _relationshipController.text.trim(),
              inviteStatus: 'pending',
              inviteCode: inviteCode,
            ),
          );

      _nameController.clear();
      _emailController.clear();
      _mobileController.clear();
      _relationshipController.clear();
      setState(() => _role = CaregiverRole.editor);
      ref.invalidate(caregiversProvider(widget.uid));
      ref.invalidate(activityLogsProvider(widget.uid));

      if (mounted) {
        final testDeepLink = 'carecrew://accept-invite/$inviteCode?email=${Uri.encodeComponent(inviteEmail)}&uid=${Uri.encodeComponent(widget.uid)}';
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Invitation Created'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invitation created for $inviteEmail'),
                  const SizedBox(height: 12),
                  const Text('📧 Email Status:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('When Cloud Functions is deployed, this caregiver will receive an email with the acceptance link.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  const Text('🔗 Test Link (Development):', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
                    child: SelectableText(testDeepLink, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                  ),
                  const SizedBox(height: 12),
                  const Text('Use this link to test the acceptance flow on your device.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Share.share(
                    'You are invited to join CareCrew. Open this link to accept:\n\n$testDeepLink',
                    subject: 'CareCrew Invitation',
                  );
                },
                child: const Text('Share'),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: testDeepLink));
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
                  Navigator.pop(context);
                },
                child: const Text('Copy Link'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Caregiver')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        children: [
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Invite to Circle'),
                const SizedBox(height: 14),
                CareCrewTextField(controller: _nameController, label: 'Name', hintText: 'Caregiver name'),
                const SizedBox(height: 14),
                CareCrewTextField(controller: _emailController, label: 'Email', hintText: 'caregiver@example.com'),
                const SizedBox(height: 14),
                CareCrewTextField(controller: _mobileController, label: 'Mobile Number', hintText: '+91XXXXXXXXXX'),
                const SizedBox(height: 14),
                CareCrewTextField(controller: _relationshipController, label: 'Relationship', hintText: 'Spouse, nurse, daughter...'),
                const SizedBox(height: 14),
                DropdownButtonFormField<CaregiverRole>(
                  initialValue: _role,
                  items: CaregiverRole.values.map((role) => DropdownMenuItem(value: role, child: Text(role.label))).toList(),
                  onChanged: (value) => setState(() => _role = value ?? CaregiverRole.editor),
                  decoration: const InputDecoration(labelText: 'Role'),
                ),
                const SizedBox(height: 14),
                CareCrewPrimaryButton(
                  label: _saving ? 'Sending...' : 'Add Caregiver',
                  onPressed: _saving ? null : _inviteCaregiver,
                  leading: const Icon(Icons.person_add_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ActivityRange { all, today, week }

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  _ActivityRange _range = _ActivityRange.all;

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(activityLogsProvider(widget.uid)).value ?? const <ActivityLogEntry>[];
    final repo = ref.read(repositoryProvider);
    final filteredLogs = switch (_range) {
      _ActivityRange.today => repo.logsForRange(logs, repo.startOfToday()),
      _ActivityRange.week => repo.logsForRange(logs, repo.sevenDaysAgo()),
      _ActivityRange.all => logs,
    };

    Widget filterChip({
      required _ActivityRange value,
      required String label,
    }) {
      final selected = _range == value;
      return GestureDetector(
        onTap: () => setState(() => _range = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF103A86) : Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text('C', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFF103A86), borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                filterChip(value: _ActivityRange.all, label: 'All Activity'),
                filterChip(value: _ActivityRange.today, label: 'Today'),
                filterChip(value: _ActivityRange.week, label: 'This Week'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (filteredLogs.isEmpty)
            const EmptyStateCard(
              title: 'No activity yet',
              subtitle: 'Every action, note, and health log will appear here in real time.',
              icon: Icons.timeline_rounded,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: math.max(500, filteredLogs.length * 110).toDouble(),
                  decoration: BoxDecoration(color: const Color(0xFF8FC2F1), borderRadius: BorderRadius.circular(999)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: filteredLogs
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AppSectionCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _statusColor(entry.type).withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(_iconForLog(entry.type), color: _statusColor(entry.type), size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                                        const SizedBox(height: 4),
                                        Text(entry.details),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Icon(Icons.person_outline, size: 16, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(entry.actor, style: TextStyle(color: Colors.grey.shade600)),
                                            const SizedBox(width: 14),
                                            Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(_relativeTime(entry.createdAt ?? DateTime.now()), style: TextStyle(color: Colors.grey.shade600)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

IconData _iconForLog(String type) {
  switch (type) {
    case 'medication_taken':
      return Icons.medication_rounded;
    case 'medication_missed':
      return Icons.warning_amber_rounded;
    case 'vitals_logged':
    case 'critical_alert':
      return Icons.monitor_heart_rounded;
    case 'appointment_added':
      return Icons.event_available_rounded;
    case 'document_uploaded':
      return Icons.description_rounded;
    default:
      return Icons.notes_rounded;
  }
}

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  bool _uploading = false;

  Future<void> _uploadDocument() async {
    final result = await FilePicker.pickFiles(type: FileType.any, allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      await ref.read(repositoryProvider).uploadDocument(uid: widget.uid, file: result.files.single);
      ref.invalidate(documentsProvider(widget.uid));
      ref.invalidate(activityLogsProvider(widget.uid));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider(widget.uid)).value ?? const <DocumentEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text('C', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          AppSectionCard(
            borderColor: const Color(0xFFA3B7CC),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFFE0E5EE),
                  child: Icon(Icons.add, size: 34, color: Color(0xFF103A86)),
                ),
                const SizedBox(height: 12),
                Text('Upload New Document', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Tap to add prescriptions, lab reports, or instructions', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _uploadDocument,
                  icon: const Icon(Icons.upload_rounded),
                  label: Text(_uploading ? 'Uploading...' : 'Upload File'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: const BorderSide(color: Color(0xFF103A86)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (docs.isEmpty)
            const EmptyStateCard(
              title: 'No documents yet',
              subtitle: 'Upload discharge summaries, prescriptions, and lab reports here.',
              icon: Icons.folder_open_rounded,
            )
          else
            ...docs.map(
              (document) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(document.fileName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text('${_shortDate(document.createdAt ?? DateTime.now())} • ${(document.fileSizeBytes / 1024).toStringAsFixed(1)} KB • ${document.mimeType.toUpperCase()}'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CareCrewPrimaryButton(
                              label: 'View',
                              onPressed: () => _launchExternal(document.downloadUrl),
                              leading: const Icon(Icons.visibility_rounded),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            onPressed: () => _launchExternal(document.downloadUrl),
                            icon: const Icon(Icons.download_rounded),
                            style: IconButton.styleFrom(backgroundColor: const Color(0xFFE8EEF8), foregroundColor: const Color(0xFF103A86)),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () async {
                              await ref.read(repositoryProvider).deleteDocument(uid: widget.uid, document: document);
                              ref.invalidate(documentsProvider(widget.uid));
                              ref.invalidate(activityLogsProvider(widget.uid));
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            style: IconButton.styleFrom(backgroundColor: const Color(0xFFF7D2D4), foregroundColor: const Color(0xFF8A1120)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _doctorController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  AppointmentStatus _status = AppointmentStatus.scheduled;
  bool _saving = false;

  @override
  void dispose() {
    _doctorController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 3650)), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: _date ?? DateTime.now());
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateController.text = _shortDate(picked);
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
    if (picked != null) {
      setState(() {
        _time = picked;
        _timeController.text = picked.format(context);
      });
    }
  }

  Future<void> _saveAppointment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null || _time == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select both date and time.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final appointmentDateTime = DateTime(_date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
      await ref.read(repositoryProvider).saveAppointment(
            uid: widget.uid,
            appointment: AppointmentEntry(
              id: '',
              doctorName: _doctorController.text.trim(),
              appointmentDateTime: appointmentDateTime,
              location: _locationController.text.trim(),
              status: _status.name,
              notes: _notesController.text.trim(),
            ),
          );
      _doctorController.clear();
      _locationController.clear();
      _notesController.clear();
      setState(() {
        _date = null;
        _time = null;
        _status = AppointmentStatus.scheduled;
        _dateController.clear();
        _timeController.clear();
      });
      ref.invalidate(appointmentsProvider(widget.uid));
      ref.invalidate(activityLogsProvider(widget.uid));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appointments = ref.watch(appointmentsProvider(widget.uid)).value ?? const <AppointmentEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text('C', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          AppSectionCard(
            backgroundColor: const Color(0xFF103A86),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Next Appointment', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text(
                        appointments.isEmpty
                            ? 'None'
                            : 'In ${appointments.first.appointmentDateTime.difference(DateTime.now()).inDays.abs()} days',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total Upcoming', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text(
                        '${appointments.where((a) => a.appointmentDateTime.isAfter(DateTime.now())).length}',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppSectionCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Add Appointment'),
                  const SizedBox(height: 14),
                  CareCrewTextField(controller: _doctorController, label: 'Doctor Name', hintText: 'Dr. Name', validator: (value) => value == null || value.trim().isEmpty ? 'Doctor name required' : null),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: CareCrewTextField(
                          controller: _dateController,
                          label: 'Date',
                          hintText: 'Choose date',
                          readOnly: true,
                          onTap: _pickDate,
                          suffixIcon: IconButton(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_rounded)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CareCrewTextField(
                          controller: _timeController,
                          label: 'Time',
                          hintText: 'Choose time',
                          readOnly: true,
                          onTap: _pickTime,
                          suffixIcon: IconButton(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CareCrewTextField(controller: _locationController, label: 'Location', hintText: 'Clinic or hospital name', validator: (value) => value == null || value.trim().isEmpty ? 'Location required' : null),
                  const SizedBox(height: 14),
                  CareCrewTextField(controller: _notesController, label: 'Notes', hintText: 'What should caregivers prepare?', maxLines: 3),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<AppointmentStatus>(
                    initialValue: _status,
                    items: AppointmentStatus.values.map((status) => DropdownMenuItem(value: status, child: Text(status.label))).toList(),
                    onChanged: (value) => setState(() => _status = value ?? AppointmentStatus.scheduled),
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                  const SizedBox(height: 14),
                  CareCrewPrimaryButton(label: _saving ? 'Saving...' : 'Save Appointment', onPressed: _saving ? null : _saveAppointment, leading: const Icon(Icons.event_available_rounded)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (appointments.isEmpty)
            const EmptyStateCard(
              title: 'No appointments yet',
              subtitle: 'Future follow-ups and visits will appear here.',
              icon: Icons.event_note_rounded,
            )
          else
            ...appointments.map(
              (appointment) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppSectionCard(
                  backgroundColor: appointment.statusValue == AppointmentStatus.completed ? const Color(0xFFE6F7E9) : Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(backgroundColor: Color(0xFF103A86), child: Icon(Icons.person, color: Colors.white)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(appointment.doctorName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                                Text('Status: ${appointment.statusValue.label}'),
                              ],
                            ),
                          ),
                          SoftChip(label: appointment.statusValue.label, color: const Color(0xFFDDE9F6)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('${_longDate(appointment.appointmentDateTime)} • ${_shortTime(appointment.appointmentDateTime)}'),
                      Text(appointment.location),
                      if (appointment.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(appointment.notes),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await ref.read(repositoryProvider).updateAppointmentStatus(uid: widget.uid, appointmentId: appointment.id, status: AppointmentStatus.completed);
                              ref.invalidate(appointmentsProvider(widget.uid));
                              ref.invalidate(activityLogsProvider(widget.uid));
                            },
                            icon: const Icon(Icons.check_circle_rounded),
                            label: const Text('Mark Completed'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await ref.read(repositoryProvider).updateAppointmentStatus(uid: widget.uid, appointmentId: appointment.id, status: AppointmentStatus.cancelled);
                              ref.invalidate(appointmentsProvider(widget.uid));
                              ref.invalidate(activityLogsProvider(widget.uid));
                            },
                            icon: const Icon(Icons.cancel_rounded),
                            label: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _tempController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _painController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _tempController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _painController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(careRoleProvider(widget.uid)).asData?.value ?? CaregiverRole.viewer;
    final canEditThresholds = role.canEditThresholds;
    final thresholds = ref.watch(thresholdsProvider(widget.uid)).value;
    if (thresholds != null && !_tempController.text.isNotEmpty && !_systolicController.text.isNotEmpty && !_diastolicController.text.isNotEmpty && !_painController.text.isNotEmpty) {
      _tempController.text = thresholds.temperatureHigh?.toString() ?? '';
      _systolicController.text = thresholds.systolicHigh?.toString() ?? '';
      _diastolicController.text = thresholds.diastolicHigh?.toString() ?? '';
      _painController.text = thresholds.painHigh?.toString() ?? '';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Vitals Thresholds'),
                const SizedBox(height: 6),
                Text('Leave a field empty if the alert should not use that threshold.', style: Theme.of(context).textTheme.bodyMedium),
                if (!canEditThresholds) ...[
                  const SizedBox(height: 10),
                  const SoftChip(label: 'View only'),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: CareCrewTextField(controller: _tempController, label: 'Temp High', hintText: '101.0', keyboardType: const TextInputType.numberWithOptions(decimal: true), readOnly: !canEditThresholds)),
                    const SizedBox(width: 12),
                    Expanded(child: CareCrewTextField(controller: _systolicController, label: 'Systolic High', hintText: '140', keyboardType: TextInputType.number, readOnly: !canEditThresholds)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: CareCrewTextField(controller: _diastolicController, label: 'Diastolic High', hintText: '90', keyboardType: TextInputType.number, readOnly: !canEditThresholds)),
                    const SizedBox(width: 12),
                    Expanded(child: CareCrewTextField(controller: _painController, label: 'Pain High', hintText: '7', keyboardType: TextInputType.number, readOnly: !canEditThresholds)),
                  ],
                ),
                const SizedBox(height: 16),
                CareCrewPrimaryButton(
                  label: _saving ? 'Saving...' : 'Save Thresholds',
                  onPressed: _saving || !canEditThresholds
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref.read(repositoryProvider).saveThresholds(
                                  uid: widget.uid,
                                  thresholds: ThresholdConfig(
                                    id: 'default',
                                    temperatureHigh: double.tryParse(_tempController.text.trim()),
                                    systolicHigh: int.tryParse(_systolicController.text.trim()),
                                    diastolicHigh: int.tryParse(_diastolicController.text.trim()),
                                    painHigh: int.tryParse(_painController.text.trim()),
                                  ),
                                );
                            ref.invalidate(thresholdsProvider(widget.uid));
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Thresholds saved successfully.')),
                              );
                            }
                          } catch (error) {
                            if (mounted) messenger.showSnackBar(SnackBar(content: Text(error.toString())));
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  leading: const Icon(Icons.shield_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Important Notes'),
                const SizedBox(height: 8),
                const Text('All data stays inside users/{userId}/... and is isolated per authenticated user. Threshold values should only be set by a certified doctor.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider(widget.uid)).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          AppSectionCard(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: const Color(0xFF103A86),
                  child: Text(profile?.displayName.isNotEmpty == true ? profile!.displayName[0].toUpperCase() : 'C', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 14),
                Text(profile?.displayName ?? 'Caregiver', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(profile?.email ?? ''),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ProfileMenuItem(
            icon: Icons.edit_note_rounded,
            title: 'Edit Profile',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EditProfileDetailsScreen(uid: widget.uid)),
            ),
          ),
          _ProfileMenuItem(icon: Icons.event_note_outlined, title: 'Appointments', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentsScreen(uid: widget.uid)))),
          _ProfileMenuItem(icon: Icons.description_outlined, title: 'Documents', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocumentsScreen(uid: widget.uid)))),
          _ProfileMenuItem(icon: Icons.receipt_long_outlined, title: 'Activity', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(uid: widget.uid)))),
          _ProfileMenuItem(icon: Icons.tune_rounded, title: 'Settings', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(uid: widget.uid)))),
          const SizedBox(height: 10),
          CareCrewPrimaryButton(
            label: 'Logout',
            onPressed: () async {
              await ref.read(repositoryProvider).signOut();
              if (!context.mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            leading: const Icon(Icons.logout_rounded),
            backgroundColor: const Color(0xFF8A1120),
          ),
        ],
      ),
    );
  }
}

class EditProfileDetailsScreen extends ConsumerStatefulWidget {
  const EditProfileDetailsScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<EditProfileDetailsScreen> createState() => _EditProfileDetailsScreenState();
}

class _EditProfileDetailsScreenState extends ConsumerState<EditProfileDetailsScreen> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _patientNameController = TextEditingController();
  final _patientAgeController = TextEditingController();
  final _patientConditionController = TextEditingController();
  final _patientEmergencyContactController = TextEditingController();
  final _patientDischargeController = TextEditingController();

  final _caregiverFormKey = GlobalKey<FormState>();
  final _patientFormKey = GlobalKey<FormState>();

  bool _loaded = false;
  bool _patientLoaded = false;
  bool _savingCaregiver = false;
  bool _savingPatient = false;
  DateTime? _patientDischargeDate;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _patientNameController.dispose();
    _patientAgeController.dispose();
    _patientConditionController.dispose();
    _patientEmergencyContactController.dispose();
    _patientDischargeController.dispose();
    super.dispose();
  }

  Future<void> _pickPatientDischargeDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _patientDischargeDate ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _patientDischargeDate = picked;
        _patientDischargeController.text = _shortDate(picked);
      });
    }
  }

  Future<void> _saveCaregiverProfile() async {
    if (!_caregiverFormKey.currentState!.validate()) return;
    setState(() => _savingCaregiver = true);
    try {
      await ref.read(repositoryProvider).updateUserProfile(
            uid: widget.uid,
            displayName: _nameController.text.trim(),
            mobileNumber: InputValidators.normalizePhone(_mobileController.text),
          );
      if (!mounted) return;
      ref.invalidate(currentUserProfileProvider(widget.uid));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile details updated.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _savingCaregiver = false);
    }
  }

  Future<void> _savePatientDetails() async {
    if (!_patientFormKey.currentState!.validate()) return;
    if (_patientDischargeDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please choose discharge date.')));
      return;
    }
    setState(() => _savingPatient = true);
    try {
      final existingPatient = await ref
          .read(repositoryProvider)
          .firestore
          .collection('users')
          .doc(widget.uid)
          .collection('patient')
          .doc('main')
          .get();
      final hadPatientProfile = existingPatient.exists;

      await ref.read(repositoryProvider).savePatientProfile(
            uid: widget.uid,
            profile: PatientProfile(
              id: 'main',
              fullName: _patientNameController.text.trim(),
              age: int.parse(_patientAgeController.text.trim()),
              dischargeDate: _patientDischargeDate!,
              condition: _patientConditionController.text.trim(),
              emergencyContact: InputValidators.normalizePhone(_patientEmergencyContactController.text),
            ),
          );
      if (!mounted) return;
      ref.invalidate(patientProfileProvider(widget.uid));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patient details updated.')));
      if (!hadPatientProfile) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AddCaregiverScreen(uid: widget.uid)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _savingPatient = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider(widget.uid)).value;
    final patient = ref.watch(patientProfileProvider(widget.uid)).value;

    if (profile != null && !_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _nameController.text = profile.displayName;
        _mobileController.text = profile.mobileNumber;
      });
    }
    if (patient != null && !_patientLoaded) {
      _patientLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _patientNameController.text = patient.fullName;
        _patientAgeController.text = patient.age.toString();
        _patientConditionController.text = patient.condition;
        _patientEmergencyContactController.text = patient.emergencyContact;
        _patientDischargeDate = patient.dischargeDate;
        _patientDischargeController.text = _shortDate(patient.dischargeDate);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        children: [
          AppSectionCard(
            child: Form(
              key: _caregiverFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Edit Profile Details'),
                  const SizedBox(height: 12),
                  CareCrewTextField(
                    controller: _nameController,
                    label: 'Full Name',
                    hintText: 'Enter your full name',
                    validator: (value) => value == null || value.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  CareCrewTextField(
                    controller: _mobileController,
                    label: 'Mobile Number',
                    hintText: 'Enter mobile number',
                    keyboardType: TextInputType.phone,
                    validator: (value) => InputValidators.phone(value, required: false, fieldLabel: 'mobile number'),
                  ),
                  const SizedBox(height: 12),
                  CareCrewPrimaryButton(
                    label: _savingCaregiver ? 'Saving...' : 'Save Profile',
                    onPressed: _savingCaregiver ? null : _saveCaregiverProfile,
                    leading: const Icon(Icons.save_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppSectionCard(
            child: Form(
              key: _patientFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Edit Patient Details'),
                  const SizedBox(height: 12),
                  CareCrewTextField(
                    controller: _patientNameController,
                    label: 'Patient Full Name',
                    hintText: 'Enter patient name',
                    validator: (value) => value == null || value.trim().isEmpty ? 'Patient name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CareCrewTextField(
                          controller: _patientAgeController,
                          label: 'Age',
                          hintText: 'Enter age',
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
                          controller: _patientDischargeController,
                          label: 'Discharge Date',
                          hintText: 'Choose date',
                          readOnly: true,
                          onTap: _pickPatientDischargeDate,
                          suffixIcon: IconButton(
                            onPressed: _pickPatientDischargeDate,
                            icon: const Icon(Icons.calendar_month_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CareCrewTextField(
                    controller: _patientConditionController,
                    label: 'Primary Condition',
                    hintText: 'Diagnosis / condition',
                    maxLines: 3,
                    validator: (value) => value == null || value.trim().isEmpty ? 'Condition is required' : null,
                  ),
                  const SizedBox(height: 12),
                  CareCrewTextField(
                    controller: _patientEmergencyContactController,
                    label: 'Emergency Contact Number',
                    hintText: 'Enter emergency contact',
                    keyboardType: TextInputType.phone,
                    validator: (value) => InputValidators.phone(value, fieldLabel: 'emergency contact number'),
                  ),
                  const SizedBox(height: 12),
                  CareCrewPrimaryButton(
                    label: _savingPatient ? 'Saving...' : 'Save Patient Details',
                    onPressed: _savingPatient ? null : _savePatientDetails,
                    leading: const Icon(Icons.save_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFF2D7E8),
                child: Icon(icon, color: const Color(0xFF103A86)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFFFA3C4)),
            ],
          ),
        ),
      ),
    );
  }
}
