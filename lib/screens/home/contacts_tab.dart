import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';
import '../../widgets/user_tile.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'dart:convert';

class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key});

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  String _searchQuery = '';
  bool _isStartingCall = false;

  Future<void> _startCall(BuildContext context, UserModel receiver, bool isVideo) async {
    if (_isStartingCall) return;
    setState(() => _isStartingCall = true);
    
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
    final callId = const Uuid().v4(); // Unique document ID for Firestore
    
    // Generate a deterministic channel ID for Agora based on sorted UIDs
    final agoraChannelId = caller.uid.compareTo(receiver.uid) < 0 
        ? '${caller.uid}_${receiver.uid}' 
        : '${receiver.uid}_${caller.uid}';

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final receiverRef = FirebaseFirestore.instance.collection('users').doc(receiver.uid);
        final callerRef = FirebaseFirestore.instance.collection('users').doc(caller.uid);
        
        final receiverSnapshot = await transaction.get(receiverRef);
        
        if (!receiverSnapshot.exists) {
          throw Exception("Receiver not found");
        }
        
        if (receiverSnapshot.data()?['isBusy'] == true) {
          throw Exception("busy");
        }
        
        // Mark both users as busy
        transaction.update(receiverRef, {'isBusy': true});
        transaction.update(callerRef, {'isBusy': true});
        
        // Create the call document
        final callRef = FirebaseFirestore.instance.collection('calls').doc(callId);
        transaction.set(callRef, {
          'callerId': caller.uid,
          'callerName': caller.name,
          'callerPic': caller.profileImageUrl,
          'receiverId': receiver.uid,
          'receiverName': receiver.name,
          'receiverPic': receiver.profileImageUrl,
          'agoraChannelId': agoraChannelId, // Store the deterministic ID
          'isVideo': isVideo,
          'status': 'ringing',
          'timestamp': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      if (context.mounted) {
        if (e.toString().contains("busy")) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User is busy on another call.')));
          // Optionally add a missed call log here
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
        }
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isStartingCall = false;
        });
      }
    }

    if (!context.mounted) return;

    if (isVideo) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoCallScreen(callerName: callId, agoraChannelId: agoraChannelId)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AudioCallScreen(callerName: callId, agoraChannelId: agoraChannelId)));
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
      builder: (ctx) {
        String completePhoneNumber = '';
        return StatefulBuilder(
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
                IntlPhoneField(
                  autofocus: true, 
                  decoration: InputDecoration(
                    hintText: 'Enter Phone Number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(ctx).colorScheme.surface,
                    errorText: errorMsg,
                  ),
                  initialCountryCode: 'IN',
                  onChanged: (phone) {
                    completePhoneNumber = phone.completeNumber;
                  },
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
                    final phone = completePhoneNumber;
                    if (phone.isEmpty) {
                      setState(() => errorMsg = 'Please enter a phone number');
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
        },
      );
      },
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
          if (filteredUsers.any((u) => u.isOnline))
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: filteredUsers.where((u) => u.isOnline).map((user) {
                  return GestureDetector(
                    onTap: () => _startVideoCall(context, user),
                    child: Container(
                      width: 72,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                backgroundImage: user.profileImageUrl.isNotEmpty 
                                    ? MemoryImage(base64Decode(user.profileImageUrl.split(',').last)) 
                                    : null,
                                child: user.profileImageUrl.isEmpty 
                                    ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 20))
                                    : null,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.name,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
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
                      return Slidable(
                        key: Key(user.uid),
                        startActionPane: ActionPane(
                          motion: const ScrollMotion(),
                          children: [
                            SlidableAction(
                              onPressed: (context) => _startAudioCall(context, user),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              icon: Icons.call,
                              label: 'Call',
                            ),
                            SlidableAction(
                              onPressed: (context) => _startVideoCall(context, user),
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              icon: Icons.videocam,
                              label: 'Video',
                            ),
                          ],
                        ),
                        endActionPane: ActionPane(
                          motion: const ScrollMotion(),
                          children: [
                            SlidableAction(
                              onPressed: (context) => userService.deleteContact(user.uid),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              icon: Icons.delete,
                              label: 'Delete',
                            ),
                          ],
                        ),
                        child: UserTile(
                          user: user,
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
