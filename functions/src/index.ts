import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as nodemailer from "nodemailer";

admin.initializeApp();
const db = admin.firestore();

// Configure email service - use SendGrid or Gmail
// For SendGrid: set SENDGRID_API_KEY environment variable
// For Gmail: set GMAIL_USER and GMAIL_PASSWORD environment variables
const getEmailTransporter = async () => {
  const sendgridApiKey = process.env.SENDGRID_API_KEY;
  const gmailUser = process.env.GMAIL_USER;
  const gmailPassword = process.env.GMAIL_PASSWORD;

  if (sendgridApiKey) {
    // SendGrid SMTP
    return nodemailer.createTransport({
      host: "smtp.sendgrid.net",
      port: 587,
      auth: {
        user: "apikey",
        pass: sendgridApiKey,
      },
    });
  } else if (gmailUser && gmailPassword) {
    // Gmail SMTP (use App Password if 2FA enabled)
    return nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: gmailUser,
        pass: gmailPassword,
      },
    });
  }

  throw new Error(
    "Email service not configured. Set SENDGRID_API_KEY or GMAIL_USER + GMAIL_PASSWORD"
  );
};

/**
 * Sends invitation email when a caregiver is added with pending status
 */
exports.sendCaregiverInvite = functions.firestore
  .document("users/{uid}/caregivers/{caregiverId}")
  .onCreate(async (snap, context) => {
    const { uid } = context.params;
    const caregiver = snap.data();

    // Only send if status is pending and inviteCode exists
    if (caregiver.inviteStatus !== "pending" || !caregiver.inviteCode) {
      return;
    }

    try {
      // Get patient profile to include in email
      const patientDoc = await db.doc(`users/${uid}/patient/main`).get();
      const patient = patientDoc.data();
      const patientName = patient?.fullName || "a patient in your care circle";

      // Build acceptance link - deep link format
      const inviteCode = caregiver.inviteCode;
      const deepLink = `carecrew://accept-invite/${inviteCode}?email=${encodeURIComponent(
        caregiver.contact
      )}&uid=${encodeURIComponent(uid)}`;

      // Build email content
      const emailSubject = `You're invited to join CareCrew for ${patientName}`;
      const emailHtml = `
        <html>
          <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
            <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
              <h2 style="color: #103A86;">You're Invited to CareCrew</h2>
              
              <p>Hi <strong>${caregiver.name}</strong>,</p>
              
              <p>You've been invited to join the care circle for <strong>${patientName}</strong>.</p>
              
              <p>Your role: <strong>${caregiver.role}</strong></p>
              
              <p style="margin-top: 20px;">To accept this invitation:</p>
              <ol>
                <li>Click the button below or copy the link</li>
                <li>Create a password when prompted</li>
                <li>Start viewing and managing care details</li>
              </ol>
              
              <p style="text-align: center; margin: 30px 0;">
                <a href="${deepLink}" style="display: inline-block; background-color: #103A86; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; font-weight: bold;">
                  Accept Invitation
                </a>
              </p>
              
              <p style="color: #666; font-size: 14px;">
                Or copy this link: <br/>
                <code style="background-color: #f5f5f5; padding: 10px; display: block; word-break: break-all;">${deepLink}</code>
              </p>
              
              <p style="color: #666; font-size: 14px; margin-top: 20px;">
                If you didn't expect this invitation or have questions, please contact the care coordinator.
              </p>
              
              <hr style="border: none; border-top: 1px solid #ddd; margin: 30px 0;"/>
              
              <p style="color: #999; font-size: 12px;">
                CareCrew | Compassionate Care Management<br/>
                This is an automated message, please do not reply.
              </p>
            </div>
          </body>
        </html>
      `;

      const transporter = await getEmailTransporter();
      
      const mailOptions = {
        from: process.env.SENDER_EMAIL || "noreply@carecrew.app",
        to: caregiver.contact,
        subject: emailSubject,
        html: emailHtml,
      };

      await transporter.sendMail(mailOptions);
      
      console.log(`Invitation email sent to ${caregiver.contact}`);

      // Update caregiver document with invitation sent timestamp and mark as sent
      await snap.ref.update({
        inviteSentAt: admin.firestore.FieldValue.serverTimestamp(),
        inviteSentStatus: "sent",
      });
    } catch (error) {
      console.error(`Failed to send invitation email to ${caregiver.contact}:`, error);
      
      // Update with error status but don't crash
      await snap.ref.update({
        inviteSentStatus: "failed",
        inviteSentError: String(error),
      });
      
      throw new functions.https.HttpsError(
        "internal",
        "Failed to send invitation email"
      );
    }
  });

/**
 * REST endpoint to accept an invitation with password creation
 * POST /acceptInvite
 * Body: { inviteCode, email, uid, password }
 */
exports.acceptInvite = functions.https.onCall(
  async (data: any, context: functions.https.CallableContext) => {
    const { inviteCode, email, uid: ownerUid, password, caregiverName } = data;

    if (!inviteCode || !email || !ownerUid || !password) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required fields: inviteCode, email, uid, password"
      );
    }

    try {
      // Verify invite exists and matches
      const caregiverSnap = await db
        .collectionGroup("caregivers")
        .where("contact", "==", email.toLowerCase())
        .where("inviteCode", "==", inviteCode)
        .limit(1)
        .get();

      if (caregiverSnap.empty) {
        throw new functions.https.HttpsError(
          "not-found",
          "Invitation not found. Please check the link and try again."
        );
      }

      const caregiverDoc = caregiverSnap.docs[0];
      const caregiver = caregiverDoc.data();

      // Verify it's for the correct owner
      if (!caregiverDoc.ref.path.includes(ownerUid)) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Invitation does not match the owner."
        );
      }

      // Create Firebase Auth user with email and password
      const userRecord = await admin.auth().createUser({
        email: email.toLowerCase(),
        password: password,
        displayName: caregiverName || caregiver.name,
      });

      // Create AppUserProfile in Firestore for the new caregiver
      await db.doc(`users/${userRecord.uid}/profile/main`).set({
        displayName: caregiverName || caregiver.name,
        email: email.toLowerCase(),
        mobileNumber: caregiver.mobile || "",
        careRole: caregiver.role || "viewer",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update caregiver entry to mark as accepted
      await caregiverDoc.ref.update({
        inviteStatus: "accepted",
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        acceptedBy: userRecord.uid,
      });

      return {
        success: true,
        message: "Invitation accepted successfully",
        uid: userRecord.uid,
        email: userRecord.email,
      };
    } catch (error: any) {
      console.error("Error accepting invite:", error);

      // Handle Firebase Auth-specific errors
      if (error.code === "auth/email-already-exists") {
        throw new functions.https.HttpsError(
          "already-exists",
          "This email is already registered. Please sign in instead."
        );
      }

      if (
        error.code === "auth/invalid-password" ||
        error.code === "auth/weak-password"
      ) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Password must be at least 6 characters."
        );
      }

      throw error instanceof functions.https.HttpsError
        ? error
        : new functions.https.HttpsError(
            "internal",
            error.message || "Failed to accept invitation"
          );
    }
  }
);
