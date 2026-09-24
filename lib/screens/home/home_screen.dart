import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';

import '../../services/theme_service.dart';
import '../../widgets/profile_image.dart';
import '../../providers/chat_providers.dart';
import '../../providers/call_providers.dart';
import 'contacts_tab.dart';
import 'call_logs_tab.dart';
import 'profile_screen.dart';
import '../chat/chat_home_screen.dart';

import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    // Request "Display over other apps" permission so CallKit can launch app from background
    Permission.systemAlertWindow.request();

    // Failsafe: Reset busy state when returning to Home
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = ref.read(authServiceProvider).currentUser;
      if (currentUser != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({'isBusy': false})
            .catchError((_) {});
      }
    });
  }

  final List<Widget> _tabs = [
    const ChatHomeScreen(),
    const ContactsTab(),
    const CallLogsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final themeService = ref.watch(themeServiceProvider);
    final user = ref.watch(authServiceProvider).currentUser;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: ProfileImage(
            imageUrl: user?.profileImageUrl ?? '',
            radius: 16,
            fallbackWidget: const Icon(
              Icons.account_circle,
              semanticLabel: 'User Profile',
            ),
          ),
          tooltip: 'Open Profile',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
            );
          },
        ),
        title: Text(
          _currentIndex == 0
              ? 'Chats'
              : _currentIndex == 1
              ? 'Contacts'
              : 'Call Logs',
        ),
        actions: [
          if (_currentIndex != 1)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: _currentIndex == 0
                  ? 'Delete All Chats'
                  : 'Clear All Call Logs',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(
                      _currentIndex == 0
                          ? "Delete All Chats"
                          : "Clear All Call Logs",
                    ),
                    content: Text(
                      _currentIndex == 0
                          ? "Are you sure you want to completely delete all chat histories? This will remove them from your chats list. This cannot be undone."
                          : "Are you sure you want to delete all call logs? This cannot be undone.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text("Cancel"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(
                          _currentIndex == 0 ? "Delete" : "Clear",
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );

                if (confirm == true && user != null) {
                  if (_currentIndex == 0) {
                    ref.read(chatRepositoryProvider).deleteAllChats(user.uid);
                  } else if (_currentIndex == 2) {
                    ref.read(callRepositoryProvider).clearAllCallLogs(user.uid);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _currentIndex == 0
                              ? "All chats deleted."
                              : "All call logs cleared.",
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          IconButton(
            icon: Icon(
              themeService.isDarkMode
                  ? CupertinoIcons.sun_max
                  : CupertinoIcons.moon,
              semanticLabel: 'Toggle Theme',
            ),
            tooltip: 'Toggle Theme',
            onPressed: () => themeService.toggleTheme(),
          ),
        ],
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Theme.of(context).textTheme.bodyMedium?.color,
        elevation: 10,
        items: [
          BottomNavigationBarItem(
            icon: Consumer(
              builder: (context, ref, child) {
                final unreadCount = ref.watch(totalUnreadCountProvider);
                if (unreadCount > 0) {
                  return Badge(
                    label: Text(unreadCount.toString()),
                    child: const Icon(Icons.chat),
                  );
                }
                return const Icon(Icons.chat);
              },
            ),
            label: 'Chats',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.contacts),
            label: 'Contacts',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Call Logs',
          ),
        ],
      ),
    );
  }
}
