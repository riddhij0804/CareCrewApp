import 'package:carecrew_app/src/app.dart';
import 'package:carecrew_app/src/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? firebaseInitError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    firebaseInitError = error.toString();
  }

  runApp(
    ProviderScope(
      child: CareCrewApp(firebaseInitError: firebaseInitError),
    ),
  );
}
