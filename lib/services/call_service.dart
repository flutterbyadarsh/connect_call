import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../main.dart';
import '../screens/call/incoming_call_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CallService {
  static final Set<String> _processedCalls = {};
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    
    await _localNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // We handle navigation via Firestore stream anyway, 
        // so tapping notification just brings app to foreground
      },
    );

    // Handle foreground FCM messages (fallback if firestore stream misses it)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Actually, since we are using Firestore streams for real-time, 
      // we don't strictly need to do anything here for calls in the foreground.
    });
  }

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
                
                // Show standard IncomingCallScreen directly
                if (navigatorKey.currentState != null) {
                  navigatorKey.currentState!.push(MaterialPageRoute(
                    builder: (_) => IncomingCallScreen(
                      callId: callId,
                      callerName: data['callerName'] ?? 'Incoming Call',
                      callerPic: data['callerPic'] ?? '',
                      agoraChannelId: data['agoraChannelId'] ?? callId,
                      isVideo: data['isVideo'] == true,
                    ),
                  ));
                }
              }
            }
            // If call was cancelled or answered elsewhere
            else if (status != 'ringing' && _processedCalls.contains(callId)) {
               // The IncomingCallScreen listens to its own status and will pop itself
            }
          }
        }
      }
    });
  }

  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] != 'cancel') {
      final callerName = data['nameCaller'] ?? 'Incoming Call';
      const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'call_channel', 'Incoming Calls',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
      );
      const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
      
      await _localNotificationsPlugin.show(
        id: 0,
        title: callerName,
        body: 'Incoming Call...',
        notificationDetails: platformChannelSpecifics,
      );
    } else {
      await _localNotificationsPlugin.cancel(id: 0);
    }
  }
}
