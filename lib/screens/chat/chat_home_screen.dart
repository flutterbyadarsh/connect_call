import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_providers.dart';
import '../../providers/selection_providers.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../widgets/profile_image.dart';
import 'chat_detail_screen.dart';
import 'contacts_screen.dart';
import 'contact_profile_screen.dart';

class ChatHomeScreen extends ConsumerWidget {
  const ChatHomeScreen({super.key});

  void _deleteSelectedChats(
    BuildContext context,
    WidgetRef ref,
    String currentUserId,
  ) async {
    final selectionState = ref.read(chatSelectionProvider);
    if (selectionState.selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chats'),
        content: Text(
          'Are you sure you want to delete ${selectionState.selectedIds.length} conversations?',
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
      final repository = ref.read(chatRepositoryProvider);
      for (final contactId in selectionState.selectedIds) {
        repository.deleteChat(
          currentUserId: currentUserId,
          otherUserId: contactId,
        );
      }
      ref.read(chatSelectionProvider.notifier).disableSelectionMode();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeChatsAsync = ref.watch(activeChatsProvider);
    final isSelecting = ref.watch(
      chatSelectionProvider.select((s) => s.isSelecting),
    );
    final selectedCount = ref.watch(
      chatSelectionProvider.select((s) => s.selectedIds.length),
    );
    final currentUser = ref.watch(authServiceProvider).currentUser;

    return Scaffold(
      appBar: isSelecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => ref
                    .read(chatSelectionProvider.notifier)
                    .disableSelectionMode(),
              ),
              title: Text('$selectedCount selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select All / Unselect All',
                  onPressed: () {
                    if (activeChatsAsync.value != null) {
                      final chats = activeChatsAsync.value!
                          .where((c) => !c.isHidden)
                          .map((c) => c.contactId)
                          .toList();
                      ref
                          .read(chatSelectionProvider.notifier)
                          .toggleSelectAll(chats);
                    }
                  },
                ),
                if (selectedCount > 0 && currentUser != null)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () =>
                        _deleteSelectedChats(context, ref, currentUser.uid),
                  ),
              ],
            )
          : null,
      body: activeChatsAsync.when(
        data: (allChats) {
          final chats = allChats.where((chat) => !chat.isHidden).toList();

          if (chats.isEmpty) {
            return const Center(
              child: Text(
                'No active chats. Tap the chat icon to start a new conversation.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: chats.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final isSelected = ref.watch(
                chatSelectionProvider.select(
                  (s) => s.selectedIds.contains(chat.contactId),
                ),
              );
              return Dismissible(
                key: Key(chat.contactId),
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
                        title: const Text("Delete Chat"),
                        content: const Text(
                          "Are you sure you want to delete this conversation?",
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
                  final currentUserId = ref
                      .read(authServiceProvider)
                      .currentUser
                      ?.uid;
                  if (currentUserId != null) {
                    ref
                        .read(chatRepositoryProvider)
                        .deleteChat(
                          currentUserId: currentUserId,
                          otherUserId: chat.contactId,
                        );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListTile(
                    selected: isSelected,
                    selectedTileColor: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.1),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelecting)
                          Checkbox(
                            value: isSelected,
                            onChanged: (val) {
                              ref
                                  .read(chatSelectionProvider.notifier)
                                  .toggleSelection(chat.contactId);
                            },
                          ),
                        Consumer(
                          builder: (context, ref, _) {
                            final presenceAsync = ref.watch(
                              userPresenceProvider(chat.contactId),
                            );
                            final isOnline =
                                presenceAsync.valueOrNull?.isOnline ?? false;
                            return Stack(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ContactProfileScreen(
                                          targetUserId: chat.contactId,
                                          fallbackName: chat.name,
                                          profileImageUrl:
                                              chat.profileImageUrl ?? '',
                                        ),
                                      ),
                                    );
                                  },
                                  child: ProfileImage(
                                    imageUrl: chat.profileImageUrl ?? '',
                                    radius: 24,
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: isOnline
                                          ? Colors.green
                                          : Colors.grey,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                    title: Consumer(
                      builder: (context, ref, child) {
                        final smartNameAsync = ref.watch(
                          smartNameProvider(chat.contactId),
                        );
                        return smartNameAsync.when(
                          data: (name) => Text(
                            name == 'Unknown' ? chat.name : name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          loading: () => Text(
                            chat.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          error: (_, __) => Text(
                            chat.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        );
                      },
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final presenceAsync = ref.watch(
                            userPresenceProvider(chat.contactId),
                          );
                          final isOnline =
                              presenceAsync.valueOrNull?.isOnline ?? false;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  color: isOnline ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  chat.lastMessage ?? 'Started a chat',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: chat.unreadCount > 0
                                        ? Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.color
                                        : Colors.grey[600],
                                    fontWeight: chat.unreadCount > 0
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    trailing: chat.unreadCount > 0
                        ? Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              chat.unreadCount > 99
                                  ? '99+'
                                  : chat.unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                    onLongPress: () {
                      if (!ref.read(chatSelectionProvider).isSelecting) {
                        ref
                            .read(chatSelectionProvider.notifier)
                            .toggleSelectionMode();
                      }
                      ref
                          .read(chatSelectionProvider.notifier)
                          .toggleSelection(chat.contactId);
                    },
                    onTap: () {
                      if (isSelecting) {
                        ref
                            .read(chatSelectionProvider.notifier)
                            .toggleSelection(chat.contactId);
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatDetailScreen(
                            contactId: chat.contactId,
                            contactName: chat.name,
                            contactPic: chat.profileImageUrl,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ContactsScreen()),
          );
        },
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.chat),
      ),
    );
  }
}
