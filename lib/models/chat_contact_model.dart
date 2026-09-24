import 'package:cloud_firestore/cloud_firestore.dart';

class ChatContactModel {
  final String contactId;
  final String name;
  final String? profileImageUrl;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final DateTime? clearedAt;
  final bool isHidden;

  ChatContactModel({
    required this.contactId,
    required this.name,
    this.profileImageUrl,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.clearedAt,
    this.isHidden = false,
  });

  factory ChatContactModel.fromFirestore(Map<String, dynamic> map, String id) {
    return ChatContactModel(
      contactId: id,
      name: map['name'] as String? ?? 'Unknown',
      profileImageUrl: map['profileImageUrl'] as String?,
      lastMessage: map['lastMessage'] as String?,
      lastMessageTime: map['lastMessageTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'] as int)
          : null,
      unreadCount: map['unread_count'] as int? ?? 0,
      clearedAt: map['cleared_at'] != null
          ? (map['cleared_at'] is Timestamp
                ? (map['cleared_at'] as Timestamp).toDate().toLocal()
                : DateTime.parse(map['cleared_at'] as String).toLocal())
          : null,
      isHidden: map['is_hidden'] == true,
    );
  }
}
