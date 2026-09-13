import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import '../main.dart';
import '../screens/call/audio_call_screen.dart';
import '../screens/call/video_call_screen.dart';

class CallService {
  static void init() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      
      if (event is CallEventActionCallAccept) {
        final params = event.callKitParams;
        final extra = params.extra ?? {};
        final isVideo = extra['isVideo'] == true;
        final callId = extra['callId'] as String? ?? params.id;
        
        debugPrint("CallKit accepted. Joining channel: $callId");
        
        // Mark call as accepted in Firestore so it stops ringing on other devices
        try {
          FirebaseFirestore.instance.collection('calls').doc(callId).update({'status': 'accepted'});
        } catch (e) {
          debugPrint("Failed to update call status: $e");
        }
        
        // Handle navigation even if app is just launching (cold start)
        int retryCount = 0;
        void navigate() {
          if (navigatorKey.currentState != null) {
            if (isVideo) {
              navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => VideoCallScreen(callerName: callId)));
            } else {
              navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => AudioCallScreen(callerName: callId)));
            }
          } else {
            // Retry after a short delay if MaterialApp hasn't mounted yet
            if (retryCount < 20) { // Max 6 seconds wait
              retryCount++;
              Future.delayed(const Duration(milliseconds: 300), navigate);
            } else {
              debugPrint("Navigation failed: navigatorKey is permanently null.");
            }
          }
        }
        
        navigate();
      } else if (event is CallEventActionCallDecline) {
        final params = event.callKitParams;
        final extra = params.extra ?? {};
        final callId = extra['callId'] as String? ?? params.id;
        
        debugPrint("CallKit declined. Call ID: $callId");
        try {
          FirebaseFirestore.instance.collection('calls').doc(callId).update({'status': 'declined'});
        } catch (e) {
          debugPrint("Failed to update call status to declined: $e");
        }
      }
    });

    // Listen for FCM messages while app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Handling a foreground message: ${message.messageId}");
      if (message.data.isNotEmpty) {
        showCallkitIncomingFromFCM(message.data);
      }
    });
  }

  static final Set<String> _processedCalls = {};

  static void startListeningForCalls() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('calls')
        .where('receiverId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null) {
            final callId = change.doc.id;
            final status = data['status'] as String?;
            
            // If call is ringing and we haven't processed it yet
            if (status == 'ringing' && !_processedCalls.contains(callId)) {
              final timestamp = data['timestamp'] as Timestamp?;
              bool shouldRing = false;
              
              if (timestamp != null) {
                // Allow 3 minutes of clock drift/delay max
                final diff = DateTime.now().difference(timestamp.toDate()).abs();
                if (diff.inMinutes < 3) {
                  shouldRing = true;
                }
              } else {
                shouldRing = true;
              }

              if (shouldRing) {
                _processedCalls.add(callId);
                final callData = {
                  'id': callId,
                  'nameCaller': data['callerName'] ?? 'Incoming Call',
                  'type': data['isVideo'] == true ? "1" : "0",
                  'handle': 'Connect Call',
                };
                showCallkitIncomingFromFCM(callData);
              }
            }
            // If call was cancelled or answered elsewhere
            else if (status != 'ringing' && _processedCalls.contains(callId)) {
               FlutterCallkitIncoming.endCall(callId);
            }
          }
        }
      }
    });
  }

  static Future<void> showCallkitIncomingFromFCM(Map<String, dynamic> data) async {
    final isVideo = data['type'] == "1";
    final callerName = data['nameCaller'] ?? 'Incoming Call';
    final callId = data['id'] ?? '';
    
    CallKitParams params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'ConnectCall',
      avatar: 'https://i.pravatar.cc/100',
      handle: data['handle'] ?? 'Connect Call',
      type: isVideo ? 1 : 0,
      duration: 30000,
      extra: <String, dynamic>{'isVideo': isVideo, 'callId': callId},
      headers: <String, dynamic>{'apiKey': 'xxxxxxx'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        backgroundUrl: 'https://i.pravatar.cc/500',
        actionColor: '#4CAF50',
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
  }
}

