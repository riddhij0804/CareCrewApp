# CareCrew Caregiver Invite System - Setup Guide

## Overview
This guide walks through setting up the complete caregiver invitation system with email delivery, deep links, and password creation.

## 1. Firebase Cloud Functions Setup

### 1.1 Install Firebase CLI
```bash
npm install -g firebase-tools
firebase login
```

### 1.2 Build Cloud Functions
```bash
cd functions
npm install
npm run build
```

### 1.3 Configure Environment Variables
Create a `.env.local` file in the `functions` directory (for local testing):

Option A: Using SendGrid (Recommended)
```
SENDGRID_API_KEY=your_sendgrid_api_key
SENDER_EMAIL=noreply@carecrew.app
```

Option B: Using Gmail SMTP
```
GMAIL_USER=your_email@gmail.com
GMAIL_PASSWORD=your_app_password  # Use App Password if 2FA enabled
SENDER_EMAIL=your_email@gmail.com
```

### 1.4 Deploy Cloud Functions
```bash
cd functions
firebase deploy --only functions
```

This will deploy:
- `sendCaregiverInvite`: Triggered on caregiver creation, sends invitation email
- `acceptInvite`: Callable function to accept invitation with password

## 2. Firestore Security Rules

Update your Firestore rules to allow multi-tenant invite pattern:

```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection - owner access
    match /users/{uid} {
      allow read, write: if request.auth.uid == uid;
      
      // Allow caregivers to read owner's data if they're accepted
      allow read: if exists(/databases/$(database)/documents/users/$(uid)/caregivers/$(request.auth.uid))
                  && get(/databases/$(database)/documents/users/$(uid)/caregivers/$(request.auth.uid)).data.inviteStatus == 'accepted';
      
      // Sub-collections: patient, medications, appointments, vitals, activity_logs, documents, caregivers, thresholds
      match /{subcollection=**} {
        allow read, write: if request.auth.uid == uid;
        
        // Caregivers sub-collection - special handling for email matching
        match /caregivers/{page} {
          // Owner can read/write caregivers
          allow read, write: if request.auth.uid == uid;
          
          // Caregivers can read themselves (for status checking)
          allow read: if request.auth.token.email == resource.data.contact;
        }
        
        // Allow accepted caregivers to read all other sub-collections
        allow read: if exists(/databases/$(database)/documents/users/$(uid)/caregivers/$(request.auth.uid))
                    && get(/databases/$(database)/documents/users/$(uid)/caregivers/$(request.auth.uid)).data.inviteStatus == 'accepted';
      }
    }
  }
}
```

## 3. iOS Deep Link Configuration

### 3.1 Update ios/Runner/Info.plist
Add URL scheme for deep links:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>carecrew</string>
    </array>
  </dict>
</array>
```

### 3.2 Update ios/Runner.xcodeproj
In Xcode:
1. Select target "Runner"
2. Go to Info tab
3. Add URL Types:
   - Identifier: `com.example.carecrew`
   - URL Schemes: `carecrew`

## 4. Android Deep Link Configuration

### 4.1 Update android/app/src/main/AndroidManifest.xml

Add intent filter to the MainActivity:

```xml
<activity
  android:name=".MainActivity"
  android:launchMode="singleTop"
  ...>
  <intent-filter>
    <action android:name="android.intent.action.MAIN" />
    <category android:name="android.intent.category.LAUNCHER" />
  </intent-filter>
  
  <!-- Deep link intent filter -->
  <intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="carecrew" android:host="accept-invite" />
  </intent-filter>
</activity>
```

## 5. Testing Deep Links

### iOS Testing
```bash
xcrun simctl openurl booted "carecrew://accept-invite/ABC123?email=caregiver@example.com&uid=owneruserid"
```

### Android Testing
```bash
adb shell am start -W -a android.intent.action.VIEW -d "carecrew://accept-invite/ABC123?email=caregiver@example.com&uid=owneruserid" com.example.carecrew_app
```

## 6. Email Sending Flow

### How It Works:

1. **Owner invites caregiver** in Care Circle screen
   - Enters caregiver name, email, mobile, role
   - System generates unique `inviteCode` (6-char alphanumeric)
   - Caregiver document created with `inviteStatus: 'pending'`

2. **Cloud Function triggered** (Firestore onCreate)
   - Fetches invitation document
   - Generates deep link: `carecrew://accept-invite/{inviteCode}?email={email}&uid={ownerUid}`
   - Sends email with link via SendGrid/Gmail/SMTP
   - Updates document: `inviteSentStatus: 'sent'`

3. **Caregiver receives email**
   - Email contains "Accept Invitation" button linking to deep link
   - Can also copy link from email body

4. **Caregiver clicks link**
   - Deep link handler in app detects `carecrew://accept-invite/` scheme
   - Shows `AcceptInviteScreen`
   - Caregiver enters name + creates password
   - System creates Firebase Auth user
   - Marks invitation as `inviteStatus: 'accepted'`
   - User auto-logged in and can see owner's data

## 7. Testing the Complete Flow

### Step 1: Local Cloud Function Testing
```bash
cd functions
npm run start
# Emulator will display local function URLs
```

### Step 2: Create Test Invitation
1. Sign up as owner (Owner A)
2. Create patient profile
3. Go to Care Circle → "Invite to Circle"
4. Enter:
   - Name: "John Caregiver"
   - Email: "caregiver@example.com"
   - Mobile: "+1-123-456-7890"
   - Role: "Viewer"
   - Send Invite

### Step 3: Check Email
- If using local emulator, check Cloud Function logs for email content
- If using SendGrid/Gmail, check email inbox

### Step 4: Accept Invitation
- Click link or copy deep link
- Run deep link command (see Section 5)
- Enter password
- Create account

### Step 5: Verify Multi-User Access
1. Sign out Owner A
2. Sign in with new caregiver account
3. Verify caregiver can see all owner's data:
   - Medications
   - Appointments
   - Vitals
   - Documents
   - Activity history

## 8 Troubleshooting

### Issue: Emails not sending

**Check 1: Cloud Function logs**
```bash
firebase functions:log --project=your_project_id
```

**Check 2: SMTP credentials**
- Verify `SENDGRID_API_KEY` or `GMAIL_USER` + `GMAIL_PASSWORD` are set
- For Gmail: Create App Password (not regular password)

**Check 3: Firestore Rules**
- Ensure function has permission to update caregiver document
- Check if collection exists: `users/{uid}/caregivers`

### Issue: Deep link not opening app

**iOS:**
- Verify `CFBundleURLSchemes` contains `carecrew` in Info.plist
- Test with `xcrun simctl openurl` command

**Android:**
- Verify intent filter has `<data android:scheme="carecrew" android:host="accept-invite">`
- Test with `adb shell am start` command

### Issue: Caregiver can't see owner's data

**Check: Firestore Rules**
```sql
-- Verify caregiver can:
1. View users/{ownerUid}/caregivers/{caregiverUid}
2. inviteStatus == 'accepted'
3. Can read all sub-collections under users/{ownerUid}/
```

**Check: Invitation Status**
- Go to Firestore Console
- Navigate to `users/{ownerUid}/caregivers/{caregiverId}`
- Verify `inviteStatus: 'accepted'`
- Verify `inviteCode` matches email link

## 9. Production Checklist

- [ ] SendGrid API key configured in Cloud Functions
- [ ] SENDER_EMAIL set to your domain email
- [ ] Firestore rules updated with multi-tenant permissions
- [ ] iOS Info.plist updated with URL schemes
- [ ] Android AndroidManifest.xml updated with intent filters
- [ ] Cloud Functions deployed (`firebase deploy --only functions`)
- [ ] Test invitation flow with real email
- [ ] Verify deep links work on device
- [ ] Test caregiver access to owner data
- [ ] Document password reset flow
- [ ] Set up monitoring for function errors

## 10. Architecture Diagram

```
Invite Flow:
Owner App                 Firebase                 Cloud Function           Email Service
   |                         |                            |                        |
   | 1. Send Invite           |                            |                        |
   |---(caregiverEntry)------>|                            |                        |
   |                          |                            |                        |
   |                  2. onCreate trigger                  |                        |
   |                          |----------(inviteCode)----->|                        |
   |                          |                            | 3. Render Email        |
   |                          |                            | with deep link         |
   |                          |                            |                        |
   |                          |                            |-----(HTML Email)------>|
   |                          |                            |                        |
   |             4. Update doc |                            |                        |
   |          (sent status)    |                            |                        |
   |                          |                            |                        |
   |                                                                               |
   |                                                   Caregiver Inbox            |
   |                                                        |
   |                                                        | 5. Click Link
   |                                                        |
   | 6. Deep Link Handler Opens App
   | 7. Show AcceptInviteScreen
   | 8. Create Firebase User + Set Password
   | 9. Mark Invite as Accepted
   | 10. Auto-Login & Show Owner Data
```

## 11. Next Steps

1. Deploy Cloud Functions
2. Update Firestore Security Rules
3. Configure deep links for iOS/Android
4. Test the complete invitation flow
5. Monitor Cloud Function logs for errors
6. Gather feedback from test users
