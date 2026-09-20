const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { RtcTokenBuilder, RtcRole } = require("agora-token");

admin.initializeApp();

const AGORA_APP_ID = "99082f23cb0047f8893f5b8ac23d50a7";
const AGORA_APP_CERTIFICATE = "7fa0bf897d9c4bb587e3d1124489d287";

// ─── Agora Token Generator ───────────────────────────────────────────────────
// Called by Flutter app before every call to get a fresh token (valid 1 hour)
exports.generateAgoraToken = onCall({ region: "asia-south1" }, async (request) => {
  const channelName = request.data.channelName;
  const uid = request.data.uid || 0;

  if (!channelName) {
    throw new Error("channelName is required");
  }

  const expirationTimeInSeconds = 3600; // 1 hour
  const currentTimestamp = Math.floor(Date.now() / 1000);
  const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

  const token = RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID,
    AGORA_APP_CERTIFICATE,
    channelName,
    uid,
    RtcRole.PUBLISHER,
    privilegeExpiredTs,
    privilegeExpiredTs
  );

  console.log(`Generated Agora token for channel: ${channelName}, uid: ${uid}`);
  return { token: token, appId: AGORA_APP_ID };
});

// ─── Incoming Call FCM ───────────────────────────────────────────────────────
// Triggered when a new call document is CREATED → sends FCM to receiver
exports.onCallInitiated = onDocumentCreated("calls/{callId}", async (event) => {
  const snap = event.data;
  if (!snap) return null;

  const callData = snap.data();
  const receiverId = callData.receiverId;
  const callerName = callData.callerName;
  const callerId = callData.callerId;
  const isVideo = callData.isVideo;
  const callId = event.params.callId;

  const userDoc = await admin.firestore().collection("users").doc(receiverId).get();
  if (!userDoc.exists) {
    console.log("No user found for id:", receiverId);
    return null;
  }

  const token = userDoc.data().fcmToken;
  if (!token) {
    console.log("No FCM token found for user:", receiverId);
    return null;
  }

  const callerPic = callData.callerPic || "";

  const payload = {
    token: token,
    data: {
      id: callId,
      nameCaller: callerName,
      avatar: callerPic,
      handle: "Connect Call",
      type: isVideo ? "1" : "0",
      extra: JSON.stringify({ callerId: callerId, isVideo: isVideo, agoraChannelId: callData.agoraChannelId }),
    },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" } },
  };

  try {
    await admin.messaging().send(payload);
    console.log("Incoming call FCM sent to", receiverId, "for call", callId);
  } catch (e) {
    console.error("Error sending incoming call FCM:", e);
  }
  return null;
});

// ─── Cancel Call FCM ─────────────────────────────────────────────────────────
// Triggered when call status changes → sends cancel FCM to dismiss callkit
exports.onCallStatusChanged = onDocumentUpdated("calls/{callId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const callId = event.params.callId;

  if (before.status === after.status) return null;

  const terminalStatuses = ["cancelled", "declined", "missed", "ended"];
  if (!terminalStatuses.includes(after.status)) return null;
  
  // Clear the busy state for both participants
  const callerId = after.callerId;
  const receiverId = after.receiverId;
  
  const batch = admin.firestore().batch();
  if (callerId) {
    batch.update(admin.firestore().collection("users").doc(callerId), { isBusy: false });
  }
  if (receiverId) {
    batch.update(admin.firestore().collection("users").doc(receiverId), { isBusy: false });
  }
  try {
    await batch.commit();
    console.log("Cleared isBusy state for caller and receiver");
  } catch(e) {
    console.error("Failed to clear isBusy state:", e);
  }

  const userDoc = await admin.firestore().collection("users").doc(receiverId).get();
  if (!userDoc.exists) return null;

  const token = userDoc.data().fcmToken;
  if (!token) return null;

  const cancelPayload = {
    token: token,
    data: {
      id: callId,
      type: "cancel",
      nameCaller: after.callerName || "Unknown",
      handle: "Connect Call",
    },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" } },
  };

  try {
    await admin.messaging().send(cancelPayload);
    console.log("Cancel FCM sent for call:", callId, "status:", after.status);
  } catch (e) {
    console.error("Error sending cancel FCM:", e);
  }
  return null;
});
