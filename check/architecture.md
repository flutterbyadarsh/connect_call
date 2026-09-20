# Call Flow Architecture & State Flags

## 1. Call Initiation (Caller -> Receiver)
- Caller clicks 'Video' or 'Audio' in `ContactsTab` or `CallLogsTab`.
- A transaction locks `isBusy = true` for both users in `/users`.
- A document is created in `/calls` with `status = 'ringing'`.
- Caller pushes `VideoCallScreen` locally.

## 2. Notification (Backend -> Receiver)
- Cloud function `onCallCreated` detects the `/calls` document creation.
- Sends an FCM data payload to the Receiver's device.

## 3. Receiving (Receiver Side)
- If App is killed/background: `FirebaseMessaging.onBackgroundMessage` catches FCM and shows local notification using `flutter_local_notifications`.
- If App is foreground (or when user taps notification): `HomeScreen` `CallService.startListeningForCalls` stream detects `status == 'ringing'`.
- Pushes `IncomingCallScreen`.

## 4. Answering / Declining (Receiver Side)
- **Accept**: Receiver clicks Accept. `status` changes to `'accepted'`. Receiver pushes `VideoCallScreen` and joins Agora.
- **Decline**: Receiver clicks Decline. `status` changes to `'declined'`. Receiver pops `IncomingCallScreen`.

## 5. Synchronizing (Caller Side)
- Caller's `VideoCallScreen` listens to the `/calls` document stream.
- If `status == 'accepted'`, caller cancels the 45s missed call timer.
- If `status == 'declined'`, caller pops `VideoCallScreen`.

## Current Bugs / Weak Points:
- "Notify some time latter": Awaiting Firestore transactions on Accept/Decline causes UI lag. (Partially addressed, needs verification).
- "Validation bhi nhi show ho rha hai": `PopScope` blocking `Navigator.pop()` inside `setState`. 
- "Screen black aarha hai": The `RtcConnection(channelId)` is using `UUID` instead of the actual `agoraChannelId`.
- **Potential New Bug**: When `disposeEngine` is fire-and-forget, it might try to update Firestore when the user no longer has internet, but this is acceptable. The main issue is navigation state getting out of sync.

## Action Plan:
Step 1: Verify all `Navigator.pop()` calls inside `VideoCallScreen`, `AudioCallScreen`, and `IncomingCallScreen`. Ensure `PopScope` is correctly configured so that it NEVER blocks legitimate code-triggered pops.
Step 2: Ensure `RtcConnection` uses `agoraChannelId` EVERYWHERE (in `agora_service.dart`, `video_call_screen.dart`, etc.).
Step 3: Test local notification flow.
