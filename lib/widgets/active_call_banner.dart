import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/agora_service.dart';
import '../screens/call/audio_call_screen.dart';
import '../screens/call/video_call_screen.dart';
import '../main.dart';

class ActiveCallBanner extends ConsumerStatefulWidget {
  const ActiveCallBanner({super.key});

  @override
  ConsumerState<ActiveCallBanner> createState() => _ActiveCallBannerState();
}

class _ActiveCallBannerState extends ConsumerState<ActiveCallBanner>
    with WidgetsBindingObserver {
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() {
        _lifecycleState = state;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lifecycleState != AppLifecycleState.resumed)
      return const SizedBox.shrink();

    final agoraState = ref.watch(agoraServiceProvider);

    // Only display if a call is active globally AND the user is not currently viewing the call screen
    if (!agoraState.isCallActive || agoraState.isCallScreenVisible) {
      return const SizedBox.shrink();
    }

    final isVideo = agoraState.isVideo;
    final title = agoraState.remoteName;
    final subtitle = agoraState.remoteUid != null
        ? 'Active ${isVideo ? 'Video' : 'Audio'} Call • ${agoraState.formattedDuration}'
        : agoraState.callStatusText;

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1B5E20), // Dark green WhatsApp-style
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              // Pre-mark visible BEFORE pushing to eliminate banner flash during push animation
              ref
                  .read(agoraServiceProvider.notifier)
                  .setCallScreenVisible(true);
              if (navigatorKey.currentState != null &&
                  agoraState.callId != null) {
                navigatorKey.currentState!.push(
                  MaterialPageRoute(
                    builder: (_) => isVideo
                        ? VideoCallScreen(
                            callerName: agoraState.callId!,
                            agoraChannelId:
                                agoraState.agoraChannelId ?? agoraState.callId!,
                          )
                        : AudioCallScreen(
                            callerName: agoraState.callId!,
                            agoraChannelId:
                                agoraState.agoraChannelId ?? agoraState.callId!,
                          ),
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo ? Icons.videocam : Icons.call,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tap to return',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.open_in_full, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
