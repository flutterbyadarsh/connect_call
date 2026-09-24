import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/message_model.dart';
import '../models/chat_contact_model.dart';

class ChatRepository {
  final FirebaseFirestore _firestore;

  ChatRepository(this._firestore);

  String getChatRoomId(String uid1, String uid2) {
    return uid1.compareTo(uid2) > 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    final messageId = const Uuid().v4();

    // Save to Firestore messages collection
    final messageData = {
      'id': messageId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'is_read': false,
      'message_status': 'sent',
      'created_at': FieldValue.serverTimestamp(),
    };
    // 1. Update sender's recent chats
    await _firestore
        .collection('users')
        .doc(senderId)
        .collection('chats')
        .doc(receiverId)
        .set({
          'contact_id': receiverId,
          'last_message': content,
          'last_message_time': FieldValue.serverTimestamp(),
          'is_hidden': false, // Unhide if it was deleted
        }, SetOptions(merge: true));

    // 2. Update receiver's recent chats (increment unread)
    final receiverChatRef = _firestore
        .collection('users')
        .doc(receiverId)
        .collection('chats')
        .doc(senderId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(receiverChatRef);
      int currentUnread = 0;
      if (snapshot.exists && snapshot.data()!.containsKey('unread_count')) {
        currentUnread = snapshot.data()!['unread_count'] as int;
      }

      transaction.set(receiverChatRef, {
        'contact_id': senderId,
        'last_message': content,
        'last_message_time': FieldValue.serverTimestamp(),
        'unread_count': currentUnread + 1,
        'is_hidden': false, // Unhide if it was deleted
      }, SetOptions(merge: true));
    });

    // 3. Save to Firestore messages collection (Do this LAST to prevent race conditions with the receiver's active listener)
    final chatRoomId = getChatRoomId(senderId, receiverId);
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .set(messageData);
  }

  // Mark messages as read
  // Explicitly reset the unread count for a specific chat
  Future<void> resetUnreadCount({
    required String currentUserId,
    required String otherUserId,
  }) async {
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('chats')
        .doc(otherUserId)
        .set({'unread_count': 0}, SetOptions(merge: true));
  }

  Future<void> markMessagesAsRead({
    required String currentUserId,
    required String otherUserId,
  }) async {
    // 1. Reset unread count in recent chats
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('chats')
        .doc(otherUserId)
        .set({'unread_count': 0}, SetOptions(merge: true));

    // 2. Mark messages as read in messages collection
    final chatRoomId = getChatRoomId(currentUserId, otherUserId);
    final unreadMessagesQuery = await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .where('receiver_id', isEqualTo: currentUserId)
        .where('sender_id', isEqualTo: otherUserId)
        .where('is_read', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (var doc in unreadMessagesQuery.docs) {
      batch.update(doc.reference, {'is_read': true, 'message_status': 'read'});
    }
    await batch.commit();
  }

  // Get message stream
  Stream<List<MessageModel>> getMessagesStream(
    String currentUserId,
    String otherUserId,
  ) {
    final chatRoomId = getChatRoomId(currentUserId, otherUserId);
    return _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .snapshots()
        .map((snapshot) {
          final messages = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return MessageModel.fromMap(data);
          }).toList();

          // Sort locally to ensure optimistic updates (which have null timestamps locally)
          // are not filtered out by Firestore's orderBy query constraints.
          messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return messages;
        });
  }

  // Add reaction to a message
  Future<void> addReaction({
    required String messageId,
    required String currentUserId,
    required String otherUserId,
    required String emoji,
  }) async {
    final chatRoomId = getChatRoomId(currentUserId, otherUserId);
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .set({
          'reactions': {currentUserId: emoji},
        }, SetOptions(merge: true));
  }

  // Delete message for local user
  Future<void> deleteMessageForMe({
    required String messageId,
    required String currentUserId,
    required String otherUserId,
  }) async {
    final chatRoomId = getChatRoomId(currentUserId, otherUserId);
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .update({
          'deleted_by': FieldValue.arrayUnion([currentUserId]),
        });
  }

  // Delete message for everyone
  Future<void> deleteMessageForEveryone({
    required String messageId,
    required String currentUserId,
    required String otherUserId,
  }) async {
    final chatRoomId = getChatRoomId(currentUserId, otherUserId);
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .update({
          'content': 'This message was deleted',
          'is_read': true, // Optional: prevents unread badge on deleted message
        });
  }

  // Clear Chat for local user
  Future<void> clearChat({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final docRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('chats')
        .doc(otherUserId);

    final docSnap = await docRef.get();

    final data = <String, dynamic>{
      'contact_id': otherUserId,
      'cleared_at': FieldValue.serverTimestamp(),
      'last_message': 'Chat cleared',
    };

    if (!docSnap.exists || docSnap.data()?['last_message_time'] == null) {
      data['last_message_time'] = FieldValue.serverTimestamp();
    }

    await docRef.set(data, SetOptions(merge: true));
  }

  // Delete Chat for local user
  Future<void> deleteChat({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final docRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('chats')
        .doc(otherUserId);

    final docSnap = await docRef.get();

    final data = <String, dynamic>{
      'contact_id': otherUserId,
      'cleared_at': FieldValue.serverTimestamp(),
      'is_hidden': true,
    };

    if (!docSnap.exists || docSnap.data()?['last_message_time'] == null) {
      data['last_message_time'] = FieldValue.serverTimestamp();
    }

    await docRef.set(data, SetOptions(merge: true));
  }

  // Delete All Chats for local user
  Future<void> deleteAllChats(String currentUserId) async {
    final chatsSnapshot = await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('chats')
        .get();

    final batch = _firestore.batch();
    for (var doc in chatsSnapshot.docs) {
      batch.set(doc.reference, {
        'cleared_at': FieldValue.serverTimestamp(),
        'is_hidden': true,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // Set Nickname for a contact
  Future<void> setContactNickname({
    required String currentUserId,
    required String targetUserId,
    required String nickname,
  }) async {
    final docRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('saved_contacts')
        .doc(targetUserId);

    if (nickname.trim().isEmpty) {
      await docRef.delete();
    } else {
      await docRef.set({
        'nickname': nickname.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // Get active chats (contacts) stream
  Stream<List<ChatContactModel>> getActiveChatsStream(String currentUserId) {
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('chats')
        .orderBy('last_message_time', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          List<ChatContactModel> contacts = [];
          for (var doc in snapshot.docs) {
            final data = doc.data();
            final contactId = data['contact_id'] as String;

            // Fetch user details
            final userDoc = await _firestore
                .collection('users')
                .doc(contactId)
                .get();
            final userData = userDoc.data() ?? {};

            contacts.add(
              ChatContactModel(
                contactId: contactId,
                name: userData['name'] ?? 'Unknown',
                profileImageUrl: userData['profileImageUrl'],
                lastMessage: data['last_message'],
                lastMessageTime: data['last_message_time'] != null
                    ? (data['last_message_time'] is Timestamp
                          ? (data['last_message_time'] as Timestamp)
                                .toDate()
                                .toLocal()
                          : DateTime.parse(
                              data['last_message_time'] as String,
                            ).toLocal())
                    : DateTime.now(),
                unreadCount: data['unread_count'] ?? 0,
                clearedAt: data['cleared_at'] != null
                    ? (data['cleared_at'] is Timestamp
                          ? (data['cleared_at'] as Timestamp).toDate().toLocal()
                          : DateTime.parse(
                              data['cleared_at'] as String,
                            ).toLocal())
                    : null,
                isHidden: data['is_hidden'] == true,
              ),
            );
          }
          return contacts;
        });
  }
}
