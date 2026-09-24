import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:pip_view/pip_view.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../services/agora_service.dart';
import '../../widgets/call_ui_widgets.dart';
import '../home/home_screen.dart';

class VideoCallScreen extends ConsumerStatefulWidget {
  final String callerName; // Firestore callId (UUID)
  final String agoraChannelId;

  const VideoCallScreen({
    super.key,
    required this.callerName,
    required this.agoraChannelId,
  });

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen>
    with WidgetsBindingObserver {
  bool _isEmulator = false;
  Key _videoKey = UniqueKey();

  // Tracks whether we are inside the native OS PiP window.
  bool _isInNativePip = false;
  late final SimplePip _pip;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDeviceInfo();

    // Subscribe to native PiP state changes (Android only).
    if (Platform.isAndroid) {
      _pip = SimplePip(
        onPipEntered: () {
          if (mounted) setState(() => _isInNativePip = true);
        },
        onPipExited: () {
          if (mounted) {
            setState(() {
              _isInNativePip = false;
              _videoKey = UniqueKey();
            });
          }
          ref.read(agoraServiceProvider.notifier).resumeMedia();
        },
      );
      // Explicitly enable Auto-Enter PiP for Android 12+
      _pip.setAutoPipMode(aspectRatio: const (9, 16), autoEnter: true);
    } else {
      _pip = SimplePip();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(agoraServiceProvider);
      if (state.isInitialized) return; // Prevent re-joining channel

      ref
          .read(agoraServiceProvider.notifier)
          .startCallSession(
            callId: widget.callerName,
            agoraChannelId: widget.agoraChannelId,
            isVideo: true,
          );
    });
  }

  Future<void> _checkDeviceInfo() async {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      _isEmulator = !info.isPhysicalDevice;
    } else {
      _isEmulator = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _enterNativePip() async {
    if (!Platform.isAndroid || _isEmulator) return;
    try {
      final available = await SimplePip.isPipAvailable;
      if (available) {
        await _pip.enterPipMode(
          aspectRatio: const (16, 9),
          seamlessResize: true,
        );
      }
    } catch (e) {
      debugPrint('[VideoCallScreen] Native PiP error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final notifier = ref.read(agoraServiceProvider.notifier);
    final agoraState = ref.read(agoraServiceProvider);

    if (lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.paused) {
      // User pressed home / task switcher: try native PiP during active video call.
      if (agoraState.isCallActive && agoraState.isVideo) {
        _enterNativePip();
      }

      if (!_isInNativePip && Platform.isAndroid) {
        // Fallback: Ensure Background/Foreground Service is running with a high-priority ongoing system notification
        // to keep the WebRTC engine (mic/camera) alive when PiP fails.
        if (lifecycle == AppLifecycleState.paused) notifier.pauseMedia();
        _startForegroundService();
      }
    } else if (lifecycle == AppLifecycleState.resumed) {
      notifier.resumeMedia();
      if (Platform.isAndroid) {
        _stopForegroundService();
      }
      if (mounted) setState(() => _videoKey = UniqueKey());
    }
  }

  void _startForegroundService() {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.startForegroundService(
          id: 112233,
          title: 'Active Call',
          body: 'Tap to return to your call',
          notificationDetails: const AndroidNotificationDetails(
            'call_foreground_channel',
            'Active Calls',
            channelDescription: 'Keeps call active in background',
            importance: Importance.max,
            priority: Priority.high,
            ongoing: true,
          ),
        );
  }

  void _stopForegroundService() {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.stopForegroundService();
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

    // Initialising overlay
    if (!agoraState.isInitialized && agoraState.errorMsg == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Connecting securely…',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) agoraNotifier.setCallScreenVisible(false);
      },
      child: PIPView(
        builder: (context, isFloating) {
          // In either soft-PiP or native PiP mode, or if screen is very small, strip all control overlays.
          final hideControls =
              isFloating ||
              _isInNativePip ||
              MediaQuery.of(context).size.width < 300;

          return Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.expand(
              child: Stack(
                children: [
                  // ── Remote video (full screen) ──────────────────────────
                  _RemoteVideoView(
                    agoraState: agoraState,
                    agoraNotifier: agoraNotifier,
                    channelId: widget.agoraChannelId,
                    videoKey: _videoKey,
                  ),

                  // ── Top bar with name, network, E2E badge ───────────────
                  if (!hideControls)
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        agoraState.remoteName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          // Network quality chip
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.signal_cellular_alt,
                                                  color:
                                                      agoraState.networkColor,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  agoraState.networkQuality,
                                                  style: TextStyle(
                                                    color:
                                                        agoraState.networkColor,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Timer / status
                                          Expanded(
                                            child: CallStatusText(
                                              isConnected:
                                                  agoraState.remoteUid != null,
                                              isInitialized:
                                                  agoraState.isInitialized,
                                              statusText:
                                                  agoraState.errorMsg ??
                                                  agoraState.callStatusText,
                                              formattedDuration:
                                                  agoraState.formattedDuration,
                                              errorMsg: agoraState.errorMsg,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // E2E badge
                                      const EncryptionBadge(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Local camera preview (bottom-right) ─────────────────
                  if (!hideControls)
                    Positioned(
                      right: 16,
                      bottom: 108,
                      child: _LocalVideoPreview(
                        agoraState: agoraState,
                        agoraNotifier: agoraNotifier,
                        videoKey: _videoKey,
                      ),
                    ),

                  // ── Expandable Effects Menu (Right side) ─────────────────
                  if (!hideControls)
                    const Positioned(
                      right: 16,
                      top: 200, // Middle-right placement
                      child: _ExpandableEffectsMenu(),
                    ),

                  // ── Control bar ─────────────────────────────────────────
                  if (!hideControls)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 28,
                      child: _VideoControlBar(
                        agoraState: agoraState,
                        agoraNotifier: agoraNotifier,
                        onPip: () => _enterNativePip(),
                        onSoftPip: () => PIPView.of(
                          context,
                        )?.presentBelow(const HomeScreen()),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Remote video full-screen ─────────────────────────────────────────────────

class _RemoteVideoView extends StatelessWidget {
  final AgoraState agoraState;
  final AgoraService agoraNotifier;
  final String channelId;
  final Key videoKey;

  const _RemoteVideoView({
    required this.agoraState,
    required this.agoraNotifier,
    required this.channelId,
    required this.videoKey,
  });

  @override
  Widget build(BuildContext context) {
    if (agoraState.remoteUid == null) {
      // Waiting / status (top bar already shows status, so just show empty here)
      return const SizedBox.shrink();
    }

    if (agoraState.remoteVideoMuted) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.videocam_off, color: Colors.white54, size: 72),
          SizedBox(height: 12),
          Text(
            'Camera turned off',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
        ],
      );
    }

    if (agoraNotifier.engine == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: agoraState.activeSpeakerUid == agoraState.remoteUid
            ? Border.all(color: Colors.greenAccent, width: 3)
            : null,
      ),
      child: AgoraVideoView(
        key: ValueKey('remote_${videoKey.hashCode}'),
        controller: VideoViewController.remote(
          rtcEngine: agoraNotifier.engine!,
          canvas: VideoCanvas(
            uid: agoraState.remoteUid!,
            renderMode: RenderModeType.renderModeHidden,
          ),
          connection: RtcConnection(channelId: channelId),
          useFlutterTexture: true,
        ),
      ),
    );
  }
}

// ── Local camera thumbnail ────────────────────────────────────────────────────

class _LocalVideoPreview extends StatelessWidget {
  final AgoraState agoraState;
  final AgoraService agoraNotifier;
  final Key videoKey;

  const _LocalVideoPreview({
    required this.agoraState,
    required this.agoraNotifier,
    required this.videoKey,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 100,
        height: 150,
        child: agoraState.isScreenSharing
            ? Container(
                color: Colors.blueGrey.shade900,
                child: const Center(
                  child: Icon(
                    Icons.screen_share,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              )
            : agoraState.isVideoDegraded
            ? Container(
                color: Colors.black87,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.signal_cellular_connected_no_internet_4_bar,
                        color: Colors.orange,
                        size: 24,
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Poor Net",
                        style: TextStyle(color: Colors.orange, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              )
            : !agoraState.isVideoOff && agoraNotifier.engine != null
            ? AgoraVideoView(
                key: ValueKey('local_${videoKey.hashCode}'),
                controller: VideoViewController(
                  rtcEngine: agoraNotifier.engine!,
                  canvas: const VideoCanvas(
                    uid: 0,
                    renderMode: RenderModeType.renderModeHidden,
                  ),
                  useFlutterTexture: true,
                ),
              )
            : Container(
                color: Colors.grey.shade800,
                child: const Center(
                  child: Icon(
                    Icons.videocam_off,
                    color: Colors.white54,
                    size: 32,
                  ),
                ),
              ),
      ),
    );
  }
}

// ── Video control bar ─────────────────────────────────────────────────────────

class _VideoControlBar extends StatelessWidget {
  final AgoraState agoraState;
  final AgoraService agoraNotifier;
  final VoidCallback onPip;
  final VoidCallback onSoftPip;

  const _VideoControlBar({
    required this.agoraState,
    required this.agoraNotifier,
    required this.onPip,
    required this.onSoftPip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            HapticControlButton(
              icon: agoraState.isMuted ? Icons.mic_off : Icons.mic,
              isActive: agoraState.isMuted,
              tooltip: agoraState.isMuted ? 'Unmute' : 'Mute',
              onTap: agoraNotifier.toggleMicrophone,
              size: 50,
              iconSize: 24,
            ),
            HapticControlButton(
              icon: Icons.flip_camera_ios,
              tooltip: 'Flip',
              onTap: agoraNotifier.switchCamera,
              size: 50,
              iconSize: 24,
            ),
            HapticControlButton(
              icon: agoraState.isVideoOff ? Icons.videocam_off : Icons.videocam,
              isActive: agoraState.isVideoOff,
              tooltip: agoraState.isVideoOff
                  ? 'Enable camera'
                  : 'Disable camera',
              onTap: agoraNotifier.toggleCamera,
              size: 50,
              iconSize: 24,
            ),
            const SizedBox(width: 8),
            // Screen Share (Android only)
            if (Platform.isAndroid) ...[
              HapticControlButton(
                icon: agoraState.isScreenSharing
                    ? Icons.stop_screen_share
                    : Icons.screen_share,
                isActive: agoraState.isScreenSharing,
                tooltip: agoraState.isScreenSharing
                    ? 'Stop sharing'
                    : 'Share screen',
                onTap: agoraNotifier.toggleScreenShare,
                size: 50,
                iconSize: 24,
              ),
              const SizedBox(width: 8),
            ],
            // Native PiP on Android, soft PiP fallback elsewhere
            HapticControlButton(
              icon: Icons.picture_in_picture_alt,
              tooltip: 'Picture in Picture',
              onTap: Platform.isAndroid ? onPip : onSoftPip,
              size: 50,
              iconSize: 24,
            ),
            const SizedBox(width: 8),
            // Hang up
            GestureDetector(
              onTap: agoraNotifier.endCallSession,
              child: Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_end,
                  size: 26,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Expandable Effects Menu ───────────────────────────────────────────────────

class _ExpandableEffectsMenu extends ConsumerStatefulWidget {
  const _ExpandableEffectsMenu();

  @override
  ConsumerState<_ExpandableEffectsMenu> createState() =>
      _ExpandableEffectsMenuState();
}

class _ExpandableEffectsMenuState
    extends ConsumerState<_ExpandableEffectsMenu> {
  bool _isExpanded = false;

  void _toggleMenu() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final agoraState = ref.watch(agoraServiceProvider);
    final agoraNotifier = ref.read(agoraServiceProvider.notifier);

    // Total height calculation for animation
    const double expandedHeight = 210.0;
    const double collapsedHeight = 56.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutQuart,
      width: 56,
      height: _isExpanded ? expandedHeight : collapsedHeight,
      decoration: BoxDecoration(
        color: _isExpanded
            ? Colors.blue.withValues(alpha: 0.2)
            : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _isExpanded
              ? Colors.blue.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: _isExpanded
            ? [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main Toggle Icon
              InkWell(
                onTap: _toggleMenu,
                borderRadius: BorderRadius.circular(28),
                child: SizedBox(
                  height: 56,
                  width: 56,
                  child: Icon(
                    _isExpanded ? Icons.close : Icons.auto_awesome,
                    color: _isExpanded ? Colors.blueAccent : Colors.white,
                    size: 24,
                  ),
                ),
              ),

              // Animated children
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _isExpanded ? 1.0 : 0.0,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Divider(color: Colors.white24, height: 1),
                    ),
                    const SizedBox(height: 4),
                    // None (Clear effects)
                    IconButton(
                      icon: const Icon(Icons.block, size: 22),
                      color: !agoraState.isBlurEnabled
                          ? Colors.white
                          : Colors.white54,
                      tooltip: 'No effects',
                      onPressed: () {
                        if (agoraState.isBlurEnabled)
                          agoraNotifier.toggleBlur();
                        _toggleMenu();
                      },
                    ),
                    // Blur
                    IconButton(
                      icon: const Icon(Icons.blur_on, size: 22),
                      color: agoraState.isBlurEnabled
                          ? Colors.blueAccent
                          : Colors.white54,
                      tooltip: 'Blur background',
                      onPressed: () {
                        if (!agoraState.isBlurEnabled)
                          agoraNotifier.toggleBlur();
                        _toggleMenu();
                      },
                    ),
                    // Placeholder AI filter
                    IconButton(
                      icon: const Icon(Icons.face_retouching_natural, size: 22),
                      color: Colors.white54,
                      tooltip: 'AI Filter',
                      onPressed: () {
                        // Using scaffold messenger since we might not have CallToast imported here
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('AI Filter coming soon'),
                            ),
                          );
                        }
                        _toggleMenu();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
