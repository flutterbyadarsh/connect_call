import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';
import '../repositories/call_repository.dart';
import '../screens/call/incoming_call_screen.dart';
import '../screens/call/video_call_screen.dart';
import '../screens/call/audio_call_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/chat/chat_detail_screen.dart';
import '../widgets/call_waiting_banner.dart';
import 'agora_service.dart';
import 'call_feedback_service.dart';
import 'chat_notification_service.dart';

class CallService {
  static final Set<String> _processedCalls = {};
  static bool _isInitialized = false;

  /// Riverpod container reference — injected from main() after ProviderScope is built.
  static ProviderContainer? _container;

  /// Must be called after [runApp] to inject the root provider container.
  static void setContainer(ProviderContainer container) {
    _container = container;
  }

  static Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Handle foreground FCM messages (Flutter In-App UI)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleForegroundCall(message);
    });

    // Handle CallKit events (Background/Terminated Native UI)
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;

      try {
        final repository = CallRepository(FirebaseFirestore.instance);
        switch (event) {
          case CallEventActionCallAccept():
            final params = event.callKitParams;
            final id = params.id;
            final extraMap = params.extra;
            final extraString = extraMap?['extra'] as String?;

            if (id.isEmpty || extraString == null) return;

            if (_processedCalls.contains('accept_$id')) return;
            _processedCalls.add('accept_$id');

            final extra = jsonDecode(extraString);
            final agoraChannelId = extra['agoraChannelId'];
            final isVideo = extra['isVideo'] == true;

            // Zombie Call Fix: Pre-check if call was already canceled before routing/engine init
            final isAccepted = await repository.acceptCallPreCheck(id);
            if (!isAccepted) {
              await FlutterCallkitIncoming.endAllCalls();
              if (navigatorKey.currentState != null &&
                  navigatorKey.currentState!.mounted) {
                ScaffoldMessenger.of(
                  navigatorKey.currentState!.context,
                ).showSnackBar(
                  const SnackBar(content: Text('Call was canceled by caller')),
                );
                navigatorKey.currentState!.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              }
              return;
            }

            // Smart Routing: If AgoraService already owns this call (minimized),
            // just re-open the screen without re-initializing the engine.
            final agoraService = _container?.read(
              agoraServiceProvider.notifier,
            );
            final agoraState = _container?.read(agoraServiceProvider);
            if (agoraService != null &&
                agoraState != null &&
                agoraState.isCallActive &&
                agoraState.callId == id) {
              agoraService.setCallScreenVisible(true);
              if (navigatorKey.currentState != null &&
                  navigatorKey.currentState!.mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  navigatorKey.currentState!.push(
                    MaterialPageRoute(
                      builder: (_) => isVideo
                          ? VideoCallScreen(
                              callerName: id,
                              agoraChannelId: agoraChannelId,
                            )
                          : AudioCallScreen(
                              callerName: id,
                              agoraChannelId: agoraChannelId,
                            ),
                    ),
                  );
                });
              }
              break;
            }

            // Route to Video/Audio screen directly (fresh call)
            void routeToCall() {
              if (navigatorKey.currentState != null &&
                  navigatorKey.currentState!.mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  navigatorKey.currentState!.push(
                    MaterialPageRoute(
                      builder: (_) => isVideo
                          ? VideoCallScreen(
                              callerName: id,
                              agoraChannelId: agoraChannelId,
                            )
                          : AudioCallScreen(
                              callerName: id,
                              agoraChannelId: agoraChannelId,
                            ),
                    ),
                  );
                });
              } else {
                Future.delayed(const Duration(milliseconds: 300), routeToCall);
              }
            }
            routeToCall();
            break;

          case CallEventActionCallDecline():
            final params = event.callKitParams;
            final id = params.id;
            if (id.isNotEmpty) {
              final user = FirebaseAuth.instance.currentUser;
              String? name = user?.displayName;
              if (user != null && (name == null || name.isEmpty)) {
                final doc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .get();
                name = doc.data()?['name'];
              }
              await repository.endCallTransaction(
                callId: id,
                status: 'rejected',
                endedBy: user?.uid,
                endedByName: name,
              );
            }
            break;

          case CallEventActionCallEnded():
            final params = event.callKitParams;
            final id = params.id;
            if (id.isNotEmpty) {
              final doc = await FirebaseFirestore.instance
                  .collection('calls')
                  .doc(id)
                  .get();
              if (doc.exists) {
                final status = doc.data()?['status'];
                final user = FirebaseAuth.instance.currentUser;
                String? name = user?.displayName;
                if (user != null && (name == null || name.isEmpty)) {
                  final userDoc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .get();
                  name = userDoc.data()?['name'];
                }

                final targetStatus =
                    (status == 'calling' || status == 'ringing')
                    ? 'rejected'
                    : 'ended';
                await repository.endCallTransaction(
                  callId: id,
                  status: targetStatus,
                  endedBy: user?.uid,
                  endedByName: name,
                );
              }
            }
            break;

          case CallEventActionCallTimeout():
            final id = event.id;
            if (id.isNotEmpty) {
              await repository.endCallTransaction(callId: id, status: 'missed');
            }
            break;
          default:
            break;
        }
      } catch (e) {
        debugPrint("CallKit Event Error: $e");
      }
    });
  }

  static Future<void> _handleForegroundCall(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] == 'cancel') {
      try {
        await FlutterCallkitIncoming.endAllCalls();
        // Also dismiss any call-waiting banner for this canceled call
        CallWaitingBannerController.instance.dismiss();
      } catch (e) {
        debugPrint("Error ending calls on foreground cancel: $e");
      }
      return;
    }

    if (data['type'] == 'chat') {
      final senderId = data['senderId'];
      if (senderId != null &&
          senderId != ChatDetailScreen.currentActiveChatId) {
        await ChatNotificationService.showChatNotification(
          id: senderId,
          title: data['senderName'] ?? 'New Message',
          body: data['content'] ?? 'You have a new message',
          payload: data,
        );
      }
      return;
    }

    final callId = data['id'];
    if (callId == null || _processedCalls.contains(callId)) return;

    // Ghost Ringing Fix: verify call is still live in Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();
      if (doc.exists) {
        final status = doc.data()?['status'] as String?;
        final terminalStatuses = [
          'cancelled',
          'declined',
          'missed',
          'ended',
          'rejected',
          'caller_ended',
        ];
        if (status != null && terminalStatuses.contains(status)) {
          await FlutterCallkitIncoming.endAllCalls();
          return;
        }
      }
    } catch (e) {
      debugPrint("Error checking call status in foreground handler: $e");
    }

    _processedCalls.add(callId);

    try {
      final extraString = data['extra'];
      if (extraString == null) return;
      final extra = jsonDecode(extraString as String);
      final isVideo = extra['isVideo'] == true;
      final agoraChannelId = extra['agoraChannelId'] ?? callId;
      final callerName = data['nameCaller'] ?? 'Incoming Call';
      final callerPic = data['avatar'] ?? '';

      // ── Call-Waiting Intercept ──────────────────────────────────────────
      // If the user is already in an active call, DO NOT push a new screen.
      // Instead show the non-intrusive call-waiting banner + play beep.
      final agoraState = _container?.read(agoraServiceProvider);
      if (agoraState != null && agoraState.isCallActive) {
        // Silently mark as ringing in Firestore so caller side updates
        FirebaseFirestore.instance
            .collection('calls')
            .doc(callId)
            .update({'status': 'ringing'})
            .catchError((_) {});

        // Play subtle waiting beep (low-volume, non-disruptive)
        CallFeedbackService.instance.playCallWaitingBeep();

        // Show the overlay banner — no screen navigation
        CallWaitingBannerController.instance.show(
          callId: callId,
          callerName: callerName,
          callerPic: callerPic,
          agoraChannelId: agoraChannelId,
          isVideo: isVideo,
        );
        return;
      }
      // ── Normal Incoming Call Path ───────────────────────────────────────

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              callId: callId,
              callerName: callerName,
              callerPic: callerPic,
              agoraChannelId: agoraChannelId,
              isVideo: isVideo,
            ),
          ),
        );

        // Silently update status to ringing
        FirebaseFirestore.instance
            .collection('calls')
            .doc(callId)
            .update({'status': 'ringing'})
            .catchError((_) {});
      }
    } catch (e) {
      debugPrint("Error handling foreground call: $e");
    }
  }

  static Future<void> showCallkitIncoming(RemoteMessage message) async {
    final data = message.data;

    if (data['type'] == 'cancel') {
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (e) {
        debugPrint("Error ending calls on showCallkitIncoming cancel: $e");
      }
      return;
    }

    final callId = data['id'] ?? const Uuid().v4();

    // Ghost Ringing Fix: Check Firestore document status before displaying native CallKit UI
    try {
      final callDoc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();
      if (callDoc.exists) {
        final status = callDoc.data()?['status'] as String?;
        final terminalStatuses = [
          'cancelled',
          'declined',
          'missed',
          'ended',
          'rejected',
          'caller_ended',
        ];
        if (status != null && terminalStatuses.contains(status)) {
          await FlutterCallkitIncoming.endAllCalls();
          return;
        }
      }
    } catch (e) {
      debugPrint("Error checking call status before showing CallKit: $e");
    }

    final callerName = data['nameCaller'] ?? 'Unknown';
    final avatar = data['avatar'] ?? '';
    final isVideo = data['type'] == '1';

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'ConnectCall',
      avatar: avatar,
      handle: 'Incoming ${isVideo ? 'Video' : 'Audio'} Call',
      type: 0,
      duration: 30000,
      extra: <String, dynamic>{'extra': data['extra']},
      headers: <String, dynamic>{'apiKey': 'flutter_callkit_incoming'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        // system_ringtone_default → uses device ringtone; fallback: res/raw/ringtone.ogg
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#000000',
        backgroundUrl: '',
        actionColor: '#4CAF50',
        isShowFullLockedScreen: true,
        isImportant: true,
        isFullScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);

    // Silently update status to ringing
    FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .update({'status': 'ringing'})
        .catchError((_) {});
  }
}
