# ConnectCall App - Version 1 Architecture & Calling Flow

**Project:** ConnectCall
**Tech Stack:** Flutter, Riverpod (State Management), Firebase (Auth, Firestore, FCM), Agora RTC Engine, Flutter Callkit Incoming.
**Purpose:** A detailed architectural reference for the highly complex Video/Audio Calling system, specifically focusing on native background states, terminated routing, and fail-safes.

---

## 1. Core Architecture & Routing
The app follows a clean, reactive architecture using Riverpod.
- **`main.dart`**: The entry point. It handles Firebase initialization, registers FCM background handlers, and initializes `CallService`.
- **`ConnectCallApp`**: The root widget. It is a `ConsumerStatefulWidget` intentionally made stateful to handle **Cold Start Routing** (explained below).
- **`AuthWrapper`**: Acts as the default home. It dynamically routes the user to `LoginScreen`, `ProfileSetupScreen`, or `HomeScreen` based on Firebase Auth state.

## 2. Call Initiation (Caller Side)
When User A calls User B:
1. **Firestore Call Document**: A document is created in the `calls` collection using the **Caller's UID** as the document ID. This document tracks the status (`calling`, `accepted`, `ended`, `declined`, `missed`).
2. **Push Notification (FCM)**: The backend/Firebase sends an FCM data payload to the Receiver's device token containing `callId`, `callerName`, `isVideo`, `agoraChannelId`, etc.
3. **Agora Initialization**: The Caller's UI pushes `VideoCallScreen`, initializes the Agora `RtcEngine`, requests camera/mic permissions, and joins the channel.

## 3. Incoming Call Handling (Receiver Side)
1. **FCM Background Handler**: Even if the app is killed, the `@pragma('vm:entry-point')` FCM handler catches the data payload.
2. **CallKit Trigger**: The FCM handler triggers `FlutterCallkitIncoming.showCallkitIncoming(params)`. This shows the Native Android/iOS incoming call UI (Heads-up or Full-screen lock screen).
3. **CallKit Event Listener**: `CallService.init()` listens to user actions (`Accept`, `Decline`).
   - If **Declined**: Updates Firestore to `declined`, Native CallKit ends the call.
   - If **Accepted**: Pushes the Flutter routing to `VideoCallScreen` and initializes Agora.

## 4. The "Cold Start / Terminated State" Problem & Fix
**Problem:** If the app is completely killed, and the user clicks "Accept" on the Native CallKit UI, Flutter starts from scratch. The background event listener often misses the initial `CallEventActionCallAccept` event because the Flutter UI engine isn't ready.

**The Fix:**
Inside the `initState` of `ConnectCallApp` (the absolute root widget), we check for active calls upon startup:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  final activeCalls = await FlutterCallkitIncoming.activeCalls();
  if (activeCalls is List && activeCalls.isNotEmpty) {
    final call = activeCalls[0];
    // Parse the payload (call.extra)
    // Directly pushReplacement to VideoCallScreen
  }
});
```
*Why `addPostFrameCallback`?* It ensures the first frame (HomeScreen/AuthWrapper) is drawn, so the `navigatorKey` is mounted before we forcefully push the call screen over it.

## 5. The "Empty Navigation Stack" Problem & Fix
**Problem:** Because the Cold Start forcefully pushed `VideoCallScreen` using `pushReplacement` over the root route, the navigation stack behind it is EMPTY. When the call ends, calling `Navigator.pop()` fails, leaving the user stuck on a frozen/black screen.

**The Fix:**
In our `_endCall()` logic, we must check if we CAN pop. If the stack is empty, we must forcefully push the Home screen:
```dart
if (Navigator.of(context).canPop()) {
  Navigator.of(context).pop();
} else {
  // Empty stack (cold start), push Home forcefully
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const HomeScreen()),
    (route) => false,
  );
}
```

## 6. Remote User Offline Handling & Fail-safes
When the remote user cuts the call or loses network, the local UI must automatically close to prevent the user from being stuck in an empty room. This requires a dual fail-safe approach:

1. **Agora `onUserOffline` Event (Primary):**
   Inside the Agora `RtcEngineEventHandler`, when `onUserOffline` fires, we set a state flag `isCallEndedByRemote = true`. The UI listens to this state and triggers `_endCall()`.
2. **Firestore Stream Listener (Fallback):**
   In `VideoCallScreen`'s `initState`, we listen to the Firestore call document. If the status changes to `ended` or `declined` (because the other user tapped Hang Up), it triggers `_endCall()`.

## 7. App Teardown & PopScope Safety
**Problem:** Physical back button presses must not instantly kill the app during a call. Also, tearing down the camera/mic while the UI is rebuilding can cause a `Null check operator` crash.

**The Fix:**
- **PopScope (`canPop: false`)**: Wraps the `VideoCallScreen` Scaffold. If the user presses the back button, it intercepts it, blocks the pop, and gracefully runs `_endCall()`.
- **Async Teardown**: `_endCall()` sets an `_isEnding` flag to prevent duplicate calls. It releases the Agora Engine *in the background* (`_engine = null`), updates Firestore, and ONLY then allows the navigation.
- **Null Safety in UI**: During teardown, the UI might rebuild. The remote video widget MUST check `agoraNotifier.engine == null` before rendering `AgoraVideoView` to prevent null crashes.

---
*Created as a core reference for scaling and maintaining production-level VoIP architecture in Flutter.*
