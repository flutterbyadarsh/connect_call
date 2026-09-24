import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/chat_repository.dart';
import '../models/message_model.dart';
import '../models/chat_contact_model.dart';

// Provides the ChatRepository instance
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(FirebaseFirestore.instance);
});

// Provides the current user's active chats (recent conversations)
final activeChatsProvider = StreamProvider<List<ChatContactModel>>((ref) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) {
    return Stream.value([]);
  }

  final chatRepo = ref.watch(chatRepositoryProvider);
  return chatRepo.getActiveChatsStream(currentUserId);
});

// Provides the total unread message count
final totalUnreadCountProvider = Provider<int>((ref) {
  final activeChats = ref.watch(activeChatsProvider);
  return activeChats.maybeWhen(
    data: (chats) => chats
        .where((c) => !c.isHidden)
        .fold(0, (sum, chat) => sum + chat.unreadCount),
    orElse: () => 0,
  );
});

// Provides the real-time messages for a specific 1-to-1 chat
final chatMessagesProvider = StreamProvider.family<List<MessageModel>, String>((
  ref,
  otherUserId,
) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) {
    return Stream.value([]);
  }

  final chatRepo = ref.watch(chatRepositoryProvider);
  return chatRepo.getMessagesStream(currentUserId, otherUserId).map((messages) {
    return messages
        .where((msg) => msg.deletedBy?.contains(currentUserId) != true)
        .toList();
  });
});

// Provides the smart name (alias/nickname if exists, otherwise fallback name)
final smartNameProvider = StreamProvider.family<String, String>((
  ref,
  targetUserId,
) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) return Stream.value('Unknown');

  // Listen to the saved_contacts subcollection for the nickname
  final nicknameStream = FirebaseFirestore.instance
      .collection('users')
      .doc(currentUserId)
      .collection('saved_contacts')
      .doc(targetUserId)
      .snapshots()
      .map((doc) => doc.exists ? (doc.data()?['nickname'] as String?) : null);

  // Listen to the target user's original name
  final originalNameStream = FirebaseFirestore.instance
      .collection('users')
      .doc(targetUserId)
      .snapshots()
      .map(
        (doc) => doc.exists
            ? (doc.data()?['name'] as String? ?? 'Unknown')
            : 'Unknown',
      );

  // Combine both streams
  return nicknameStream.asyncMap((nickname) async {
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }
    // If no nickname, wait for the latest original name
    final originalName = await originalNameStream.first;
    return originalName;
  });
});
