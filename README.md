# CareCrew

CareCrew is a Firebase-backed Flutter app for patient setup, medication tracking, vitals, documents, caregivers, appointments, and activity history.

## What is already wired

- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Riverpod state management
- Real-time streams for user data
- Single-user data isolation under `users/{uid}/...`

## What you still must do in Firebase Console

1. Make sure the Android app registered in Firebase matches the package name used by this project.
	- Current app package: `com.carecrew.carecrew_app`
	- The `google-services.json` currently in the project was generated for `com.example.carecrewapp`, so it should be replaced with the file for the actual package you want to ship.
2. Enable Authentication -> Sign-in method -> Email/Password.
3. Create Firestore in production or test mode, then apply your own security rules.
4. Enable Firebase Storage.
5. If you want phone login, enable Phone authentication and configure reCAPTCHA / APNs where needed.
6. If you use App Check, add a provider; otherwise the warning about no App Check provider can be ignored for local development.

## Run It

1. Install Flutter dependencies.
	```bash
	flutter pub get
	```
2. Make sure the matching `google-services.json` is in `android/app/`.
3. Copy `firebase.env.example.json` to `firebase.env.json` and fill your real values.
4. Run with `--dart-define-from-file` (keeps keys out of git).
	```bash
	cp firebase.env.example.json firebase.env.json
	flutter run --dart-define-from-file=firebase.env.json
	```
5. For release builds, pass the same file.
	```bash
	flutter build apk --dart-define-from-file=firebase.env.json
	```

## Important note

The sign-up error you saw means Firebase is still not configured correctly for this app. The code now uses real project values, but the Android package name and Firebase app registration must still match exactly for production use.
