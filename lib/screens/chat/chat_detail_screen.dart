import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/profile_image.dart';
import 'package:intl/intl.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/message_bubble.dart';
import 'contact_profile_screen.dart';
import '../../services/user_service.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  static String? currentActiveChatId;

  final String contactId;
  final String contactName;
  final String? contactPic;

  const ChatDetailScreen({
    super.key,
    required this.contactId,
    required this.contactName,
    this.contactPic,
  });

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    ChatDetailScreen.currentActiveChatId = widget.contactId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        ref
            .read(chatRepositoryProvider)
            .resetUnreadCount(
              currentUserId: currentUserId,
              otherUserId: widget.contactId,
            );
        ref
            .read(chatRepositoryProvider)
            .markMessagesAsRead(
              currentUserId: currentUserId,
              otherUserId: widget.contactId,
            );
      }
    });
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    setState(() => _isSending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            senderId: currentUserId,
            receiverId: widget.contactId,
            content: text,
          );
      _messageController.clear();
      // Optionally scroll to bottom (though reversed list handles it mostly)
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    ChatDetailScreen.currentActiveChatId = null;
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Actively and continuously mark incoming messages as read while this screen is open
    ref.listen(chatMessagesProvider(widget.contactId), (previous, next) {
      if (next.hasValue && next.value != null) {
        final messages = next.value!;
        // Check if there are any unread messages from the other user
        final hasUnread = messages.any(
          (msg) => msg.senderId != currentUserId && msg.messageStatus != 'read',
        );

        if (hasUnread) {
          ref
              .read(chatRepositoryProvider)
              .markMessagesAsRead(
                currentUserId: currentUserId,
                otherUserId: widget.contactId,
              );
        }
      }
    });

    final messagesAsync = ref.watch(chatMessagesProvider(widget.contactId));
    final activeChatsAsync = ref.watch(activeChatsProvider);
    DateTime? clearedAt;
    if (activeChatsAsync.hasValue && activeChatsAsync.value != null) {
      try {
        final chatContact = activeChatsAsync.value!.firstWhere(
          (c) => c.contactId == widget.contactId,
        );
        clearedAt = chatContact.clearedAt;
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(
        title: Consumer(
          builder: (context, ref, child) {
            final smartNameAsync = ref.watch(
              smartNameProvider(widget.contactId),
            );
            final presenceAsync = ref.watch(
              userPresenceProvider(widget.contactId),
            );

            final displayName = smartNameAsync.maybeWhen(
              data: (name) => name == 'Unknown' ? widget.contactName : name,
              orElse: () => widget.contactName,
            );

            final isOnline = presenceAsync.valueOrNull?.isOnline ?? false;

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContactProfileScreen(
                      targetUserId: widget.contactId,
                      fallbackName: widget.contactName,
                      profileImageUrl: widget.contactPic ?? '',
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  ProfileImage(imageUrl: widget.contactPic ?? '', radius: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: isOnline ? Colors.green : Colors.grey[400],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear_chat') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear Chat'),
                    content: const Text(
                      'Are you sure you want to clear this chat?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref
                      .read(chatRepositoryProvider)
                      .clearChat(
                        currentUserId: currentUserId,
                        otherUserId: widget.contactId,
                      );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_chat',
                child: Text('Clear Chat'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (allMessages) {
                final messages = allMessages.where((msg) {
                  if (clearedAt == null) return true;
                  return msg.createdAt.isAfter(clearedAt);
                }).toList();

                if (messages.isEmpty) {
                  return const Center(child: Text('Say hi!'));
                }
                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == currentUserId;

                    bool showDateDivider = false;
                    if (index == messages.length - 1) {
                      showDateDivider = true;
                    } else {
                      final previousMsg =
                          messages[index + 1]; // Temporally older message
                      if (msg.createdAt.year != previousMsg.createdAt.year ||
                          msg.createdAt.month != previousMsg.createdAt.month ||
                          msg.createdAt.day != previousMsg.createdAt.day) {
                        showDateDivider = true;
                      }
                    }

                    Widget bubble = MessageBubble(message: msg, isMe: isMe);

                    if (showDateDivider) {
                      String dateStr;
                      final now = DateTime.now();
                      if (msg.createdAt.year == now.year &&
                          msg.createdAt.month == now.month &&
                          msg.createdAt.day == now.day) {
                        dateStr = 'Today';
                      } else if (msg.createdAt.year == now.year &&
                          msg.createdAt.month == now.month &&
                          msg.createdAt.day == now.day - 1) {
                        dateStr = 'Yesterday';
                      } else {
                        dateStr = DateFormat(
                          'dd MMM yyyy',
                        ).format(msg.createdAt);
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          bubble,
                        ],
                      );
                    }

                    return bubble;
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) =>
                  Center(child: Text('Error loading messages: $e')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                _isSending
                    ? const CircularProgressIndicator()
                    : IconButton(
                        icon: const Icon(Icons.send),
                        color: Theme.of(context).primaryColor,
                        onPressed: _sendMessage,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
