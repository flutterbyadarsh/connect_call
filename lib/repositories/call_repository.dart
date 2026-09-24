import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/call_model.dart';

class CallRepository {
  final FirebaseFirestore _firestore;

  CallRepository(this._firestore);

  Future<CallModel> initiateCall({
    required String receiverId,
    required String channelId,
    required String callerName,
    required String callerPic,
    required bool isVideo,
  }) async {
    final callerId = FirebaseAuth.instance.currentUser?.uid;
    if (callerId == null) throw Exception("User not authenticated");

    final callDoc = _firestore.collection('calls').doc();

    final newCall = CallModel(
      id: callDoc.id,
      callerId: callerId,
      callerName: callerName,
      callerPic: callerPic,
      receiverId: receiverId,
      channelId: channelId,
      status: 'calling',
      isVideo: isVideo,
      createdAt: DateTime.now(),
    );

    await _firestore
        .runTransaction((transaction) async {
          final receiverDocRef = _firestore.collection('users').doc(receiverId);
          final receiverSnapshot = await transaction.get(receiverDocRef);

          if (receiverSnapshot.exists &&
              receiverSnapshot.data()?['isBusy'] == true) {
            throw Exception("user_busy");
          }

          final rData = receiverSnapshot.data();
          final rName = rData?['name'] ?? 'Unknown';
          final rPic = rData?['profileImageUrl'] ?? '';

          // Mark receiver as busy
          transaction.update(receiverDocRef, {'isBusy': true});

          // Mark caller as busy
          final callerDocRef = _firestore.collection('users').doc(callerId);
          transaction.update(callerDocRef, {'isBusy': true});

          // Create call document with receiver info
          final callMap = newCall.toMap();
          callMap['receiverName'] = rName;
          callMap['receiverPic'] = rPic;
          transaction.set(callDoc, callMap);
        })
        .catchError((e) {
          if (e.toString().contains("user_busy")) {
            throw Exception("user_busy");
          }
          debugPrint("Warning: Firestore initiateCall transaction failed: $e");
          throw Exception("Transaction failed: $e");
        });

    return newCall;
  }

  Future<bool> acceptCallPreCheck(String callId) async {
    try {
      return await _firestore.runTransaction<bool>((transaction) async {
        final callDocRef = _firestore.collection('calls').doc(callId);
        final snapshot = await transaction.get(callDocRef);

        if (!snapshot.exists) return false;

        final data = snapshot.data();
        if (data == null) return false;

        final status = data['status'] as String?;
        // If the call was already canceled, declined, ended, or missed -> block acceptance
        final terminalStatuses = [
          'cancelled',
          'declined',
          'missed',
          'ended',
          'rejected',
          'caller_ended',
        ];
        if (status == null || terminalStatuses.contains(status)) {
          return false;
        }

        // Atomically update status to accepted
        transaction.update(callDocRef, {'status': 'accepted'});
        return true;
      });
    } catch (e) {
      debugPrint("Warning: Firestore acceptCallPreCheck failed: $e");
      return false;
    }
  }

  Future<void> endCallTransaction({
    required String callId,
    required String status,
    String? endedBy,
    String? endedByName,
    int? duration,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final callDocRef = _firestore.collection('calls').doc(callId);
        final snapshot = await transaction.get(callDocRef);

        final updateMap = <String, dynamic>{'status': status};
        if (endedBy != null) updateMap['endedBy'] = endedBy;
        if (endedByName != null) updateMap['endedByName'] = endedByName;
        if (duration != null) updateMap['duration'] = duration;

        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null) {
            final callerId = data['callerId'] as String?;
            final receiverId = data['receiverId'] as String?;

            if (callerId != null && callerId.isNotEmpty) {
              final callerDocRef = _firestore.collection('users').doc(callerId);
              transaction.update(callerDocRef, {'isBusy': false});
            }
            if (receiverId != null && receiverId.isNotEmpty) {
              final receiverDocRef = _firestore
                  .collection('users')
                  .doc(receiverId);
              transaction.update(receiverDocRef, {'isBusy': false});
            }
          }
          transaction.update(callDocRef, updateMap);
        } else {
          transaction.set(callDocRef, updateMap, SetOptions(merge: true));
        }
      });
    } catch (e) {
      debugPrint("Warning: Firestore endCallTransaction failed: $e");
      // Fallback update if transaction fails
      _firestore
          .collection('calls')
          .doc(callId)
          .update({'status': status})
          .catchError((_) {});
    }
  }

  Future<void> updateCallStatus(String callId, String status) async {
    // Non-blocking background write
    _firestore
        .collection('calls')
        .doc(callId)
        .update({'status': status})
        .timeout(const Duration(seconds: 5))
        .catchError((e) {
          debugPrint("Warning: Firestore updateCallStatus failed: $e");
        });
  }

  Stream<List<CallModel>> getIncomingCallsStream(String firebaseUid) {
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: firebaseUid)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CallModel.fromMap(doc.data()))
              .toList(),
        );
  }

  Future<void> deleteCallLogs(String currentUserId, List<String> logIds) async {
    final batch = _firestore.batch();
    for (final id in logIds) {
      final docRef = _firestore.collection('calls').doc(id);
      batch.update(docRef, {
        'deleted_by': FieldValue.arrayUnion([currentUserId]),
      });
    }
    try {
      await batch.commit().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("Warning: Firestore deleteCallLogs failed: $e");
    }
  }

  Future<void> clearAllCallLogs(String currentUserId) async {
    final callerQuery = await _firestore
        .collection('calls')
        .where('callerId', isEqualTo: currentUserId)
        .get();

    final receiverQuery = await _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: currentUserId)
        .get();

    final batch = _firestore.batch();

    for (var doc in callerQuery.docs) {
      if (!(doc.data()['deleted_by'] as List<dynamic>? ?? []).contains(
        currentUserId,
      )) {
        batch.update(doc.reference, {
          'deleted_by': FieldValue.arrayUnion([currentUserId]),
        });
      }
    }

    for (var doc in receiverQuery.docs) {
      if (!(doc.data()['deleted_by'] as List<dynamic>? ?? []).contains(
        currentUserId,
      )) {
        batch.update(doc.reference, {
          'deleted_by': FieldValue.arrayUnion([currentUserId]),
        });
      }
    }

    try {
      await batch.commit().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("Warning: Firestore clearAllCallLogs batch commit failed: $e");
    }
  }
}
