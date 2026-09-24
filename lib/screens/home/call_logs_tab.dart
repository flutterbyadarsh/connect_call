import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils/error_handler.dart';
import '../../services/auth_service.dart';
import '../../services/call_feedback_service.dart';
import '../../widgets/call_toast.dart';
import '../../widgets/shimmer_list_widget.dart';
import '../../widgets/empty_state_widget.dart';
import '../../providers/call_providers.dart';
import '../../providers/selection_providers.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/profile_image.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';
import '../chat/contact_profile_screen.dart';

class CallLogsTab extends ConsumerWidget {
  const CallLogsTab({super.key});

  void _deleteSelectedLogs(
    BuildContext context,
    WidgetRef ref,
    String currentUserId,
  ) async {
    final selectionState = ref.read(callSelectionProvider);
    if (selectionState.selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Call Logs'),
        content: Text(
          'Are you sure you want to delete ${selectionState.selectedIds.length} selected logs?',
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
      ref
          .read(callRepositoryProvider)
          .deleteCallLogs(currentUserId, selectionState.selectedIds.toList());
      ref.read(callSelectionProvider.notifier).disableSelectionMode();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    final callLogsAsyncValue = ref.watch(callLogsStreamProvider);
    final isSelecting = ref.watch(
      callSelectionProvider.select((s) => s.isSelecting),
    );
    final selectedCount = ref.watch(
      callSelectionProvider.select((s) => s.selectedIds.length),
    );

    return Scaffold(
      appBar: isSelecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => ref
                    .read(callSelectionProvider.notifier)
                    .disableSelectionMode(),
              ),
              title: Text('$selectedCount selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select All / Unselect All',
                  onPressed: () {
                    if (callLogsAsyncValue.value != null) {
                      final allIds = callLogsAsyncValue.value!
                          .map((d) => d.id)
                          .toList();
                      ref
                          .read(callSelectionProvider.notifier)
                          .toggleSelectAll(allIds);
                    }
                  },
                ),
                if (selectedCount > 0)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () =>
                        _deleteSelectedLogs(context, ref, user.uid),
                  ),
              ],
            )
          : null,
      body: callLogsAsyncValue.when(
        data: (docs) {
          if (docs.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.history,
              title: 'No Call Logs Yet',
              subtitle:
                  'When you make or receive calls, they will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: docs.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return CallLogTile(
                doc: docs[index],
                currentUserId: user.uid,
                currentUserName: user.name,
                currentUserPic: user.profileImageUrl,
              );
            },
          );
        },
        loading: () => const ShimmerListWidget(),
        error: (error, stack) => Center(
          child: Text(
            ErrorHandler.getUserFriendlyMessage(error),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }
}

class CallLogTile extends ConsumerStatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String currentUserId;
  final String currentUserName;
  final String currentUserPic;

  const CallLogTile({
    super.key,
    required this.doc,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserPic,
  });

  @override
  ConsumerState<CallLogTile> createState() => _CallLogTileState();
}

class _CallLogTileState extends ConsumerState<CallLogTile> {
  bool _isStartingCall = false;

  @override
  Widget build(BuildContext context) {
    final isSelecting = ref.watch(
      callSelectionProvider.select((s) => s.isSelecting),
    );
    final isSelected = ref.watch(
      callSelectionProvider.select(
        (s) => s.selectedIds.contains(widget.doc.id),
      ),
    );
    final logId = widget.doc.id;

    final data = widget.doc.data();
    final isOutgoing = data['callerId'] == widget.currentUserId;
    final isVideo = data['isVideo'] == true;

    final otherName = isOutgoing
        ? (data['receiverName'] ?? 'Unknown')
        : (data['callerName'] ?? 'Unknown');
    final otherPic = isOutgoing
        ? (data['receiverPic'] ?? '')
        : (data['callerPic'] ?? '');
    final otherId = isOutgoing ? data['receiverId'] : data['callerId'];

    final smartNameAsync = ref.watch(smartNameProvider(otherId));

    final timestamp = data['timestamp'] as Timestamp?;
    final dt =
        timestamp?.toDate() ??
        (data['createdAt'] != null
            ? DateTime.tryParse(data['createdAt'])
            : null);

    final dateStr = dt != null
        ? DateFormat('MMM d, h:mm a').format(dt)
        : 'Just now';

    final status = data['status'] as String?;
    final duration = data['duration'] as int? ?? 0;

    final isMissed =
        status == 'missed' ||
        (!isOutgoing && status == 'ended' && duration == 0);

    String durationStr = '';
    if (duration > 0) {
      final mins = duration ~/ 60;
      final secs = duration % 60;
      durationStr = mins > 0 ? ' • $mins m $secs s' : ' • $secs s';
    } else if (isMissed) {
      durationStr = ' • Missed';
    } else {
      durationStr = ' • 0 s';
    }

    final iconColor = isMissed
        ? Colors.red
        : (isOutgoing ? Colors.green : Colors.blue);

    return Dismissible(
      key: Key(logId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text("Delete Call Log"),
              content: const Text(
                "Are you sure you want to delete this call log?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    "Delete",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) {
        HapticFeedback.heavyImpact();
        ref.read(callRepositoryProvider).deleteCallLogs(widget.currentUserId, [
          logId,
        ]);
      },
      child: Card(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            selected: isSelected,
            selectedTileColor: Theme.of(
              context,
            ).primaryColor.withValues(alpha: 0.1),
            onLongPress: () {
              HapticFeedback.lightImpact();
              if (!ref.read(callSelectionProvider).isSelecting) {
                ref.read(callSelectionProvider.notifier).toggleSelectionMode();
              }
              ref.read(callSelectionProvider.notifier).toggleSelection(logId);
            },
            onTap: () {
              HapticFeedback.lightImpact();
              if (isSelecting) {
                ref.read(callSelectionProvider.notifier).toggleSelection(logId);
              } else {
                if (_isStartingCall) return;
                setState(() => _isStartingCall = true);

                final channelId = const Uuid().v4();
                ref
                    .read(callRepositoryProvider)
                    .initiateCall(
                      receiverId: otherId,
                      channelId: channelId,
                      callerName: widget.currentUserName,
                      callerPic: widget.currentUserPic,
                      isVideo: isVideo,
                    )
                    .then((call) {
                      if (!context.mounted) return;
                      setState(() => _isStartingCall = false);

                      if (isVideo) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoCallScreen(
                              callerName: call.id,
                              agoraChannelId: channelId,
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AudioCallScreen(
                              callerName: call.id,
                              agoraChannelId: channelId,
                            ),
                          ),
                        );
                      }
                    })
                    .catchError((e) {
                      if (!context.mounted) return;
                      setState(() => _isStartingCall = false);
                      final errStr = e.toString();
                      if (errStr.contains('user_busy')) {
                        // Tactile + audio busy feedback
                        HapticFeedback.heavyImpact();
                        CallFeedbackService.instance.playBusyTone();
                        CallToast.show(
                          message: '$otherName is busy on another call',
                          type: CallToastType.busy,
                        );
                      } else {
                        CallToast.show(
                          message: 'Could not start call. Please try again.',
                          type: CallToastType.info,
                        );
                      }
                    });
              }
            },
            leading: SizedBox(
              width: isSelecting ? 96 : 52,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelecting)
                    Checkbox(
                      value: isSelected,
                      onChanged: (val) {
                        ref
                            .read(callSelectionProvider.notifier)
                            .toggleSelection(logId);
                      },
                    ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ContactProfileScreen(
                            targetUserId: otherId,
                            fallbackName: otherName,
                            profileImageUrl: otherPic,
                          ),
                        ),
                      );
                    },
                    child: ProfileImage(
                      imageUrl: otherPic,
                      radius: 26,
                      fallbackWidget: CircleAvatar(
                        radius: 26,
                        backgroundColor: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.1),
                        child: Text(
                          otherName.isNotEmpty
                              ? otherName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            title: smartNameAsync.when(
              data: (name) => Text(
                name == 'Unknown' ? otherName : name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              loading: () => Text(
                otherName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              error: (_, __) => Text(
                otherName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Icon(
                    isMissed
                        ? Icons.call_missed
                        : (isOutgoing ? Icons.call_made : Icons.call_received),
                    size: 16,
                    color: iconColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$dateStr$durationStr',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                isVideo ? Icons.videocam : Icons.call,
                color: isVideo ? Colors.blue : Colors.green,
              ),
              onPressed: () {
                if (_isStartingCall) return;
                setState(() => _isStartingCall = true);

                final channelId = const Uuid().v4();
                ref
                    .read(callRepositoryProvider)
                    .initiateCall(
                      receiverId: otherId,
                      channelId: channelId,
                      callerName: widget.currentUserName,
                      callerPic: widget.currentUserPic,
                      isVideo: isVideo,
                    )
                    .then((call) {
                      if (!context.mounted) return;
                      setState(() => _isStartingCall = false);

                      if (isVideo) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoCallScreen(
                              callerName: call.id,
                              agoraChannelId: channelId,
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AudioCallScreen(
                              callerName: call.id,
                              agoraChannelId: channelId,
                            ),
                          ),
                        );
                      }
                    })
                    .catchError((e) {
                      if (!context.mounted) return;
                      setState(() => _isStartingCall = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to start call: $e')),
                      );
                    });
              },
            ),
          ),
        ),
      ),
    );
  }
}
