import 'dart:async';

import 'package:carecrew_app/src/models.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  final Set<int> _medicationReminderIds = <int>{};
  final Set<int> _appointmentReminderIds = <int>{};
  String _medicationSignature = '';
  String _appointmentSignature = '';

  final AndroidNotificationDetails _reminderAndroidDetails = const AndroidNotificationDetails(
    'carecrew_reminders',
    'Care reminders',
    channelDescription: 'Medication and appointment reminders',
    importance: Importance.high,
    priority: Priority.high,
  );

  final AndroidNotificationDetails _alertAndroidDetails = const AndroidNotificationDetails(
    'carecrew_alerts',
    'Care alerts',
    channelDescription: 'Critical health and caregiver activity alerts',
    importance: Importance.max,
    priority: Priority.max,
  );

  NotificationDetails get _reminderDetails => NotificationDetails(
        android: _reminderAndroidDetails,
        iOS: const DarwinNotificationDetails(),
      );

  NotificationDetails get _alertDetails => NotificationDetails(
        android: _alertAndroidDetails,
        iOS: const DarwinNotificationDetails(),
      );

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  Future<void> syncMedicationReminders({
    required String uid,
    required List<MedicationEntry> medications,
  }) async {
    await initialize();

    final signature = medications
        .map(
          (m) =>
              '${m.id}|${m.name}|${m.scheduledHour}|${m.scheduledMinute}|${m.status}|${m.lastTakenDateKey}|${m.createdAt?.toIso8601String() ?? ''}',
        )
        .join('~');
    if (signature == _medicationSignature) return;

    for (final id in _medicationReminderIds) {
      await _plugin.cancel(id);
    }
    _medicationReminderIds.clear();

    final now = tz.TZDateTime.now(tz.local);
    for (final med in medications) {
      if (med.status.toLowerCase() == 'taken') {
        continue;
      }

      final created = med.createdAt;
      if (created == null) {
        continue;
      }

      final scheduledAt = tz.TZDateTime(
        tz.local,
        created.year,
        created.month,
        created.day,
        med.scheduledHour,
        med.scheduledMinute,
      );
      final reminderAt = scheduledAt.subtract(const Duration(minutes: 5));
      if (!reminderAt.isAfter(now)) {
        continue;
      }

      final id = _stableId('med:$uid:${med.id}:${created.toIso8601String()}', offset: 100000);
      _medicationReminderIds.add(id);

      await _scheduleWithFallback(
        id: id,
        title: 'Medication Reminder',
        body: "Reminder: Medication '${med.name}' is scheduled at ${med.timeLabel}",
        scheduled: reminderAt,
        details: _reminderDetails,
      );
    }

    _medicationSignature = signature;
  }

  Future<void> syncAppointmentReminders({
    required String uid,
    required List<AppointmentEntry> appointments,
  }) async {
    await initialize();

    final signature = appointments
        .map((a) => '${a.id}|${a.doctorName}|${a.appointmentDateTime.toIso8601String()}|${a.status}')
        .join('~');
    if (signature == _appointmentSignature) return;

    for (final id in _appointmentReminderIds) {
      await _plugin.cancel(id);
    }
    _appointmentReminderIds.clear();

    final now = tz.TZDateTime.now(tz.local);
    for (final appt in appointments) {
      final status = appt.status.toLowerCase();
      if (status == 'completed' || status == 'cancelled') {
        continue;
      }

      final reminderAt = appt.appointmentDateTime.subtract(const Duration(hours: 1));
      final tzReminderAt = tz.TZDateTime.from(reminderAt, tz.local);
      if (tzReminderAt.isBefore(now)) {
        continue;
      }

      final id = _stableId('appt:$uid:${appt.id}', offset: 200000);
      _appointmentReminderIds.add(id);

      final atTime = DateFormat('h:mm a').format(appt.appointmentDateTime);
      await _scheduleWithFallback(
        id: id,
        title: 'Appointment Reminder',
        body: 'Reminder: Appointment with Dr. ${appt.doctorName} at $atTime',
        scheduled: tzReminderAt,
        details: _reminderDetails,
      );
    }

    _appointmentSignature = signature;
  }

  Future<void> showAbnormalVitalsAlert(List<String> reasons) async {
    await initialize();
    final body = reasons.isEmpty
        ? 'Alert: Abnormal vitals detected'
        : 'Alert: Abnormal vitals detected (${reasons.join(', ')})';
    await _plugin.show(
      _ephemeralId(offset: 400000),
      'Critical Vitals Alert',
      body,
      _alertDetails,
    );
  }

  Future<void> showCaregiverActivityNotification({
    required String caregiverName,
  }) async {
    await initialize();
    await _plugin.show(
      _ephemeralId(offset: 500000),
      'Care Circle Update',
      '$caregiverName added a new update for the patient',
      _alertDetails,
    );
  }

  int _stableId(String value, {required int offset}) {
    final hash = _deterministicHash(value);
    return offset + (hash % 90000);
  }

  int _deterministicHash(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash & 0x7fffffff;
  }

  int _ephemeralId({required int offset}) {
    final now = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    return offset + (now % 90000);
  }

  Future<void> _scheduleWithFallback({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduled,
    required NotificationDetails details,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } on PlatformException catch (error) {
      if (error.code != 'exact_alarms_not_permitted') rethrow;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    }
  }
}
