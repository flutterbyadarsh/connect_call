import 'package:cloud_firestore/cloud_firestore.dart';

class CallModel {
  final String id;
  final String callerId;
  final String callerName;
  final String callerPic;
  final String receiverId;
  final String channelId;
  final String status;
  final bool isVideo;
  final DateTime createdAt;
  final String? endedBy;
  final String? endedByName;

  CallModel({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.callerPic,
    required this.receiverId,
    required this.channelId,
    required this.status,
    required this.isVideo,
    required this.createdAt,
    this.endedBy,
    this.endedByName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'callerId': callerId,
      'callerName': callerName,
      'callerPic': callerPic,
      'receiverId': receiverId,
      'channelId': channelId,
      'agoraChannelId': channelId, // for cloud function compatibility
      'status': status,
      'isVideo': isVideo,
      'createdAt': createdAt.toIso8601String(),
      'timestamp': FieldValue.serverTimestamp(),
      if (endedBy != null) 'endedBy': endedBy,
      if (endedByName != null) 'endedByName': endedByName,
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      id: map['id'] ?? '',
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerPic: map['callerPic'] ?? '',
      receiverId: map['receiverId'] ?? '',
      channelId: map['channelId'] ?? map['agoraChannelId'] ?? '',
      status: map['status'] ?? 'calling',
      isVideo: map['isVideo'] ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      endedBy: map['endedBy'],
      endedByName: map['endedByName'],
    );
  }
}
