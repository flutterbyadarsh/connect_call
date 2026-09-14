import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';
import '../../widgets/user_tile.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';

class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key});

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  String _searchQuery = '';

  Future<void> _startCall(BuildContext context, UserModel receiver, bool isVideo) async {
    final caller = ref.read(authServiceProvider).currentUser;
    if (caller == null) return;
    
    // Check if the receiver is online
    if (!receiver.isOnline) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User is offline and cannot be called right now.')));
      }
      return;
    }

    // Check for internet connection
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Internet connection is unavailable.')));
      }
      return;
    }
    
    final callId = const Uuid().v4(); // Generate a unique channel ID

    // Create a call document to trigger the Cloud Function
    await FirebaseFirestore.instance.collection('calls').doc(callId).set({
      'callerId': caller.uid,
      'callerName': caller.name,
      'callerPic': caller.profileImageUrl,
      'receiverId': receiver.uid,
      'receiverName': receiver.name,
      'receiverPic': receiver.profileImageUrl,
      'isVideo': isVideo,
      'status': 'ringing',
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;

    if (isVideo) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoCallScreen(callerName: callId)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AudioCallScreen(callerName: callId)));
    }
  }

  void _startAudioCall(BuildContext context, UserModel receiver) => _startCall(context, receiver, false);
  void _startVideoCall(BuildContext context, UserModel receiver) => _startCall(context, receiver, true);

  void _showAddContactSheet(BuildContext context) {
    final phoneCtrl = TextEditingController();
    String? errorMsg;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              top: 24,
              left: 24,
              right: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Add New Contact', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  autofocus: true, 
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Enter Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(ctx).colorScheme.surface,
                    errorText: errorMsg,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: Theme.of(ctx).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    setState(() => errorMsg = null);
                    final phone = phoneCtrl.text.trim();
                    if (phone.isEmpty) {
                      setState(() => errorMsg = 'Please enter a phone number');
                      return;
                    }
                    
                    final phoneRegex = RegExp(r'^\d{10}$');
                    if (!phoneRegex.hasMatch(phone)) {
                      setState(() => errorMsg = 'Please enter a valid 10-digit phone number');
                      return;
                    }

                    final currentUser = ref.read(authServiceProvider).currentUser;
                    if (currentUser != null && currentUser.phoneNumber == phone) {
                      setState(() => errorMsg = 'You cannot add your own number');
                      return;
                    }
                    
                    Navigator.pop(ctx);
                    final success = await ref.read(userServiceProvider).addContactByPhone(phone);
                    
                    if (!mounted) return;
                    if (!success) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not found or already added')));
                    }
                  },
                  child: const Text('Add Contact', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userService = ref.watch(userServiceProvider);
    
    final filteredUsers = userService.users.where((u) {
      return u.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
             u.phoneNumber.contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddContactSheet(context),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                ),
              ),
            ),
          ),
          if (userService.isLoading) 
            const LinearProgressIndicator(),
          Expanded(
            child: filteredUsers.isEmpty
                ? Center(
                    child: Text(
                      "No contacts found. Click '+' to add.",
                      style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
                    )
                  )
                : ListView.separated(
                    itemCount: filteredUsers.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      return Dismissible(
                        key: Key(user.uid),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          userService.deleteContact(user.uid);
                        },
                        child: UserTile(
                          user: user,
                          // Passing UID as channel name for Agora to connect
                          onAudioCall: () => _startAudioCall(context, user),
                          onVideoCall: () => _startVideoCall(context, user),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
