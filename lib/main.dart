import 'package:carecrew_app/src/app.dart';
import 'package:carecrew_app/src/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    initError = error.toString();
  }

  if (initError == null) {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      initError =
          'Missing Supabase --dart-define values: SUPABASE_URL, SUPABASE_ANON_KEY';
    } else {
      try {
        await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      } catch (error) {
        initError = 'Supabase init failed: $error';
      }
    }
  }

  // Initialize deep link listener
  final appLinks = AppLinks();
  
  runApp(
    ProviderScope(
      child: CareCrewApp(firebaseInitError: initError, appLinks: appLinks),
    ),
  );
}
