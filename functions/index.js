const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.onCallInitiated = functions.firestore
  .document("calls/{callId}")
  .onCreate(async (snap, context) => {
    const callData = snap.data();
    const receiverId = callData.receiverId;
    const callerName = callData.callerName;
    const callerId = callData.callerId;
    const isVideo = callData.isVideo;

    // Get the receiver's FCM token
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

    // Prepare FCM data payload for flutter_callkit_incoming
    // CallKit reads data from FCM and displays the call screen
    const payload = {
      token: token,
      data: {
        id: snap.id, // Call ID (channelName for Agora)
        nameCaller: callerName,
        handle: "Connect Call", // Appears below name
        type: isVideo ? "1" : "0", // 0 for audio, 1 for video
        extra: JSON.stringify({ callerId: callerId, isVideo: isVideo })
      },
      android: {
        priority: "high",
      },
      apns: {
        headers: {
          "apns-priority": "10",
        },
      }
    };

    try {
      await admin.messaging().send(payload);
      console.log("Push notification sent to " + receiverId);
    } catch (e) {
      console.error("Error sending push: ", e);
    }
  });
