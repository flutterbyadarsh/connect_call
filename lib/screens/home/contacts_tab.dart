import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';
import '../../widgets/user_tile.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../providers/call_providers.dart';
import '../../providers/selection_providers.dart';
import '../../widgets/shimmer_list_widget.dart';
import '../../widgets/empty_state_widget.dart';

class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key});

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  String _searchQuery = '';
  bool _isStartingCall = false;

  Future<void> _startCall(
    BuildContext context,
    UserModel receiver,
    bool isVideo,
  ) async {
    if (_isStartingCall) return;
    setState(() => _isStartingCall = true);

    final caller = ref.read(authServiceProvider).currentUser;
    if (caller == null) return;

    // Check if receiver is busy
    if (receiver.isBusy) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User is busy on another call')),
        );
      }
      setState(() => _isStartingCall = false);
      return;
    }

    // Removed offline check to allow background calling
    // Check for internet connection
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Internet connection is unavailable.')),
        );
      }
      return;
    }
    // Generate a deterministic channel ID for Agora based on sorted UIDs
    final agoraChannelId = caller.uid.compareTo(receiver.uid) < 0
        ? '${caller.uid}_${receiver.uid}'
        : '${receiver.uid}_${caller.uid}';

    String newCallId;
    try {
      // Initiate the call in Firestore for real-time signaling
      final newCall = await ref
          .read(callRepositoryProvider)
          .initiateCall(
            receiverId: receiver.uid,
            channelId: agoraChannelId,
            callerName: caller.name,
            callerPic: caller.profileImageUrl,
            isVideo: isVideo,
          );
      newCallId = newCall.id;
    } catch (e) {
      if (context.mounted) {
        if (e.toString().contains("busy")) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User is busy on another call.')),
          );
          // Optionally add a missed call log here
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Call failed: $e')));
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            callerName: newCallId,
            agoraChannelId: agoraChannelId,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudioCallScreen(
            callerName: newCallId,
            agoraChannelId: agoraChannelId,
          ),
        ),
      );
    }
  }

  void _startAudioCall(BuildContext context, UserModel receiver) =>
      _startCall(context, receiver, false);
  void _startVideoCall(BuildContext context, UserModel receiver) =>
      _startCall(context, receiver, true);

  void _showAddContactSheet(BuildContext context) {
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
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
                      const Text(
                        'Add New Contact',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: Theme.of(ctx).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      setState(() => errorMsg = null);
                      final phone = completePhoneNumber;
                      if (phone.isEmpty) {
                        setState(
                          () => errorMsg = 'Please enter a phone number',
                        );
                        return;
                      }

                      final currentUser = ref
                          .read(authServiceProvider)
                          .currentUser;
                      if (currentUser != null &&
                          currentUser.phoneNumber == phone) {
                        setState(
                          () => errorMsg = 'You cannot add your own number',
                        );
                        return;
                      }

                      Navigator.pop(ctx);
                      final success = await ref
                          .read(userServiceProvider)
                          .addContactByPhone(phone);

                      if (!mounted) return;
                      if (!success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('User not found or already added'),
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'Add Contact',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _deleteSelectedContacts(BuildContext context, WidgetRef ref) async {
    final selectionState = ref.read(contactSelectionProvider);
    if (selectionState.selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contacts'),
        content: Text(
          'Are you sure you want to delete ${selectionState.selectedIds.length} selected contacts?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final userService = ref.read(userServiceProvider);
      for (final id in selectionState.selectedIds) {
        userService.deleteContact(id);
      }
      ref.read(contactSelectionProvider.notifier).disableSelectionMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userService = ref.watch(userServiceProvider);

    final filteredUsers = userService.users.where((u) {
      return u.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          u.phoneNumber.contains(_searchQuery);
    }).toList();

    final isSelecting = ref.watch(
      contactSelectionProvider.select((s) => s.isSelecting),
    );
    final selectedCount = ref.watch(
      contactSelectionProvider.select((s) => s.selectedIds.length),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: isSelecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => ref
                    .read(contactSelectionProvider.notifier)
                    .disableSelectionMode(),
              ),
              title: Text('$selectedCount selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select All / Unselect All',
                  onPressed: () {
                    final allIds = filteredUsers.map((u) => u.uid).toList();
                    ref
                        .read(contactSelectionProvider.notifier)
                        .toggleSelectAll(allIds);
                  },
                ),
                if (selectedCount > 0)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteSelectedContacts(context, ref),
                  ),
              ],
            )
          : null,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddContactSheet(context),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        tooltip: 'Add Contact',
        child: const Icon(Icons.person_add, semanticLabel: 'Add Contact Icon'),
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
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
          ),
          if (userService.isLoading && filteredUsers.isEmpty)
            const Expanded(child: ShimmerListWidget())
          else
            Expanded(
              child: filteredUsers.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.people_outline,
                      title: 'No Contacts Found',
                      subtitle: "Click the '+' button to add someone.",
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          child: Text(
                            'My Contacts',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).primaryColor,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: filteredUsers.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              return Slidable(
                                key: Key(user.uid),
                                endActionPane: ActionPane(
                                  motion: const ScrollMotion(),
                                  children: [
                                    SlidableAction(
                                      onPressed: (context) {
                                        HapticFeedback.heavyImpact();
                                        userService.deleteContact(user.uid);
                                      },
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      icon: Icons.delete,
                                      label: 'Delete',
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(16),
                                        bottomRight: Radius.circular(16),
                                      ),
                                    ),
                                  ],
                                ),
                                child: UserTile(
                                  user: user,
                                  isSelecting: isSelecting,
                                  isSelected: ref.watch(
                                    contactSelectionProvider.select(
                                      (s) => s.selectedIds.contains(user.uid),
                                    ),
                                  ),
                                  onToggleSelection: () => ref
                                      .read(contactSelectionProvider.notifier)
                                      .toggleSelection(user.uid),
                                  onAudioCall: () =>
                                      _startAudioCall(context, user),
                                  onVideoCall: () =>
                                      _startVideoCall(context, user),
                                  onLongPress: () {
                                    if (!ref
                                        .read(contactSelectionProvider)
                                        .isSelecting) {
                                      ref
                                          .read(
                                            contactSelectionProvider.notifier,
                                          )
                                          .toggleSelectionMode();
                                    }
                                    ref
                                        .read(contactSelectionProvider.notifier)
                                        .toggleSelection(user.uid);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
