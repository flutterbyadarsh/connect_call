import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/call_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/profile_setup_screen.dart';
import 'screens/home/home_screen.dart';
import 'firebase_options.dart';

import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'screens/call/video_call_screen.dart';
import 'screens/call/audio_call_screen.dart';
import 'screens/chat/chat_detail_screen.dart';
import 'services/chat_notification_service.dart';
import 'widgets/active_call_banner.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");

  if (message.data.isNotEmpty) {
    // Process concurrently without blocking the isolate
    Future.microtask(() async {
      try {
        if (message.data['type'] == 'cancel') {
          await FlutterCallkitIncoming.endAllCalls();
        } else if (message.data['type'] == 'chat') {
          await ChatNotificationService.showChatNotification(
            id: message.data['senderId'] ?? 'chat',
            title: message.data['senderName'] ?? 'New Message',
            body: message.data['content'] ?? 'You have a new message',
            payload: message.data,
          );
        } else {
          await CallService.showCallkitIncoming(message);
        }
      } catch (e) {
        debugPrint("Error handling background message: $e");
      }
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize Chat Notifications
    await ChatNotificationService.init();

    await CallService.init();

    // Check if app was launched from a CallKit accept
    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls.isNotEmpty) {
      // The CallKit event listener inside CallService.init() will handle routing
      // when it receives the ACTION_CALL_ACCEPT event on startup.
    }
  } catch (e) {
    debugPrint("Firebase not initialized: $e");
  }

  runApp(const ProviderScope(child: ConnectCallApp()));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class ConnectCallApp extends ConsumerStatefulWidget {
  const ConnectCallApp({super.key});

  @override
  ConsumerState<ConnectCallApp> createState() => _ConnectCallAppState();
}

class _ConnectCallAppState extends ConsumerState<ConnectCallApp>
    with WidgetsBindingObserver {
  Timer? _offlineTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Inject the Riverpod container into CallService for smart notification routing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallService.setContainer(ProviderScope.containerOf(context));
    });
    _checkInitialCallRouting();
    _updatePresence(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineTimer?.cancel();
    super.dispose();
  }

  void _updatePresence(bool isOnline) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'isOnline': isOnline,
              'lastSeen': isOnline ? null : FieldValue.serverTimestamp(),
            });
      } catch (e) {
        debugPrint("Error updating presence: $e");
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _offlineTimer?.cancel();
      _updatePresence(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _offlineTimer?.cancel();
      _offlineTimer = Timer(const Duration(seconds: 15), () {
        _updatePresence(false);
      });
    } else if (state == AppLifecycleState.detached) {
      _offlineTimer?.cancel();
      _updatePresence(false);
    }
  }

  Future<void> _checkInitialCallRouting() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        if (activeCalls.isNotEmpty) {
          final call = activeCalls.first;
          final extraMap = call.extra;
          if (extraMap != null) {
            final extraString = extraMap['extra'] as String?;
            if (extraString != null) {
              final extra = jsonDecode(extraString);
              final agoraChannelId = extra['agoraChannelId'];
              final isVideo = extra['isVideo'] == true;
              final id = call.id;

              if (agoraChannelId != null) {
                // We know there's an active call from cold start
                navigatorKey.currentState?.pushReplacement(
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
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Error routing cold start call: $e");
      }
    });

    // Handle chat notification taps when app is terminated
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null && initialMessage.data['type'] == 'chat') {
      _routeToChatDetail(initialMessage.data);
    }

    // Handle chat notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['type'] == 'chat') {
        _routeToChatDetail(message.data);
      }
    });
  }

  void _routeToChatDetail(Map<String, dynamic> data) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final senderId = data['senderId'];
      final senderName = data['senderName'];
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeService = ref.watch(themeServiceProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ConnectCall',
      themeMode: themeService.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          children: [
            if (child case final Widget w) w,
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ActiveCallBanner(),
            ),
          ],
        );
      },
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = ref.watch(authServiceProvider);

    if (authService.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (authService.currentUser != null) {
      if (authService.currentUser!.name.isEmpty ||
          authService.currentUser!.name == 'User') {
        return const ProfileSetupScreen();
      }
      return const HomeScreen();
    }

    return const LoginScreen();
  }
}
