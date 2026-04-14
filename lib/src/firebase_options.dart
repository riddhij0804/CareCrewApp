import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static void _assertConfigured() {
    final missing = <String>[];
    if (_apiKey.isEmpty) missing.add('FIREBASE_API_KEY');
    if (_appId.isEmpty) missing.add('FIREBASE_APP_ID');
    if (_messagingSenderId.isEmpty) {
      missing.add('FIREBASE_MESSAGING_SENDER_ID');
    }
    if (_projectId.isEmpty) missing.add('FIREBASE_PROJECT_ID');
    if (_storageBucket.isEmpty) missing.add('FIREBASE_STORAGE_BUCKET');

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing Firebase --dart-define values: ${missing.join(', ')}',
      );
    }
  }

  static FirebaseOptions get currentPlatform {
    _assertConfigured();
    return const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      storageBucket: _storageBucket,
    );
  }
}
