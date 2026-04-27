import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static const String _fallbackApiKey =
      'AIzaSyD92nKn-VrhZIyUk6tB1amU1H1v7K82EKc';
  static const String _fallbackAppId =
      '1:145045453389:android:c4148f27c3dc7c86ecfa04';
  static const String _fallbackMessagingSenderId = '145045453389';
  static const String _fallbackProjectId = 'madlab-77d86';
  static const String _fallbackStorageBucket =
      'madlab-77d86.firebasestorage.app';

  static const String _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: _fallbackApiKey,
  );
  static const String _appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: _fallbackAppId,
  );
  static const String _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: _fallbackMessagingSenderId,
  );
  static const String _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: _fallbackProjectId,
  );
  static const String _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: _fallbackStorageBucket,
  );
  static const String _webAppId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '',
  );
  static const String _authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: '',
  );
  static const String _measurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
    defaultValue: '',
  );

  static void _assertAndroidConfigured() {
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

  static void _assertWebConfigured() {
    final missing = <String>[];
    if (_apiKey.isEmpty) missing.add('FIREBASE_API_KEY');
    if (_webAppId.isEmpty) missing.add('FIREBASE_WEB_APP_ID');
    if (_messagingSenderId.isEmpty) {
      missing.add('FIREBASE_MESSAGING_SENDER_ID');
    }
    if (_projectId.isEmpty) missing.add('FIREBASE_PROJECT_ID');
    if (_storageBucket.isEmpty) missing.add('FIREBASE_STORAGE_BUCKET');

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing Firebase web --dart-define values: ${missing.join(', ')}',
      );
    }
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      _assertWebConfigured();
      final resolvedAuthDomain =
          _authDomain.isNotEmpty ? _authDomain : '$_projectId.firebaseapp.com';
      return FirebaseOptions(
        apiKey: _apiKey,
        appId: _webAppId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        storageBucket: _storageBucket,
        authDomain: resolvedAuthDomain,
        measurementId: _measurementId.isEmpty ? null : _measurementId,
      );
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Firebase is currently configured only for Android in this project.',
      );
    }

    _assertAndroidConfigured();
    return const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      storageBucket: _storageBucket,
    );
  }
}
