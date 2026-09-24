import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, String>? reactions;
  final String messageStatus; // 'sent', 'delivered', 'seen'
  final List<String>?
  deletedBy; // UIDs of users who deleted this message for themselves

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    this.isRead = false,
    this.reactions,
    this.messageStatus = 'sent',
    this.deletedBy,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      receiverId: map['receiver_id'] as String,
      content: map['content'] as String,
      createdAt: map['created_at'] == null
          ? DateTime.now()
          : (map['created_at'] is Timestamp
                ? (map['created_at'] as Timestamp).toDate().toLocal()
                : DateTime.parse(map['created_at'] as String).toLocal()),
      isRead: map['is_read'] ?? false,
      reactions: map['reactions'] != null
          ? Map<String, String>.from(map['reactions'])
          : null,
      messageStatus: map['message_status'] as String? ?? 'sent',
      deletedBy: map['deleted_by'] != null
          ? List<String>.from(map['deleted_by'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'is_read': isRead,
      'message_status': messageStatus,
      if (reactions != null) 'reactions': reactions,
      if (deletedBy != null) 'deleted_by': deletedBy,
    };
  }
}
