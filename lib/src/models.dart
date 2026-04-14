import 'package:cloud_firestore/cloud_firestore.dart';

enum CaregiverRole { admin, editor, viewer }

extension CaregiverRoleX on CaregiverRole {
  String get label {
    switch (this) {
      case CaregiverRole.admin:
        return 'Admin';
      case CaregiverRole.editor:
        return 'Editor';
      case CaregiverRole.viewer:
        return 'Viewer';
    }
  }

  static CaregiverRole fromValue(String? value) {
    switch (value?.toLowerCase()) {
      case 'admin':
        return CaregiverRole.admin;
      case 'viewer':
        return CaregiverRole.viewer;
      case 'editor':
      default:
        return CaregiverRole.editor;
    }
  }
}

enum AppointmentStatus { scheduled, completed, cancelled }

extension AppointmentStatusX on AppointmentStatus {
  String get label {
    switch (this) {
      case AppointmentStatus.scheduled:
        return 'Scheduled';
      case AppointmentStatus.completed:
        return 'Completed';
      case AppointmentStatus.cancelled:
        return 'Cancelled';
    }
  }

  static AppointmentStatus fromValue(String? value) {
    switch (value?.toLowerCase()) {
      case 'completed':
        return AppointmentStatus.completed;
      case 'cancelled':
        return AppointmentStatus.cancelled;
      case 'scheduled':
      default:
        return AppointmentStatus.scheduled;
    }
  }
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

Map<String, dynamic>? _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  return null;
}

class AppUserProfile {
  AppUserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.mobileNumber,
    required this.role,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final String mobileNumber;
  final String role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AppUserProfile.fromMap(String uid, Map<String, dynamic> map) {
    return AppUserProfile(
      uid: uid,
      displayName: (map['displayName'] as String?)?.trim().isNotEmpty == true
          ? map['displayName'] as String
          : 'Caregiver',
      email: (map['email'] as String?) ?? '',
      mobileNumber: (map['mobileNumber'] as String?) ?? '',
      role: (map['careRole'] as String?) ?? 'admin',
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'mobileNumber': mobileNumber,
      'careRole': role,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class PatientProfile {
  PatientProfile({
    required this.id,
    required this.fullName,
    required this.age,
    required this.dischargeDate,
    required this.condition,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String fullName;
  final int age;
  final DateTime dischargeDate;
  final String condition;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PatientProfile.fromMap(String id, Map<String, dynamic> map) {
    return PatientProfile(
      id: id,
      fullName: (map['fullName'] as String?) ?? '',
      age: (map['age'] as num?)?.toInt() ?? 0,
      dischargeDate: _date(map['dischargeDate']) ?? DateTime.now(),
      condition: (map['condition'] as String?) ?? '',
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'age': age,
      'dischargeDate': Timestamp.fromDate(dischargeDate),
      'condition': condition,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class CaregiverEntry {
  CaregiverEntry({
    required this.id,
    required this.name,
    required this.contact,
    required this.role,
    required this.relationship,
    required this.inviteStatus,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String contact;
  final String role;
  final String relationship;
  final String inviteStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CaregiverRole get roleValue => CaregiverRoleX.fromValue(role);
  bool get canEdit => roleValue != CaregiverRole.viewer;

  factory CaregiverEntry.fromMap(String id, Map<String, dynamic> map) {
    return CaregiverEntry(
      id: id,
      name: (map['name'] as String?) ?? '',
      contact: (map['contact'] as String?) ?? '',
      role: (map['role'] as String?) ?? 'viewer',
      relationship: (map['relationship'] as String?) ?? '',
      inviteStatus: (map['inviteStatus'] as String?) ?? 'pending',
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'contact': contact,
      'role': role,
      'relationship': relationship,
      'inviteStatus': inviteStatus,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class MedicationEntry {
  MedicationEntry({
    required this.id,
    required this.name,
    required this.dosage,
    this.currentStock,
    required this.scheduledHour,
    required this.scheduledMinute,
    required this.notes,
    required this.status,
    this.lastTakenAt,
    this.lastTakenDateKey,
    this.lastMissedDateKey,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String dosage;
  final int? currentStock;
  final int scheduledHour;
  final int scheduledMinute;
  final String notes;
  final String status;
  final DateTime? lastTakenAt;
  final String? lastTakenDateKey;
  final String? lastMissedDateKey;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get timeLabel {
    final hour = scheduledHour % 12 == 0 ? 12 : scheduledHour % 12;
    final minute = scheduledMinute.toString().padLeft(2, '0');
    final suffix = scheduledHour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String get bucket {
    final minutes = scheduledHour * 60 + scheduledMinute;
    if (minutes < 12 * 60) return 'Morning';
    if (minutes < 17 * 60) return 'Afternoon';
    return 'Evening';
  }

  bool get canBeMarkedTaken => status != 'taken';
  bool get hasLowStock => currentStock != null && currentStock! < 5;

  factory MedicationEntry.fromMap(String id, Map<String, dynamic> map) {
    return MedicationEntry(
      id: id,
      name: (map['name'] as String?) ?? '',
      dosage: (map['dosage'] as String?) ?? '',
      currentStock: (map['currentStock'] as num?)?.toInt(),
      scheduledHour: (map['scheduledHour'] as num?)?.toInt() ?? 8,
      scheduledMinute: (map['scheduledMinute'] as num?)?.toInt() ?? 0,
      notes: (map['notes'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'pending',
      lastTakenAt: _date(map['lastTakenAt']),
      lastTakenDateKey: map['lastTakenDateKey'] as String?,
      lastMissedDateKey: map['lastMissedDateKey'] as String?,
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'dosage': dosage,
      'currentStock': currentStock,
      'scheduledHour': scheduledHour,
      'scheduledMinute': scheduledMinute,
      'notes': notes,
      'status': status,
      'lastTakenAt': lastTakenAt != null ? Timestamp.fromDate(lastTakenAt!) : null,
      'lastTakenDateKey': lastTakenDateKey,
      'lastMissedDateKey': lastMissedDateKey,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class VitalEntry {
  VitalEntry({
    required this.id,
    required this.temperature,
    required this.systolic,
    required this.diastolic,
    required this.painLevel,
    required this.notes,
    this.photoUrl,
    this.photoPath,
    this.alertLabel,
    this.alertReasons = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final double temperature;
  final int systolic;
  final int diastolic;
  final int painLevel;
  final String notes;
  final String? photoUrl;
  final String? photoPath;
  final String? alertLabel;
  final List<String> alertReasons;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasAlert => (alertLabel ?? '').isNotEmpty;

  factory VitalEntry.fromMap(String id, Map<String, dynamic> map) {
    return VitalEntry(
      id: id,
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0,
      systolic: (map['systolic'] as num?)?.toInt() ?? 0,
      diastolic: (map['diastolic'] as num?)?.toInt() ?? 0,
      painLevel: (map['painLevel'] as num?)?.toInt() ?? 0,
      notes: (map['notes'] as String?) ?? '',
      photoUrl: map['photoUrl'] as String?,
      photoPath: map['photoPath'] as String?,
      alertLabel: map['alertLabel'] as String?,
      alertReasons: ((map['alertReasons'] as List?) ?? const []).cast<String>(),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'temperature': temperature,
      'systolic': systolic,
      'diastolic': diastolic,
      'painLevel': painLevel,
      'notes': notes,
      'photoUrl': photoUrl,
      'photoPath': photoPath,
      'alertLabel': alertLabel,
      'alertReasons': alertReasons,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class ThresholdConfig {
  ThresholdConfig({
    required this.id,
    this.temperatureHigh,
    this.systolicHigh,
    this.diastolicHigh,
    this.painHigh,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final double? temperatureHigh;
  final int? systolicHigh;
  final int? diastolicHigh;
  final int? painHigh;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasAnyThreshold =>
      temperatureHigh != null || systolicHigh != null || diastolicHigh != null || painHigh != null;

  factory ThresholdConfig.fromMap(String id, Map<String, dynamic> map) {
    return ThresholdConfig(
      id: id,
      temperatureHigh: (map['temperatureHigh'] as num?)?.toDouble(),
      systolicHigh: (map['systolicHigh'] as num?)?.toInt(),
      diastolicHigh: (map['diastolicHigh'] as num?)?.toInt(),
      painHigh: (map['painHigh'] as num?)?.toInt(),
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'temperatureHigh': temperatureHigh,
      'systolicHigh': systolicHigh,
      'diastolicHigh': diastolicHigh,
      'painHigh': painHigh,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class AppointmentEntry {
  AppointmentEntry({
    required this.id,
    required this.doctorName,
    required this.appointmentDateTime,
    required this.location,
    required this.status,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String doctorName;
  final DateTime appointmentDateTime;
  final String location;
  final String status;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AppointmentStatus get statusValue => AppointmentStatusX.fromValue(status);

  factory AppointmentEntry.fromMap(String id, Map<String, dynamic> map) {
    return AppointmentEntry(
      id: id,
      doctorName: (map['doctorName'] as String?) ?? '',
      appointmentDateTime: _date(map['appointmentDateTime']) ?? DateTime.now(),
      location: (map['location'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'scheduled',
      notes: (map['notes'] as String?) ?? '',
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'doctorName': doctorName,
      'appointmentDateTime': Timestamp.fromDate(appointmentDateTime),
      'location': location,
      'status': status,
      'notes': notes,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class ActivityLogEntry {
  ActivityLogEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.details,
    required this.actor,
    this.createdAt,
    this.meta = const {},
  });

  final String id;
  final String type;
  final String title;
  final String details;
  final String actor;
  final DateTime? createdAt;
  final Map<String, dynamic> meta;

  factory ActivityLogEntry.fromMap(String id, Map<String, dynamic> map) {
    return ActivityLogEntry(
      id: id,
      type: (map['type'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      details: (map['details'] as String?) ?? '',
      actor: (map['actor'] as String?) ?? '',
      createdAt: _date(map['createdAt']),
      meta: _map(map['meta']) ?? const {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'title': title,
      'details': details,
      'actor': actor,
      'meta': meta,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}

class DocumentEntry {
  DocumentEntry({
    required this.id,
    required this.fileName,
    required this.storagePath,
    required this.downloadUrl,
    required this.fileSizeBytes,
    required this.mimeType,
    required this.addedBy,
    this.createdAt,
  });

  final String id;
  final String fileName;
  final String storagePath;
  final String downloadUrl;
  final int fileSizeBytes;
  final String mimeType;
  final String addedBy;
  final DateTime? createdAt;

  factory DocumentEntry.fromMap(String id, Map<String, dynamic> map) {
    return DocumentEntry(
      id: id,
      fileName: (map['fileName'] as String?) ?? '',
      storagePath: (map['storagePath'] as String?) ?? '',
      downloadUrl: (map['downloadUrl'] as String?) ?? '',
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      mimeType: (map['mimeType'] as String?) ?? '',
      addedBy: (map['addedBy'] as String?) ?? '',
      createdAt: _date(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'fileSizeBytes': fileSizeBytes,
      'mimeType': mimeType,
      'addedBy': addedBy,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}
