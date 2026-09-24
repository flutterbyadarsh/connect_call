import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../providers/chat_providers.dart';

class MessageBubble extends ConsumerStatefulWidget {
  final MessageModel message;
  final bool isMe;

  const MessageBubble({super.key, required this.message, required this.isMe});

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  final List<String> _emojis = ['❤️', '😂', '😮', '😢', '🙏', '👍'];

  void _showReactionOverlay() {
    debugPrint("Long press triggered on message: ${widget.message.id}");
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hideReactionOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, -50),
              targetAnchor: widget.isMe
                  ? Alignment.topLeft
                  : Alignment.topRight,
              followerAnchor: widget.isMe
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _emojis.map((emoji) {
                      return GestureDetector(
                        onTap: () {
                          _addReaction(emoji);
                          _hideReactionOverlay();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideReactionOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete for me',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessageForMe();
                },
              ),
              if (widget.isMe)
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    'Delete for everyone',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteMessageForEveryone();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _deleteMessageForMe() {
    final repo = ref.read(chatRepositoryProvider);
    final currentUserId = widget.isMe
        ? widget.message.senderId
        : widget.message.receiverId;
    final otherUserId = widget.isMe
        ? widget.message.receiverId
        : widget.message.senderId;
    repo.deleteMessageForMe(
      messageId: widget.message.id,
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    );
  }

  void _deleteMessageForEveryone() {
    final repo = ref.read(chatRepositoryProvider);
    final currentUserId = widget.message.senderId;
    final otherUserId = widget.message.receiverId;
    repo.deleteMessageForEveryone(
      messageId: widget.message.id,
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    );
  }

  void _addReaction(String emoji) {
    final repo = ref.read(chatRepositoryProvider);
    final currentUserId = widget.isMe
        ? widget.message.senderId
        : widget.message.receiverId;
    final otherUserId = widget.isMe
        ? widget.message.receiverId
        : widget.message.senderId;

    repo.addReaction(
      messageId: widget.message.id,
      currentUserId: currentUserId,
      otherUserId: otherUserId,
      emoji: emoji,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasReactions =
        widget.message.reactions != null &&
        widget.message.reactions!.isNotEmpty;

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            _showReactionOverlay();
            _showMessageOptions(context);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: widget.isMe
                      ? Theme.of(context).primaryColor
                      : Colors.grey[300],
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: widget.isMe
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: widget.isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        widget.message.content,
                        style: TextStyle(
                          color: widget.isMe ? Colors.white : Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.isMe)
                      Icon(
                        widget.message.messageStatus == 'read'
                            ? Icons.done_all
                            : (widget.message.messageStatus == 'delivered'
                                  ? Icons.done_all
                                  : Icons.check),
                        size: 16,
                        color: widget.message.messageStatus == 'read'
                            ? Colors.red
                            : Colors.grey[400],
                      ),
                  ],
                ),
              ),
              if (hasReactions)
                Positioned(
                  bottom: -4,
                  right: widget.isMe ? 12 : null,
                  left: widget.isMe ? null : 12,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.message.reactions!.values.toSet().map((
                        emoji,
                      ) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
