import 'dart:io';
import 'dart:typed_data';

import 'package:carecrew_app/src/models.dart';
import 'package:carecrew_app/src/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class CareCrewRepository {
      Future<void> setLastPatientLocation({required String uid, required String location}) async {
        await _userDoc(uid).collection('meta').doc('last_patient_location').set({
          'location': location,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      Future<String?> getLastPatientLocation(String uid) async {
        final doc = await _userDoc(uid).collection('meta').doc('last_patient_location').get();
        return doc.data()?['location'] as String?;
      }
    Future<void> deleteMedication({
      required String uid,
      required MedicationEntry medication,
    }) async {
      await _subCollection(uid, 'medications').doc(medication.id).delete();
      await addActivityLog(
        uid: uid,
        type: 'medication_deleted',
        title: 'Medication deleted',
        details: '${medication.name} at ${medication.timeLabel} was deleted.',
        actor: 'Caregiver',
        meta: {'medicationId': medication.id},
      );
    }
  CareCrewRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  static const String _bucketName = 'carecrew-files';

  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;
  supabase.SupabaseClient get _supabase => supabase.Supabase.instance.client;
  dynamic get _storage => _supabase.storage.from(_bucketName);

  Future<T> _runStorageOperation<T>(
    Future<T> Function() operation, {
    required String action,
  }) async {
    try {
      return await operation();
    } catch (error) {
      final message = error.toString();
      if (message.contains('Failed host lookup') ||
          message.contains('SocketException') ||
          message.contains('ClientException') ||
          message.contains('Connection timed out')) {
        throw StateError(
          '$action failed because the device could not reach Supabase. Check your internet connection, private DNS/VPN, and Supabase URL.',
        );
      }
      rethrow;
    }
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);

    DocumentReference<Map<String, dynamic>> _patientRootDoc(String patientId) =>
      _firestore.collection('patients').doc(patientId);

    CollectionReference<Map<String, dynamic>> _patientSubCollection(String patientId, String name) =>
      _patientRootDoc(patientId).collection(name);

    DocumentReference<Map<String, dynamic>> _patientProfileDoc(String patientId) =>
      _patientSubCollection(patientId, 'profile').doc('main');

    DocumentReference<Map<String, dynamic>> _patientCaregiverDoc(String patientId, String uid) =>
      _patientSubCollection(patientId, 'caregivers').doc(uid);

    CollectionReference<Map<String, dynamic>> _invitesCollection() =>
      _firestore.collection('invites');

  CollectionReference<Map<String, dynamic>> _subCollection(String uid, String name) =>
      _userDoc(uid).collection(name);

  DocumentReference<Map<String, dynamic>> _patientDoc(String uid) =>
      _subCollection(uid, 'patient').doc('main');

  DocumentReference<Map<String, dynamic>> _thresholdDoc(String uid) =>
      _subCollection(uid, 'thresholds').doc('default');

  String _dayKey(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  String _shortDate(DateTime value) => DateFormat('MMM d, yyyy').format(value);

  String? _contentTypeForExtension(String? extension) {
    final ext = (extension ?? '').toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'txt':
        return 'text/plain';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return null;
    }
  }

  Future<Uint8List> _readBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes!;
    if (file.path != null && file.path!.isNotEmpty) {
      return File(file.path!).readAsBytes();
    }
    throw StateError('Could not read the selected file. Please pick it again.');
  }

  Future<void> ensureUserProfile(User firebaseUser) async {
    final displayName = firebaseUser.displayName ?? '';
    final mobile = firebaseUser.phoneNumber ?? '';
    final email = firebaseUser.email ?? '';
    try {
      await _userDoc(firebaseUser.uid).set(
        {
          'uid': firebaseUser.uid,
          'displayName': displayName.isEmpty ? 'Caregiver' : displayName,
          'email': email,
          'mobileNumber': mobile,
          'careRole': 'admin',
          'patientIds': FieldValue.arrayUnion([firebaseUser.uid]),
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Auth should still succeed even if Firestore is temporarily unavailable.
    }
  }

  Future<void> createAccount({
    required String name,
    required String email,
    required String password,
    String mobileNumber = '',
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.updateDisplayName(name);
    await credential.user?.reload();
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _userDoc(user.uid).set(
          {
            'uid': user.uid,
            'displayName': name,
            'email': email,
            'mobileNumber': mobileNumber,
            'careRole': 'admin',
            'patientIds': FieldValue.arrayUnion([user.uid]),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {
        // Keep the new auth user signed in even if Firestore is not ready yet.
      }
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw StateError('Google sign-in was cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google sign-in failed: missing ID token.');
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user != null) {
      await ensureUserProfile(user);
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Proceed with Firebase sign-out even if Google sign-out is unavailable.
    }
    await _auth.signOut();
  }

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email);

  String _normalizePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  Future<String> _resolveUserInvitePhone(User user) async {
    final authPhone = _normalizePhone(user.phoneNumber);
    if (authPhone.isNotEmpty) return authPhone;

    try {
      final profile = await _userDoc(user.uid).get();
      final profilePhone = _normalizePhone(profile.data()?['mobileNumber'] as String?);
      return profilePhone;
    } catch (_) {
      return '';
    }
  }

  bool _inviteMatchesUser(CareInvite invite, String userId, String userPhone) {
    final inviteUserId = invite.invitedUserId?.trim();
    if (inviteUserId != null && inviteUserId.isNotEmpty) {
      return inviteUserId == userId;
    }

    final invitePhone = _normalizePhone(invite.invitedPhone);
    if (invitePhone.isEmpty) {
      return true;
    }
    if (userPhone.isEmpty) {
      return false;
    }
    return invitePhone == userPhone;
  }

  Stream<List<String>> watchUserPatientIds(String uid) {
    return _userDoc(uid).snapshots().map((snapshot) {
      final raw = (snapshot.data()?['patientIds'] as List?) ?? const [];
      final ids = raw.whereType<String>().map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
      final deduped = <String>{};
      final ordered = <String>[];
      for (final id in ids) {
        if (deduped.add(id)) {
          ordered.add(id);
        }
      }
      return ordered;
    });
  }

  Future<void> _bindEmailInvitesToUser(User user) async {
    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return;

    // Backfill invite records for legacy caregiver rows created before invites/{inviteId} existed.
    try {
      final legacyPending = await _firestore
          .collectionGroup('caregivers')
          .where('contact', isEqualTo: email)
          .where('inviteStatus', isEqualTo: 'pending')
          .get();
      for (final row in legacyPending.docs) {
        final ownerRef = row.reference.parent.parent;
        if (ownerRef == null) continue;
        final patientId = ownerRef.id;
        final legacy = row.data();

        final existingInvite = await _invitesCollection()
            .where('patientId', isEqualTo: patientId)
            .where('invitedEmail', isEqualTo: email)
            .limit(1)
            .get();
        final hasPending = existingInvite.docs.any((doc) {
          final status = (doc.data()['status'] as String? ?? '').toLowerCase();
          return status == 'pending';
        });
        if (hasPending) continue;

        final ownerProfile = await _userDoc(patientId).get();
        final ownerName = (ownerProfile.data()?['displayName'] as String?)?.trim();
        final patientProfile = await _patientDoc(patientId).get();
        final patientName = (patientProfile.data()?['fullName'] as String?)?.trim();

        await _invitesCollection().doc().set(
          CareInvite(
            id: '',
            patientId: patientId,
            role: CaregiverRoleX.fromValue(legacy['role'] as String?).name,
            status: 'pending',
            invitedBy: patientId,
            invitedUserId: user.uid,
            invitedEmail: email,
            invitedPhone: (legacy['mobile'] as String?)?.trim(),
            invitedByName: ownerName?.isEmpty == true ? null : ownerName,
            patientName: patientName?.isEmpty == true ? null : patientName,
            createdAt: DateTime.now(),
          ).toMap(),
        );
      }
    } catch (_) {
      // Legacy invite backfill is best-effort and should not block login routing.
    }

    final snapshot = await _invitesCollection()
        .where('status', isEqualTo: 'pending')
        .where('invitedEmail', isEqualTo: email)
        .get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final boundUid = (data['invitedUserId'] as String?)?.trim();
      if (boundUid == null || boundUid.isEmpty) {
        batch.set(doc.reference, {
          'invitedUserId': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
    await batch.commit();
  }

  Stream<List<CareInvite>> watchPendingInvites(User user) async* {
    await _bindEmailInvitesToUser(user);
    final userPhone = await _resolveUserInvitePhone(user);
    yield* _invitesCollection()
        .where('status', isEqualTo: 'pending')
        .where('invitedUserId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final invites = snapshot.docs
              .map((doc) => CareInvite.fromMap(doc.id, doc.data()))
              .where((invite) => _inviteMatchesUser(invite, user.uid, userPhone))
              .toList();
          invites.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
          return invites;
        });
  }

  Future<List<CareInvite>> fetchPendingInvites(User user) async {
    await _bindEmailInvitesToUser(user);
    final userPhone = await _resolveUserInvitePhone(user);
    final snapshot = await _invitesCollection()
        .where('status', isEqualTo: 'pending')
        .where('invitedUserId', isEqualTo: user.uid)
        .get();
    final invites = snapshot.docs
        .map((doc) => CareInvite.fromMap(doc.id, doc.data()))
        .where((invite) => _inviteMatchesUser(invite, user.uid, userPhone))
        .toList();
    invites.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    return invites;
  }

  Future<void> acceptInvite({
    required User user,
    required CareInvite invite,
  }) async {
    if (invite.patientId.trim().isEmpty) {
      throw StateError('Invite is missing patientId.');
    }

    final inviteRef = _invitesCollection().doc(invite.id);
    final role = CaregiverRoleX.fromValue(invite.role).name;

    await _firestore.runTransaction((tx) async {
      final inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) {
        throw StateError('Invite no longer exists.');
      }
      final inviteData = inviteSnap.data() ?? const <String, dynamic>{};
      final status = (inviteData['status'] as String? ?? '').toLowerCase();
      if (status != 'pending') {
        throw StateError('Invite is already ${inviteData['status'] ?? 'processed'}.');
      }

      tx.set(_patientCaregiverDoc(invite.patientId, user.uid), {
        'uid': user.uid,
        'email': (user.email ?? '').trim().toLowerCase(),
        'displayName': (user.displayName ?? '').trim(),
        'role': role,
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(_userDoc(user.uid), {
        'patientIds': FieldValue.arrayUnion([invite.patientId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(inviteRef, {
        'status': 'accepted',
        'invitedUserId': user.uid,
        'respondedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    // Keep legacy caregiver entries in sync for current read paths.
    final email = (user.email ?? '').trim().toLowerCase();
    if (email.isEmpty) return;
    final legacyCaregiverRows = await _subCollection(invite.patientId, 'caregivers')
        .where('contact', isEqualTo: email)
        .get();
    for (final doc in legacyCaregiverRows.docs) {
      await doc.reference.set({
        'inviteStatus': 'accepted',
        'acceptedBy': user.uid,
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> rejectInvite({
    required User user,
    required CareInvite invite,
  }) async {
    await _invitesCollection().doc(invite.id).set({
      'status': 'rejected',
      'invitedUserId': user.uid,
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<CaregiverRole> resolveCaregiverRoleForContext({
    required String careContextId,
    required User user,
  }) async {
    if (careContextId == user.uid) {
      return CaregiverRole.admin;
    }

    final patientMembership = await _patientCaregiverDoc(careContextId, user.uid).get();
    if (patientMembership.exists) {
      final roleValue = patientMembership.data()?['role'] as String?;
      return CaregiverRoleX.fromValue(roleValue);
    }

    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      return CaregiverRole.viewer;
    }
    final legacyRows = await _subCollection(careContextId, 'caregivers')
        .where('contact', isEqualTo: email)
        .limit(1)
        .get();
    if (legacyRows.docs.isEmpty) {
      return CaregiverRole.viewer;
    }
    final roleValue = legacyRows.docs.first.data()['role'] as String?;
    return CaregiverRoleX.fromValue(roleValue);
  }

  Stream<AppUserProfile?> watchUserProfile(String uid) {
    return _userDoc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return AppUserProfile.fromMap(snapshot.id, data);
    });
  }

  Future<void> updateUserProfile({
    required String uid,
    required String displayName,
    required String mobileNumber,
  }) async {
    await _userDoc(uid).set({
      'displayName': displayName,
      'mobileNumber': mobileNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (displayName.isNotEmpty) {
      await _auth.currentUser?.updateDisplayName(displayName);
    }
  }

  Stream<PatientProfile?> watchPatientProfile(String uid) {
    return _patientDoc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return PatientProfile.fromMap(snapshot.id, data);
    });
  }

  Future<void> savePatientProfile({
    required String uid,
    required PatientProfile profile,
  }) async {
    final patientId = uid;
    try {
      await _patientDoc(uid).set(
        profile.toMap(),
        SetOptions(merge: true),
      );
      await _patientProfileDoc(patientId).set(
        profile.toMap(),
        SetOptions(merge: true),
      );
      await _patientCaregiverDoc(patientId, uid).set(
        {
          'uid': uid,
          'role': CaregiverRole.admin.name,
          'status': 'accepted',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _userDoc(uid).set(
        {
          'patientIds': FieldValue.arrayUnion([patientId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError(
          'Permission denied while saving patient profile. Check Firestore rules for users/$uid/patient/main.',
        );
      }
      rethrow;
    }
    final verificationSnapshot = await _patientDoc(uid).get();
    if (!verificationSnapshot.exists) {
      throw StateError('Patient profile was not persisted. Please try again.');
    }
    // Try to add an activity log but don't fail the whole operation if logging fails.
    try {
      await addActivityLog(
        uid: uid,
        type: 'patient_setup',
        title: 'Patient profile completed',
        details: '${profile.fullName} was added as the active patient.',
        actor: 'System',
      );
    } catch (e, st) {
      // Log locally and continue — we don't want the UI to treat logging failures as save failures.
      // ignore: avoid_print
      print('Warning: addActivityLog failed for patient profile: $e\n$st');
    }
  }

  Stream<List<CaregiverEntry>> watchCaregivers(String uid) {
    return _subCollection(uid, 'caregivers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CaregiverEntry.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> saveCaregiver({
    required String uid,
    required CaregiverEntry caregiver,
  }) async {
    final ref = _subCollection(uid, 'caregivers').doc();
    final patientProfileSnapshot = await _patientDoc(uid).get();
    final patientName = (patientProfileSnapshot.data()?['fullName'] as String?)?.trim();
    final inviteRef = _invitesCollection().doc();
    final actorName = (_auth.currentUser?.displayName ?? '').trim();

    await ref.set({
      ...caregiver.toMap(),
      'id': ref.id,
    });

    await _patientCaregiverDoc(uid, uid).set(
      {
        'uid': uid,
        'role': CaregiverRole.admin.name,
        'status': 'accepted',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await inviteRef.set(
      CareInvite(
        id: inviteRef.id,
        patientId: uid,
        role: CaregiverRoleX.fromValue(caregiver.role).name,
        status: 'pending',
        invitedBy: _auth.currentUser?.uid ?? uid,
        invitedUserId: null,
        invitedEmail: caregiver.contact.trim().toLowerCase(),
        invitedPhone: caregiver.mobile.trim().isEmpty ? null : caregiver.mobile.trim(),
        patientName: patientName?.isEmpty == true ? null : patientName,
        invitedByName: actorName.isEmpty ? null : actorName,
        createdAt: DateTime.now(),
      ).toMap(),
    );

    await addActivityLog(
      uid: uid,
      type: 'caregiver_added',
      title: 'Caregiver added',
      details: '${caregiver.name} was invited as ${caregiver.role}.',
      actor: 'System',
    );
  }

  Future<void> deleteCaregiver({required String uid, required String caregiverId}) async {
    final caregiverRef = _subCollection(uid, 'caregivers').doc(caregiverId);
    final caregiverSnapshot = await caregiverRef.get();
    final caregiverData = caregiverSnapshot.data() ?? const <String, dynamic>{};
    final contact = (caregiverData['contact'] as String? ?? '').trim().toLowerCase();
    final acceptedBy = (caregiverData['acceptedBy'] as String?)?.trim();

    await caregiverRef.delete();

    if (acceptedBy != null && acceptedBy.isNotEmpty) {
      await _patientCaregiverDoc(uid, acceptedBy).delete();
    }

    if (contact.isNotEmpty) {
      final invites = await _invitesCollection()
          .where('patientId', isEqualTo: uid)
          .where('invitedEmail', isEqualTo: contact)
          .where('status', isEqualTo: 'pending')
          .get();
      for (final doc in invites.docs) {
        await doc.reference.set(
          {
            'status': 'rejected',
            'respondedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }

    await addActivityLog(
      uid: uid,
      type: 'caregiver_removed',
      title: 'Caregiver removed',
      details: 'A caregiver invitation or member was removed from the circle.',
      actor: 'System',
    );
  }

  Stream<List<MedicationEntry>> watchMedications(String uid) {
    return _subCollection(uid, 'medications').snapshots().map((snapshot) {
      final meds = snapshot.docs
          .map((doc) => MedicationEntry.fromMap(doc.id, doc.data()))
          .toList();
      meds.sort((a, b) {
        final hourCompare = a.scheduledHour.compareTo(b.scheduledHour);
        if (hourCompare != 0) return hourCompare;
        return a.scheduledMinute.compareTo(b.scheduledMinute);
      });
      return meds;
    });
  }

  Future<void> saveMedication({
    required String uid,
    required MedicationEntry medication,
  }) async {
    final ref = _subCollection(uid, 'medications').doc();
    await ref.set({...medication.toMap(), 'id': ref.id});
    await addActivityLog(
      uid: uid,
      type: 'medication_added',
      title: 'Medication scheduled',
      details: '${medication.name} at ${medication.timeLabel} was added.',
      actor: 'System',
    );
  }

  Future<void> updateMedication({
    required String uid,
    required MedicationEntry medication,
  }) async {
    await _subCollection(uid, 'medications').doc(medication.id).update({
      ...medication.toMap(),
      'id': medication.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addActivityLog(
      uid: uid,
      type: 'medication_updated',
      title: 'Medication updated',
      details: '${medication.name} at ${medication.timeLabel} was updated.',
      actor: 'Caregiver',
      meta: {'medicationId': medication.id},
    );
  }

  Future<void> markMedicationTaken({
    required String uid,
    required MedicationEntry medication,
    String? actor,
  }) async {
    final now = DateTime.now();
    final doseKey = _dayKey(medication.createdAt ?? now);
    final nextStock = medication.currentStock == null
        ? null
        : (medication.currentStock! > 0 ? medication.currentStock! - 1 : 0);
    await _subCollection(uid, 'medications').doc(medication.id).update(
      {
        'status': 'taken',
        'lastTakenAt': Timestamp.fromDate(now),
        'lastTakenDateKey': doseKey,
        'currentStock': nextStock,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    await addActivityLog(
      uid: uid,
      type: 'medication_taken',
      title: 'Medication taken',
      details: '${medication.name} ${medication.dosage} marked as taken.',
      actor: actor ?? 'Caregiver',
      meta: {'medicationId': medication.id},
    );
  }

  Future<void> markMedicationNotTaken({
    required String uid,
    required MedicationEntry medication,
    String? actor,
  }) async {
    await _subCollection(uid, 'medications').doc(medication.id).update(
      {
        'status': 'pending',
        'lastTakenAt': null,
        'lastTakenDateKey': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    await addActivityLog(
      uid: uid,
      type: 'medication_updated',
      title: 'Medication marked not taken',
      details: '${medication.name} ${medication.dosage} marked as not taken.',
      actor: actor ?? 'Caregiver',
      meta: {'medicationId': medication.id},
    );
  }

  Future<void> syncMedicationStatuses(String uid) async {
    final snapshot = await _subCollection(uid, 'medications').get();
    final now = DateTime.now();

    for (final doc in snapshot.docs) {
      final medication = MedicationEntry.fromMap(doc.id, doc.data());
      final created = medication.createdAt;
      if (created == null) continue;

      final scheduledAt = DateTime(
        created.year,
        created.month,
        created.day,
        medication.scheduledHour,
        medication.scheduledMinute,
      );
      final doseKey = _dayKey(scheduledAt);
      final isPastDue = !now.isBefore(scheduledAt);
      final alreadyLoggedMissed = medication.lastMissedDateKey == doseKey;
      final alreadyTakenForDose = medication.status == 'taken' || medication.lastTakenDateKey == doseKey;

      if (isPastDue && !alreadyTakenForDose && !alreadyLoggedMissed) {
        await doc.reference.update(
          {
            'status': 'missed',
            'lastMissedDateKey': doseKey,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        await addActivityLog(
          uid: uid,
          type: 'medication_missed',
          title: 'Medication missed',
          details:
              '${medication.name} was due at ${medication.timeLabel} and has not been marked taken.',
          actor: 'System',
          meta: {'medicationId': medication.id},
        );
      } else if (!isPastDue && medication.status == 'missed') {
        await doc.reference.update(
          {
            'status': 'pending',
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }
    }
  }

  Stream<List<VitalEntry>> watchVitals(String uid) {
    return _subCollection(uid, 'vitals')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => VitalEntry.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<ThresholdConfig?> watchThresholds(String uid) {
    return _thresholdDoc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return ThresholdConfig.fromMap(snapshot.id, data);
    });
  }

  Future<void> saveThresholds({
    required String uid,
    required ThresholdConfig thresholds,
  }) async {
    await _thresholdDoc(uid).set(thresholds.toMap(), SetOptions(merge: true));
    await addActivityLog(
      uid: uid,
      type: 'thresholds_updated',
      title: 'Thresholds updated',
      details: 'Vital alert thresholds were updated.',
      actor: 'System',
    );
  }

  Future<VitalEntry> saveVitalEntry({
    required String uid,
    required VitalEntry entry,
  }) async {
    final thresholdsSnapshot = await _thresholdDoc(uid).get();
    final thresholds =
        thresholdsSnapshot.exists && thresholdsSnapshot.data() != null
        ? ThresholdConfig.fromMap(
            thresholdsSnapshot.id,
            thresholdsSnapshot.data()!,
          )
        : ThresholdConfig(id: 'default');

    final alertReasons = <String>[];
    if (thresholds.temperatureHigh != null &&
        entry.temperature > thresholds.temperatureHigh!) {
      alertReasons.add('Fever detected');
    }
    if (thresholds.systolicHigh != null &&
        entry.systolic > thresholds.systolicHigh!) {
      alertReasons.add('High blood pressure');
    }
    if (thresholds.diastolicHigh != null &&
        entry.diastolic > thresholds.diastolicHigh!) {
      alertReasons.add('Diastolic above threshold');
    }
    if (thresholds.painHigh != null && entry.painLevel > thresholds.painHigh!) {
      alertReasons.add('Pain level elevated');
    }

    final alertLabel = alertReasons.isEmpty ? null : alertReasons.first;
    final ref = _subCollection(uid, 'vitals').doc();
    final timestamp = entry.createdAt ?? DateTime.now();
    final saved = VitalEntry(
      id: ref.id,
      temperature: entry.temperature,
      systolic: entry.systolic,
      diastolic: entry.diastolic,
      painLevel: entry.painLevel,
      notes: entry.notes,
      photoUrl: entry.photoUrl,
      photoPath: entry.photoPath,
      alertLabel: alertLabel,
      alertReasons: alertReasons,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await ref.set(saved.toMap());
    await addActivityLog(
      uid: uid,
      type: alertReasons.isEmpty ? 'vitals_logged' : 'critical_alert',
      title: alertReasons.isEmpty ? 'Vitals logged' : alertReasons.first,
      details:
          'Temperature ${entry.temperature.toStringAsFixed(1)}°F, BP ${entry.systolic}/${entry.diastolic}, pain ${entry.painLevel}.',
      actor: 'Caregiver',
      meta: {'vitalId': ref.id, 'alertReasons': alertReasons},
    );
    if (alertReasons.isNotEmpty) {
      await NotificationService.instance.showAbnormalVitalsAlert(alertReasons);
    }
    return saved;
  }

  Future<VitalEntry> updateVitalEntry({
    required String uid,
    required VitalEntry entry,
  }) async {
    final thresholdsSnapshot = await _thresholdDoc(uid).get();
    final thresholds =
        thresholdsSnapshot.exists && thresholdsSnapshot.data() != null
        ? ThresholdConfig.fromMap(
            thresholdsSnapshot.id,
            thresholdsSnapshot.data()!,
          )
        : ThresholdConfig(id: 'default');

    final alertReasons = <String>[];
    if (thresholds.temperatureHigh != null &&
        entry.temperature > thresholds.temperatureHigh!) {
      alertReasons.add('Fever detected');
    }
    if (thresholds.systolicHigh != null &&
        entry.systolic > thresholds.systolicHigh!) {
      alertReasons.add('High blood pressure');
    }
    if (thresholds.diastolicHigh != null &&
        entry.diastolic > thresholds.diastolicHigh!) {
      alertReasons.add('Diastolic above threshold');
    }
    if (thresholds.painHigh != null && entry.painLevel > thresholds.painHigh!) {
      alertReasons.add('Pain level elevated');
    }

    final alertLabel = alertReasons.isEmpty ? null : alertReasons.first;
    final timestamp = entry.createdAt ?? DateTime.now();
    final updated = VitalEntry(
      id: entry.id,
      temperature: entry.temperature,
      systolic: entry.systolic,
      diastolic: entry.diastolic,
      painLevel: entry.painLevel,
      notes: entry.notes,
      photoUrl: entry.photoUrl,
      photoPath: entry.photoPath,
      alertLabel: alertLabel,
      alertReasons: alertReasons,
      createdAt: timestamp,
      updatedAt: DateTime.now(),
    );

    await _subCollection(uid, 'vitals').doc(entry.id).update(updated.toMap());
    await addActivityLog(
      uid: uid,
      type: 'vitals_updated',
      title: 'Vitals updated',
      details:
          'Temperature ${entry.temperature.toStringAsFixed(1)}°F, BP ${entry.systolic}/${entry.diastolic}, pain ${entry.painLevel}.',
      actor: 'Caregiver',
      meta: {'vitalId': entry.id, 'alertReasons': alertReasons},
    );
    if (alertReasons.isNotEmpty) {
      await NotificationService.instance.showAbnormalVitalsAlert(alertReasons);
    }
    return updated;
  }

  Stream<List<AppointmentEntry>> watchAppointments(String uid) {
    return _subCollection(uid, 'appointments')
        .orderBy('appointmentDateTime')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentEntry.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> saveAppointment({
    required String uid,
    required AppointmentEntry appointment,
  }) async {
    final ref = _subCollection(uid, 'appointments').doc();
    try {
      await ref.set({...appointment.toMap(), 'id': ref.id});
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError(
          'Permission denied while saving appointment. Check Firestore rules for users/$uid/appointments.',
        );
      }
      rethrow;
    }
    await addActivityLog(
      uid: uid,
      type: 'appointment_added',
      title: 'Appointment added',
      details:
          'Appointment with ${appointment.doctorName} scheduled for ${_shortDate(appointment.appointmentDateTime)}.',
      actor: 'System',
      meta: {'appointmentId': ref.id},
    );
  }

  Future<void> updateAppointmentStatus({
    required String uid,
    required String appointmentId,
    required AppointmentStatus status,
  }) async {
    await _subCollection(uid, 'appointments').doc(appointmentId).update({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addActivityLog(
      uid: uid,
      type: 'appointment_status_changed',
      title: 'Appointment ${status.label.toLowerCase()}',
      details: 'Appointment status updated to ${status.label}.',
      actor: 'Caregiver',
      meta: {'appointmentId': appointmentId, 'status': status.name},
    );
  }

  Stream<List<ActivityLogEntry>> watchActivityLogs(String uid) {
    return _subCollection(uid, 'activity_logs')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ActivityLogEntry.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> addActivityLog({
    required String uid,
    required String type,
    required String title,
    required String details,
    required String actor,
    Map<String, dynamic> meta = const {},
  }) async {
    final ref = _subCollection(uid, 'activity_logs').doc();
    await ref.set(
      ActivityLogEntry(
        id: ref.id,
        type: type,
        title: title,
        details: details,
        actor: actor,
        createdAt: DateTime.now(),
        meta: meta,
      ).toMap(),
    );

    const caregiverTriggerTypes = <String>{
      'care_note_added',
      'vitals_logged',
      'critical_alert',
      'medication_taken',
      'medication_missed',
      'medication_added',
      'medication_status_changed',
    };
    if (caregiverTriggerTypes.contains(type)) {
      final name = actor.trim().isEmpty ? 'Caregiver' : actor.trim();
      await NotificationService.instance.showCaregiverActivityNotification(
        caregiverName: name,
      );
    }
  }

  Stream<List<DocumentEntry>> watchDocuments(String uid) {
    return _subCollection(uid, 'documents')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => DocumentEntry.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<DocumentEntry> uploadDocument({
    required String uid,
    required PlatformFile file,
  }) async {
    final bytes = await _readBytes(file);

    final cleanName = file.name.replaceAll(' ', '_');
    final storagePath =
        'users/$uid/documents/${DateTime.now().millisecondsSinceEpoch}_$cleanName';
    await _runStorageOperation(
      () => _storage.uploadBinary(
        storagePath,
        bytes,
        fileOptions: supabase.FileOptions(
          contentType: _contentTypeForExtension(file.extension),
        ),
      ),
      action: 'Document upload',
    );
    final downloadUrl = _storage.getPublicUrl(storagePath);
    final docRef = _subCollection(uid, 'documents').doc();
    final entry = DocumentEntry(
      id: docRef.id,
      fileName: file.name,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      fileSizeBytes: file.size,
      mimeType: file.extension ?? 'application/octet-stream',
      addedBy: _auth.currentUser?.displayName ?? 'Caregiver',
      createdAt: DateTime.now(),
    );
    await docRef.set({...entry.toMap(), 'id': docRef.id});
    await addActivityLog(
      uid: uid,
      type: 'document_uploaded',
      title: 'Document uploaded',
      details: '${file.name} was uploaded to storage.',
      actor: _auth.currentUser?.displayName ?? 'Caregiver',
      meta: {'documentId': docRef.id},
    );
    return entry;
  }

  Future<Map<String, String>> uploadVitalPhoto({
    required String uid,
    required PlatformFile file,
  }) async {
    final bytes = await _readBytes(file);
    final cleanName = file.name.replaceAll(' ', '_');
    final storagePath =
        'users/$uid/vitals/${DateTime.now().millisecondsSinceEpoch}_$cleanName';
    await _runStorageOperation(
      () => _storage.uploadBinary(
        storagePath,
        bytes,
        fileOptions: supabase.FileOptions(
          contentType: _contentTypeForExtension(file.extension) ?? 'image/*',
        ),
      ),
      action: 'Vital photo upload',
    );
    return {
      'storagePath': storagePath,
      'downloadUrl': _storage.getPublicUrl(storagePath),
    };
  }

  Future<void> deleteDocument({
    required String uid,
    required DocumentEntry document,
  }) async {
    await _runStorageOperation(
      () => _storage.remove([document.storagePath]),
      action: 'Document delete',
    );
    await _subCollection(uid, 'documents').doc(document.id).delete();
    await addActivityLog(
      uid: uid,
      type: 'document_deleted',
      title: 'Document deleted',
      details: '${document.fileName} was removed.',
      actor: _auth.currentUser?.displayName ?? 'Caregiver',
      meta: {'documentId': document.id},
    );
  }

  Future<void> clearActivityHistory(String uid) async {
    final snapshot = await _subCollection(uid, 'activity_logs').get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<String> resolveCareContextUid(User user) async {
    try {
      final userSnapshot = await _userDoc(user.uid).get();
      final patientIds = (userSnapshot.data()?['patientIds'] as List?)?.whereType<String>().toList() ?? const <String>[];
      if (patientIds.isNotEmpty) {
        return patientIds.first;
      }
    } catch (_) {
      // Fall through to legacy care-context resolution.
    }

    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return user.uid;

    try {
      final snapshot = await _firestore
          .collectionGroup('caregivers')
          .where('contact', isEqualTo: email)
          .get();
      if (snapshot.docs.isEmpty) return user.uid;

      String? ownerUid;
      for (final doc in snapshot.docs) {
        final ownerRef = doc.reference.parent.parent;
        if (ownerRef == null) continue;
        ownerUid ??= ownerRef.id;

        final status = (doc.data()['inviteStatus'] as String? ?? 'pending')
            .toLowerCase();
        if (status != 'accepted') {
          await doc.reference.set({
            'inviteStatus': 'accepted',
            'acceptedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      return ownerUid ?? user.uid;
    } catch (_) {
      return user.uid;
    }
  }

  int medicationAdherencePercent(List<ActivityLogEntry> logs) {
    final taken = logs.where((log) => log.type == 'medication_taken').length;
    final missed = logs.where((log) => log.type == 'medication_missed').length;
    final total = taken + missed;
    if (total == 0) return 0;
    return ((taken / total) * 100).round();
  }

  int appointmentAttendancePercent(List<AppointmentEntry> appointments) {
    if (appointments.isEmpty) return 0;
    final completed = appointments
        .where((entry) => entry.statusValue == AppointmentStatus.completed)
        .length;
    return ((completed / appointments.length) * 100).round();
  }

  List<ActivityLogEntry> logsForRange(
    List<ActivityLogEntry> logs,
    DateTime startInclusive,
  ) {
    return logs
        .where(
          (log) =>
              log.createdAt != null && !log.createdAt!.isBefore(startInclusive),
        )
        .toList();
  }

  List<VitalEntry> vitalsForRange(
    List<VitalEntry> vitals,
    DateTime startInclusive,
  ) {
    return vitals
        .where(
          (entry) =>
              entry.createdAt != null &&
              !entry.createdAt!.isBefore(startInclusive),
        )
        .toList();
  }

  DateTime startOfToday() =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  DateTime sevenDaysAgo() => DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  ).subtract(const Duration(days: 6));

  DateTime thirtyDaysAgo() => DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  ).subtract(const Duration(days: 29));

  /// Mark a caregiver invitation as accepted after password creation
  Future<void> acceptCaregiverInvite({
    required String ownerUid,
    required String caregiverEmail,
    required String caregiverUid,
  }) async {
    final snapshot = await _firestore
        .collectionGroup('caregivers')
        .where('contact', isEqualTo: caregiverEmail.toLowerCase())
        .get();

    if (snapshot.docs.isEmpty) {
      throw StateError('Invitation not found for $caregiverEmail');
    }

    for (final doc in snapshot.docs) {
      final parentPath = doc.reference.parent.parent?.path;
      if (parentPath != null && parentPath.contains(ownerUid)) {
        final role = CaregiverRoleX.fromValue(doc.data()['role'] as String?).name;
        await doc.reference.update({
          'inviteStatus': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedBy': caregiverUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await _patientCaregiverDoc(ownerUid, caregiverUid).set(
          {
            'uid': caregiverUid,
            'email': caregiverEmail.toLowerCase(),
            'role': role,
            'status': 'accepted',
            'acceptedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        await _userDoc(caregiverUid).set(
          {
            'patientIds': FieldValue.arrayUnion([ownerUid]),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }
  }
}

