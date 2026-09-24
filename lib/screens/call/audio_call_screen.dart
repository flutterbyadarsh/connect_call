import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_theme.dart';
import '../../services/agora_service.dart';
import '../../widgets/call_ui_widgets.dart';
import '../../widgets/call_toast.dart';
import 'video_call_screen.dart';

class AudioCallScreen extends ConsumerStatefulWidget {
  final String callerName; // Firestore callId (UUID)
  final String agoraChannelId;

  const AudioCallScreen({
    super.key,
    required this.callerName,
    required this.agoraChannelId,
  });

  @override
  ConsumerState<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends ConsumerState<AudioCallScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(agoraServiceProvider);
      if (state.isInitialized) return; // Prevent re-joining channel

      ref
          .read(agoraServiceProvider.notifier)
          .startCallSession(
            callId: widget.callerName,
            agoraChannelId: widget.agoraChannelId,
            isVideo: false,
          );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final notifier = ref.read(agoraServiceProvider.notifier);
    if (lifecycle == AppLifecycleState.resumed) {
      notifier.resumeMedia();
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.inactive) {
      notifier.pauseMedia();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agoraState = ref.watch(agoraServiceProvider);
    final agoraNotifier = ref.read(agoraServiceProvider.notifier);

    final isConnected = agoraState.remoteUid != null;
    final isRinging = agoraState.callStatusText == 'Ringing';

    ref.listen<AgoraState>(agoraServiceProvider, (previous, next) {
      if (previous == null) return;

      // 1. Transition to video screen if upgraded
      if (!previous.isVideo && next.isVideo) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => VideoCallScreen(
                callerName: widget.callerName,
                agoraChannelId: widget.agoraChannelId,
              ),
            ),
          );
        }
      }

      // 2. Incoming video upgrade request dialog
      if (previous.videoUpgradeRequest == null &&
          next.videoUpgradeRequest != null) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (next.videoUpgradeRequest != currentUid) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text(
                'Video Call Request',
                style: TextStyle(color: Colors.white),
              ),
              content: Text(
                '${next.remoteName} wants to turn on video.',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    agoraNotifier.rejectVideoUpgrade();
                  },
                  child: const Text(
                    'Decline',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    agoraNotifier.acceptVideoUpgrade();
                  },
                  child: const Text(
                    'Accept',
                    style: TextStyle(color: Colors.greenAccent),
                  ),
                ),
              ],
            ),
          );
        }
      }
    });

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) agoraNotifier.setCallScreenVisible(false);
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryColor.withValues(alpha: 0.85),
                const Color(0xFF0F0C29),
                Colors.black,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Top bar ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 32,
                        ),
                        tooltip: 'Minimise',
                        onPressed: () {
                          agoraNotifier.setCallScreenVisible(false);
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Caller info ────────────────────────────────────────────
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Pulsing ripple avatar
                      RippleAvatar(
                        imageBytes: agoraState.remotePicBytes,
                        isRinging: isRinging,
                        isConnected: isConnected,
                      ),

                      const SizedBox(height: 28),

                      // Remote user name
                      Text(
                        agoraState.remoteName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Animated status / timer
                      CallStatusText(
                        isConnected: isConnected,
                        isInitialized: agoraState.isInitialized,
                        statusText:
                            agoraState.errorMsg ?? agoraState.callStatusText,
                        formattedDuration: agoraState.formattedDuration,
                        errorMsg: agoraState.errorMsg,
                      ),

                      const SizedBox(height: 20),

                      // E2E encryption badge
                      const EncryptionBadge(),
                    ],
                  ),
                ),

                // ── Controls ───────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 32,
                    horizontal: 40,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(44),
                      topRight: Radius.circular(44),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      HapticControlButton(
                        icon: agoraState.isMuted ? Icons.mic_off : Icons.mic,
                        isActive: agoraState.isMuted,
                        tooltip: agoraState.isMuted ? 'Unmute' : 'Mute',
                        onTap: agoraNotifier.toggleMicrophone,
                      ),

                      // ── Video Upgrade Button ──
                      HapticControlButton(
                        icon: Icons.videocam,
                        tooltip: 'Turn on video',
                        onTap: () {
                          if (agoraState.videoUpgradeRequest != null) {
                            CallToast.show(
                              message: "Request already sent...",
                              type: CallToastType.info,
                            );
                          } else {
                            agoraNotifier.requestVideoUpgrade();
                            CallToast.show(
                              message: "Requesting video upgrade...",
                              type: CallToastType.info,
                            );
                          }
                        },
                      ),

                      // Hang-up button — heavyImpact already fires in endCallSession
                      GestureDetector(
                        onTap: agoraNotifier.endCallSession,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call_end,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      _SpeakerButton(agoraNotifier: agoraNotifier),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Speaker toggle (local state only) ─────────────────────────────────────────

class _SpeakerButton extends StatefulWidget {
  final AgoraService agoraNotifier;
  const _SpeakerButton({required this.agoraNotifier});

  @override
  State<_SpeakerButton> createState() => _SpeakerButtonState();
}

class _SpeakerButtonState extends State<_SpeakerButton> {
  bool _isSpeaker = false;

  @override
  Widget build(BuildContext context) {
    return HapticControlButton(
      icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
      isActive: _isSpeaker,
      tooltip: _isSpeaker ? 'Earpiece' : 'Speaker',
      onTap: () {
        setState(() => _isSpeaker = !_isSpeaker);
        widget.agoraNotifier.setSpeakerphone(_isSpeaker);
      },
    );
  }
}
