import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';

class CallLogsTab extends ConsumerWidget {
  const CallLogsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('calls')
          .where(Filter.or(
            Filter('callerId', isEqualTo: user.uid),
            Filter('receiverId', isEqualTo: user.uid),
          ))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading call logs\n${snapshot.error}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final docs = snapshot.data?.docs.toList() ?? [];
        docs.sort((a, b) {
          final t1 = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final t2 = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (t1 == null && t2 == null) return 0;
          if (t1 == null) return 1;
          if (t2 == null) return -1;
          return t2.compareTo(t1); // Descending
        });

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No call logs yet.',
              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (ctx, i) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            
            final isOutgoing = data['callerId'] == user.uid;
            final isVideo = data['isVideo'] == true;
            
            final otherName = isOutgoing ? (data['receiverName'] ?? 'Unknown') : (data['callerName'] ?? 'Unknown');
            final otherPic = isOutgoing ? (data['receiverPic'] ?? '') : (data['callerPic'] ?? '');
            final otherId = isOutgoing ? data['receiverId'] : data['callerId'];

            final timestamp = data['timestamp'] as Timestamp?;
            final dateStr = timestamp != null 
                ? DateFormat('MMM d, h:mm a').format(timestamp.toDate()) 
                : 'Just now';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                backgroundImage: otherPic.isNotEmpty 
                    ? MemoryImage(base64Decode(otherPic.split(',').last)) 
                    : null,
                child: otherPic.isEmpty
                    ? Text(
                        otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                        style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 20),
                      )
                    : null,
              ),
              title: Text(otherName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              subtitle: Row(
                children: [
                  Icon(
                    isOutgoing ? Icons.call_made : Icons.call_received,
                    size: 16,
                    color: isOutgoing ? Colors.green : Colors.blue,
                  ),
                  const SizedBox(width: 4),
                  Text(dateStr, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
                ],
              ),
              trailing: IconButton(
                icon: Icon(isVideo ? Icons.videocam : Icons.call, color: Theme.of(context).primaryColor),
                onPressed: () async {
                  final callId = Uuid().v4();
                  await FirebaseFirestore.instance.collection('calls').doc(callId).set({
                    'callerId': user.uid,
                    'callerName': user.name,
                    'callerPic': user.profileImageUrl,
                    'receiverId': otherId,
                    'receiverName': otherName,
                    'receiverPic': otherPic,
                    'isVideo': isVideo,
                    'timestamp': FieldValue.serverTimestamp(),
                  });
                  
                  if (!context.mounted) return;
                  if (isVideo) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => VideoCallScreen(callerName: callId)));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => AudioCallScreen(callerName: callId)));
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}
