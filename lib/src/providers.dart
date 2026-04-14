import 'package:carecrew_app/src/models.dart';
import 'package:carecrew_app/src/repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final firebaseStorageProvider = Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

final repositoryProvider = Provider<CareCrewRepository>((ref) {
  return CareCrewRepository(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(firebaseStorageProvider),
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(repositoryProvider).authStateChanges();
});

final currentUserProfileProvider = StreamProvider.family<AppUserProfile?, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchUserProfile(uid);
});

final patientProfileProvider = StreamProvider.family<PatientProfile?, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchPatientProfile(uid);
});

final caregiversProvider = StreamProvider.family<List<CaregiverEntry>, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchCaregivers(uid);
});

final medicationsProvider = StreamProvider.family<List<MedicationEntry>, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchMedications(uid);
});

final vitalsProvider = StreamProvider.family<List<VitalEntry>, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchVitals(uid);
});

final thresholdsProvider = StreamProvider.family<ThresholdConfig?, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchThresholds(uid);
});

final appointmentsProvider = StreamProvider.family<List<AppointmentEntry>, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchAppointments(uid);
});

final activityLogsProvider = StreamProvider.family<List<ActivityLogEntry>, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchActivityLogs(uid);
});

final documentsProvider = StreamProvider.family<List<DocumentEntry>, String>((ref, uid) {
  return ref.watch(repositoryProvider).watchDocuments(uid);
});
