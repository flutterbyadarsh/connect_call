import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/call_service.dart';
import '../../services/theme_service.dart';
import 'contacts_tab.dart';
import 'call_logs_tab.dart';
import 'profile_screen.dart';

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
    CallService.startListeningForCalls();
    
    // Failsafe: Reset busy state when returning to Home
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = ref.read(authServiceProvider).currentUser;
      if (currentUser != null) {
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'isBusy': false})
            .catchError((_) {});
      }
    });
  }

  final List<Widget> _tabs = [
    const ContactsTab(),
    const CallLogsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final themeService = ref.watch(themeServiceProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.account_circle),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
            );
          },
        ),
        title: Text(_currentIndex == 0 ? 'Contacts' : 'Call Logs'),
        actions: [
          IconButton(
            icon: Icon(themeService.isDarkMode ? CupertinoIcons.sun_max : CupertinoIcons.moon),
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.contacts), label: 'Contacts'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Call Logs'),
        ],
      ),
    );
  }
}
