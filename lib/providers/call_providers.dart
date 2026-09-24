import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/call_repository.dart';
import '../models/call_model.dart';

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepository(FirebaseFirestore.instance);
});

final incomingCallStreamProvider = StreamProvider.autoDispose<List<CallModel>>((
  ref,
) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) {
    return Stream.value([]);
  }

  final repository = ref.watch(callRepositoryProvider);
  return repository.getIncomingCallsStream(currentUserId);
});

final callLogsStreamProvider =
    StreamProvider.autoDispose<
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
    >((ref) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return Stream.value([]);

      return FirebaseFirestore.instance
          .collection('calls')
          .where(
            Filter.or(
              Filter('callerId', isEqualTo: user.uid),
              Filter('receiverId', isEqualTo: user.uid),
            ),
          )
          .snapshots()
          .map((snapshot) {
            final docs = snapshot.docs.where((doc) {
              final data = doc.data();
              final deletedBy = data['deleted_by'] as List<dynamic>?;
              return deletedBy == null || !deletedBy.contains(user.uid);
            }).toList();

            docs.sort((a, b) {
              final aData = a.data();
              final bData = b.data();

              final t1 = aData['timestamp'] as Timestamp?;
              final t2 = bData['timestamp'] as Timestamp?;

              final dt1 =
                  t1?.toDate() ??
                  (aData['createdAt'] != null
                      ? DateTime.tryParse(aData['createdAt'])
                      : null);
              final dt2 =
                  t2?.toDate() ??
                  (bData['createdAt'] != null
                      ? DateTime.tryParse(bData['createdAt'])
                      : null);

              if (dt1 == null && dt2 == null) return 0;
              if (dt1 == null) return 1;
              if (dt2 == null) return -1;
              return dt2.compareTo(dt1); // Descending
            });
            return docs;
          });
    });
