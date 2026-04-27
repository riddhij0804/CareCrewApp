# CareCrew

CareCrew is a mobile app for families and caregivers who need one place to coordinate a patient’s daily care. It helps answer a simple problem: when care is split across medicines, vitals, appointments, documents, and multiple people, important things get missed or scattered. CareCrew brings all of that into one shared flow so the patient’s recovery can be followed with less confusion and less delay.

## What is already wired

- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Riverpod state management
- Real-time streams for user data
- Single-user data isolation under `users/{uid}/...`

## Care Circle Schema (Extended)

The app now supports shared patient membership and invite workflows while keeping legacy `users/{uid}/...` collections compatible.

### Shared patient membership

```text
patients/{patientId}/
	profile/main
	caregivers/{uid}:
		role: "admin" | "editor" | "viewer" | "doctor"
		status: "accepted"

users/{uid}/
	patientIds: [patientId, ...]
```

### Invites

```text
invites/{inviteId}:
	patientId
	invitedUserId (optional until bound)
	invitedEmail
	role
	status: "pending" | "accepted" | "rejected"
	invitedBy
	createdAt
	respondedAt
```

## What you still must do in Firebase Console

1. Make sure the Android app registered in Firebase matches the package name used by this project.
	- Current app package: `com.carecrew.carecrew_app`
	- The `google-services.json` currently in the project was generated for `com.example.carecrewapp`, so it should be replaced with the file for the actual package you want to ship.
2. Enable Authentication -> Sign-in method -> Email/Password.
3. Create Firestore in production or test mode, then apply your own security rules.
4. Enable Firebase Storage.
5. If you want phone login, enable Phone authentication and configure reCAPTCHA / APNs where needed.
6. If you use App Check, add a provider; otherwise the warning about no App Check provider can be ignored for local development.
## The Problem

Caregiving usually fails in small ways, not one big way. A medicine is forgotten. A symptom is not written down. An appointment gets buried in a chat thread. A caregiver does not know what someone else already handled. Over time, that creates stress for the family and makes it harder to keep the patient safe and consistent.

## The Proposed Solution

CareCrew solves that by turning care into a clear sequence:

1. The family signs in or creates an account.
2. The patient’s basic information is added once.
3. Caregivers can be invited so everyone works from the same care space.
4. Daily tasks like medications and vitals are tracked in one place.
5. Appointments, documents, and activity history stay available for reference.
6. Progress can be reviewed anytime from a single dashboard.

The goal is not just storing information. The goal is to make the next care action obvious.

## Full User Flow

### 1. Start Here

The app opens to authentication. A user can sign in if they already have an account, or create a new one if they are starting fresh.

### 2. Set Up the Patient

After sign-up or first sign-in, the app asks for the patient’s core details. This includes the patient’s name, age, discharge date, and primary condition. This step creates the center of the care record so everything else can attach to it.

### 3. Bring In the Care Team

The next step is to add caregivers. These may be family members, friends, or professionals. The purpose is to make care shared instead of isolated. Everyone involved can work from the same patient context instead of maintaining separate notes.

### 4. Move Into the Main Dashboard

Once setup is complete, the app opens the main care dashboard. This is the daily control center. It shows the current state of care, what has already been done, what still needs attention, and what comes next.

### 5. Track Daily Care

From the dashboard, the user can manage the main parts of care:

- Medicines: add scheduled medicines, see what is due today, mark doses as taken, and notice low stock early.
- Vitals: record readings such as temperature, blood pressure, pain level, and optional symptom photos.
- History: review the activity trail so the family can see what happened and when.
- Care Team: view who is involved in the patient’s care and keep the support network organized.
- Appointments and documents: keep visits and important files easy to reach when needed.

### 6. Watch Progress Over Time

CareCrew is meant to support the full recovery period, not just a single visit. The app keeps a running history of actions and trends so the family can see whether care is staying on track or if something needs attention.

### 7. Respond Quickly When Needed

If something urgent happens, the app keeps emergency access visible so the caregiver can react without searching through different screens.

## What CareCrew Gives the User

- A single place to organize patient care.
- A simple onboarding flow that gets the care record started quickly.
- Shared visibility for caregivers.
- Daily reminders through visible care tasks.
- A record of medicines, vitals, appointments, and activities.
- Better continuity, especially when several people are involved in the same patient journey.

## Setup Notes

This project uses Firebase and Flutter. If you are running it locally, make sure your Firebase project is configured correctly, then provide the values required by the app before launching.

1. Install Flutter dependencies.
	```bash
	flutter pub get
	```
2. Make sure the matching `google-services.json` is in `android/app/`.
3. Copy `firebase.env.example.json` to `firebase.env.json` and fill your real values.
4. Run with `--dart-define-from-file`.
	```bash
	cp firebase.env.example.json firebase.env.json
	flutter run --dart-define-from-file=firebase.env.json
	```
5. For release builds, pass the same file.
	```bash
	flutter build apk --dart-define-from-file=firebase.env.json
	```

## Firebase Checklist

1. Make sure the Android app registered in Firebase matches the package name used by this project.
	- Current app package: `com.carecrew.carecrew_app`
	- The `google-services.json` currently in the project was generated for `com.example.carecrewapp`, so it should be replaced with the file for the actual package you want to ship.
2. Enable Authentication -> Sign-in method -> Email/Password.
3. Create Firestore in production or test mode, then apply your own security rules.
4. Enable Firebase Storage.
5. If you want phone login, enable Phone authentication and configure reCAPTCHA / APNs where needed.
6. If you use App Check, add a provider; otherwise the warning about no App Check provider can be ignored for local development.

## Important Note

If sign-in or sign-up fails, the most common cause is still Firebase configuration mismatch. The app expects the Firebase project, Android package name, and generated configuration file to all match the same setup.
