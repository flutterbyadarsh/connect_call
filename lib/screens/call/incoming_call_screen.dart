import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'video_call_screen.dart';
import 'audio_call_screen.dart';
import '../../main.dart';

class IncomingCallScreen extends ConsumerWidget {
  final String callId;
  final String callerName;
  final String callerPic;
  final String agoraChannelId;
  final bool isVideo;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.callerPic,
    required this.agoraChannelId,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen to call status, if it's no longer ringing, pop this screen
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('calls').doc(callId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'];
          if (status == 'missed' || status == 'ended' || status == 'declined') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
          }
        }

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                CircleAvatar(
                  radius: 60,
                  backgroundImage: callerPic.isNotEmpty ? NetworkImage(callerPic) : null,
                  child: callerPic.isEmpty ? const Icon(Icons.person, size: 60) : null,
                ),
                const SizedBox(height: 24),
                Text(
                  callerName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Incoming ${isVideo ? 'Video' : 'Audio'} Call...',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline Button
                    FloatingActionButton.large(
                      heroTag: 'decline_btn',
                      onPressed: () {
                        FirebaseFirestore.instance.collection('calls').doc(callId).update({'status': 'declined'}).catchError((_) {});
                        Navigator.of(context).pop();
                      },
                      backgroundColor: Colors.red,
                      child: const Icon(Icons.call_end, color: Colors.white, size: 36),
                    ),
                    // Accept Button
                    FloatingActionButton.large(
                      heroTag: 'accept_btn',
                      onPressed: () {
                        FirebaseFirestore.instance.collection('calls').doc(callId).update({'status': 'accepted'}).catchError((_) {});
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => isVideo
                                ? VideoCallScreen(callerName: callId, agoraChannelId: agoraChannelId)
                                : AudioCallScreen(callerName: callId, agoraChannelId: agoraChannelId),
                          ),
                        );
                      },
                      backgroundColor: Colors.green,
                      child: Icon(isVideo ? Icons.videocam : Icons.call, color: Colors.white, size: 36),
                    ),
                  ],
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        );
      },
    );
  }
}
