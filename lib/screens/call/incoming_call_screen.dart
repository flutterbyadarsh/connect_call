import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'video_call_screen.dart';
import 'audio_call_screen.dart';

import '../../widgets/profile_image.dart';
import '../../repositories/call_repository.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
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
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  bool _isPopping = false;
  bool _isProcessingAccept = false;

  @override
  Widget build(BuildContext context) {
    final repository = CallRepository(FirebaseFirestore.instance);

    // Listen to call status stream: if status turns terminal (e.g. caller cancels), pop screen immediately
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          if (data != null) {
            final status = data['status'];
            final terminalStatuses = [
              'cancelled',
              'declined',
              'missed',
              'ended',
              'rejected',
              'caller_ended',
            ];
            if (terminalStatuses.contains(status)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted &&
                    Navigator.of(context).canPop() &&
                    !_isPopping) {
                  _isPopping = true;
                  FlutterCallkitIncoming.endAllCalls().catchError((_) {});
                  Navigator.of(context).pop();
                }
              });
            }
          }
        }

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                ProfileImage(imageUrl: widget.callerPic, radius: 60),
                const SizedBox(height: 24),
                Text(
                  widget.callerName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Incoming ${widget.isVideo ? 'Video' : 'Audio'} Call...',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline Button
                    FloatingActionButton.large(
                      heroTag: 'decline_btn',
                      onPressed: () async {
                        if (_isPopping) return;
                        _isPopping = true;

                        final user = FirebaseAuth.instance.currentUser;
                        String? name = user?.displayName;
                        if (user != null && (name == null || name.isEmpty)) {
                          final doc = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .get();
                          name = doc.data()?['name'];
                        }

                        await repository.endCallTransaction(
                          callId: widget.callId,
                          status: 'rejected',
                          endedBy: user?.uid,
                          endedByName: name,
                        );

                        FlutterCallkitIncoming.endAllCalls().catchError((_) {});
                        if (context.mounted && Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                      backgroundColor: Colors.red,
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    // Accept Button with Atomic Zombie-Call Pre-Check
                    FloatingActionButton.large(
                      heroTag: 'accept_btn',
                      onPressed: _isProcessingAccept
                          ? null
                          : () async {
                              setState(() => _isProcessingAccept = true);

                              final isAccepted = await repository
                                  .acceptCallPreCheck(widget.callId);

                              if (!isAccepted) {
                                // Call was canceled by caller before receiver accepted
                                FlutterCallkitIncoming.endAllCalls().catchError(
                                  (_) {},
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Call was canceled by the caller',
                                      ),
                                    ),
                                  );
                                  if (Navigator.of(context).canPop()) {
                                    Navigator.of(context).pop();
                                  }
                                }
                                return;
                              }

                              if (context.mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => widget.isVideo
                                        ? VideoCallScreen(
                                            callerName: widget.callId,
                                            agoraChannelId:
                                                widget.agoraChannelId,
                                          )
                                        : AudioCallScreen(
                                            callerName: widget.callId,
                                            agoraChannelId:
                                                widget.agoraChannelId,
                                          ),
                                  ),
                                );
                              }
                            },
                      backgroundColor: Colors.green,
                      child: Icon(
                        widget.isVideo ? Icons.videocam : Icons.call,
                        color: Colors.white,
                        size: 36,
                      ),
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
