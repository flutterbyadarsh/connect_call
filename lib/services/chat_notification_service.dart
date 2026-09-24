import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/chat/chat_detail_screen.dart';
import '../main.dart';
import '../repositories/chat_repository.dart';
import '../firebase_options.dart';
import 'dart:ui';

@pragma('vm:entry-point')
void onNotificationActionBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized(); // CRITICAL for background isolates

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (response.payload == null) return;
  final payload = jsonDecode(response.payload!);

  // The 'senderId' in the payload is the person who sent the original message (our target).
  final targetUserUidFromPayload = payload['senderId'] as String?;

  // Explicitly get local user ID from Auth.
  final localUserUid =
      FirebaseAuth.instance.currentUser?.uid ??
      payload['receiverId'] as String?;

  if (targetUserUidFromPayload == null || localUserUid == null) {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.show(
      id: 777,
      title: 'Debug Error',
      body:
          'Target or Local User ID is null. Target: $targetUserUidFromPayload, Local: $localUserUid',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'debug_channel',
          'Debug',
          importance: Importance.max,
        ),
      ),
    );
    return;
  }

  try {
    final firestore = FirebaseFirestore.instance;
    final repo = ChatRepository(firestore);

    if (response.actionId == 'reply_action') {
      final replyText = response.input;
      if (replyText != null && replyText.isNotEmpty) {
        await repo.sendMessage(
          senderId: localUserUid,
          receiverId: targetUserUidFromPayload,
          content: replyText,
        );
        debugPrint(
          'BG_REPLY_SUCCESS: Reply sent successfully to $targetUserUidFromPayload',
        );

        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        await flutterLocalNotificationsPlugin.show(
          id: 999,
          title: 'Debug Success',
          body:
              'Reply sent to $targetUserUidFromPayload from $localUserUid: $replyText',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'debug_channel',
              'Debug',
              importance: Importance.max,
            ),
          ),
        );
      } else {
        debugPrint('BG_REPLY_ERROR: Reply text is null or empty');
      }
    } else if (response.actionId == 'mark_read_action') {
      await repo.markMessagesAsRead(
        currentUserId: localUserUid,
        otherUserId: targetUserUidFromPayload,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_history_$targetUserUidFromPayload');

      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();
      await flutterLocalNotificationsPlugin.cancel(
        id: targetUserUidFromPayload.hashCode,
      );
    }
  } catch (e) {
    debugPrint('BG_REPLY_ERROR: $e');
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.show(
      id: 888,
      title: 'Debug Exception',
      body: e.toString(),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'debug_channel',
          'Debug',
          importance: Importance.max,
        ),
      ),
    );
  }
}

class ChatNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse:
          onNotificationActionBackground,
    );
  }

  static Future<String?> _downloadAndSavePicture(
    String? url,
    String fileName,
  ) async {
    if (url == null || url.isEmpty) return null;
    try {
      final Directory directory = await getApplicationDocumentsDirectory();
      final String filePath = '${directory.path}/$fileName';
      final File file = File(filePath);
      if (await file.exists()) {
        return filePath;
      }
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(Uri.parse(url));
      final HttpClientResponse response = await request.close();
      if (response.statusCode == 200) {
        final List<int> bytes = await consolidateHttpClientResponseBytes(
          response,
        );
        await file.writeAsBytes(bytes);
        return filePath;
      }
    } catch (e) {
      debugPrint('Error downloading image: $e');
    }
    return null;
  }

  static Future<void> showChatNotification({
    required String id,
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    final senderId = payload['senderId'] as String? ?? id;
    final senderName = payload['senderName'] as String? ?? title;
    final senderPic = payload['senderPic'] as String?;
    final timestamp = payload['timestamp'] != null
        ? DateTime.parse(payload['timestamp']).millisecondsSinceEpoch
        : DateTime.now().millisecondsSinceEpoch;

    final messageId = payload['messageId'] as String?;
    if (messageId != null) {
      try {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null) {
          final uid1 = currentUserId;
          final uid2 = senderId;
          final chatRoomId = uid1.compareTo(uid2) > 0
              ? '${uid1}_$uid2'
              : '${uid2}_$uid1';

          await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatRoomId)
              .collection('messages')
              .doc(messageId)
              .update({'message_status': 'delivered'});
        }
      } catch (e) {
        debugPrint("Error updating delivered status: $e");
      }
    }

    // Load existing history
    final prefs = await SharedPreferences.getInstance();
    final historyKey = 'chat_history_$senderId';
    List<String> history = prefs.getStringList(historyKey) ?? [];

    // Add new message
    history.add(jsonEncode({'text': body, 'timestamp': timestamp}));
    await prefs.setStringList(historyKey, history);

    // Download avatar if available
    String? localAvatarPath = await _downloadAndSavePicture(
      senderPic,
      'avatar_$senderId.png',
    );

    final Person sender = Person(
      name: senderName,
      key: senderId,
      icon: localAvatarPath != null
          ? BitmapFilePathAndroidIcon(localAvatarPath)
          : null,
    );

    final Person me = Person(name: 'Me', key: 'me');

    final List<Message> messages = history.map((jsonStr) {
      final map = jsonDecode(jsonStr);
      return Message(
        map['text'],
        DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
        sender,
      );
    }).toList();

    final MessagingStyleInformation messagingStyle = MessagingStyleInformation(
      me,
      groupConversation: false,
      messages: messages,
    );

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'chat_messages',
          'Chat Messages',
          channelDescription: 'Notifications for incoming chat messages',
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: messagingStyle,
          color: Colors.blue,
          category: AndroidNotificationCategory.message,
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'reply_action',
              'Reply',
              icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
              inputs: <AndroidNotificationActionInput>[
                AndroidNotificationActionInput(label: 'Type a message...'),
              ],
            ),
            const AndroidNotificationAction(
              'mark_read_action',
              'Mark as read',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'mute_action',
              'Mute',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      id: senderId.hashCode,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: jsonEncode(payload),
    );
  }

  static void _onNotificationTapped(NotificationResponse response) async {
    if (response.payload != null) {
      final payload = jsonDecode(response.payload!);

      final senderId = payload['senderId'];
      final senderName = payload['senderName'];

      // Clear history when tapped to open
      if (senderId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('chat_history_$senderId');
      }

      if (senderId != null && navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              contactId: senderId,
              contactName: senderName ?? 'Contact',
            ),
          ),
        );
      }
    }
  }
}
