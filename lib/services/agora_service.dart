import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'agora_token_service.dart';
import 'call_feedback_service.dart';
import '../repositories/call_repository.dart';
import '../main.dart';
import '../screens/home/home_screen.dart';
import '../widgets/call_toast.dart';

const String _kAgoraAppId = "99082f23cb0047f8893f5b8ac23d50a7";

class AgoraState {
  final bool isInitializing;
  final bool isInitialized;
  final bool isJoined;
  final int? remoteUid;
  final bool isMuted;
  final bool isVideoOff;
  final bool remoteVideoMuted;
  final String networkQuality;
  final Color networkColor;
  final String? errorMsg;
  final bool isCallEndedByRemote;
  final bool isBlurEnabled;
  final int? activeSpeakerUid;
  final bool isScreenSharing;
  final bool isVideoDegraded;
  final String? videoUpgradeRequest;

  // Decoupled Global Active Call Session Fields
  final bool isCallActive;
  final bool isCallScreenVisible;
  final String? callId;
  final String? agoraChannelId;
  final String remoteName;
  final String remotePic;
  final Uint8List? remotePicBytes;
  final bool isVideo;
  final int callDurationSeconds;
  final String callStatusText;

  AgoraState({
    this.isInitializing = false,
    this.isInitialized = false,
    this.isJoined = false,
    this.remoteUid,
    this.isMuted = false,
    this.isVideoOff = false,
    this.remoteVideoMuted = false,
    this.networkQuality = 'Good',
    this.networkColor = Colors.green,
    this.errorMsg,
    this.isCallEndedByRemote = false,
    this.isBlurEnabled = false,
    this.activeSpeakerUid,
    this.isScreenSharing = false,
    this.isVideoDegraded = false,
    this.videoUpgradeRequest,
    this.isCallActive = false,
    this.isCallScreenVisible = false,
    this.callId,
    this.agoraChannelId,
    this.remoteName = 'Connecting...',
    this.remotePic = '',
    this.remotePicBytes,
    this.isVideo = false,
    this.callDurationSeconds = 0,
    this.callStatusText = 'Calling...',
  });

  String get formattedDuration {
    final minutes = (callDurationSeconds / 60).floor().toString().padLeft(
      2,
      '0',
    );
    final seconds = (callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  AgoraState copyWith({
    bool? isInitializing,
    bool? isInitialized,
    bool? isJoined,
    int? remoteUid,
    bool? clearRemoteUid,
    bool? isMuted,
    bool? isVideoOff,
    bool? remoteVideoMuted,
    String? networkQuality,
    Color? networkColor,
    String? errorMsg,
    bool? clearError,
    bool? isCallEndedByRemote,
    bool? isBlurEnabled,
    int? activeSpeakerUid,
    bool? clearActiveSpeaker,
    bool? isScreenSharing,
    bool? isVideoDegraded,
    String? videoUpgradeRequest,
    bool? clearVideoUpgradeRequest,
    bool? isCallActive,
    bool? isCallScreenVisible,
    String? callId,
    String? agoraChannelId,
    String? remoteName,
    String? remotePic,
    Uint8List? remotePicBytes,
    bool? isVideo,
    int? callDurationSeconds,
    String? callStatusText,
  }) {
    return AgoraState(
      isInitializing: isInitializing ?? this.isInitializing,
      isInitialized: isInitialized ?? this.isInitialized,
      isJoined: isJoined ?? this.isJoined,
      remoteUid: clearRemoteUid == true ? null : (remoteUid ?? this.remoteUid),
      isMuted: isMuted ?? this.isMuted,
      isVideoOff: isVideoOff ?? this.isVideoOff,
      remoteVideoMuted: remoteVideoMuted ?? this.remoteVideoMuted,
      networkQuality: networkQuality ?? this.networkQuality,
      networkColor: networkColor ?? this.networkColor,
      errorMsg: clearError == true ? null : (errorMsg ?? this.errorMsg),
      isCallEndedByRemote: isCallEndedByRemote ?? this.isCallEndedByRemote,
      isBlurEnabled: isBlurEnabled ?? this.isBlurEnabled,
      activeSpeakerUid: clearActiveSpeaker == true
          ? null
          : (activeSpeakerUid ?? this.activeSpeakerUid),
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isVideoDegraded: isVideoDegraded ?? this.isVideoDegraded,
      videoUpgradeRequest: clearVideoUpgradeRequest == true
          ? null
          : (videoUpgradeRequest ?? this.videoUpgradeRequest),
      isCallActive: isCallActive ?? this.isCallActive,
      isCallScreenVisible: isCallScreenVisible ?? this.isCallScreenVisible,
      callId: callId ?? this.callId,
      agoraChannelId: agoraChannelId ?? this.agoraChannelId,
      remoteName: remoteName ?? this.remoteName,
      remotePic: remotePic ?? this.remotePic,
      remotePicBytes: remotePicBytes ?? this.remotePicBytes,
      isVideo: isVideo ?? this.isVideo,
      callDurationSeconds: callDurationSeconds ?? this.callDurationSeconds,
      callStatusText: callStatusText ?? this.callStatusText,
    );
  }
}

class AgoraService extends StateNotifier<AgoraState> {
  AgoraService() : super(AgoraState());

  RtcEngine? _engine;
  bool _isDisposed = false;

  Timer? _callingTimer;
  Timer? _ringingTimer;
  Timer? _callDurationTimer;
  StreamSubscription? _callStatusSubscription;

  RtcEngine? get engine => _engine;

  void setCallScreenVisible(bool visible) {
    state = state.copyWith(isCallScreenVisible: visible);
  }

  Future<void> startCallSession({
    required String callId,
    required String agoraChannelId,
    required bool isVideo,
    String remoteName = 'Connecting...',
    String remotePic = '',
  }) async {
    // If already active in the same channel, just ensure screen visibility
    if (state.isCallActive && state.callId == callId) {
      state = state.copyWith(isCallScreenVisible: true);
      return;
    }

    // Reset previous state
    _cleanupTimersAndSubscriptions();

    Uint8List? picBytes;
    if (remotePic.isNotEmpty) {
      try {
        picBytes = base64Decode(remotePic.split(',').last);
      } catch (_) {}
    }

    state = AgoraState(
      isCallActive: true,
      isCallScreenVisible: true,
      callId: callId,
      agoraChannelId: agoraChannelId,
      isVideo: isVideo,
      remoteName: remoteName,
      remotePic: remotePic,
      remotePicBytes: picBytes,
      callStatusText: 'Calling...',
    );

    // Atomic Pre-Check: Verify call status in Firestore before engine initialization
    try {
      final doc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();
      if (doc.exists) {
        final status = doc.data()?['status'] as String?;
        // Busy state: receiver is already on another call
        if (status == 'busy') {
          final name = state.remoteName;
          CallToast.show(
            message: '$name is busy on another call',
            type: CallToastType.busy,
          );
          await CallFeedbackService.instance.playBusyTone();
          await endCallSession(updateStatus: false);
          return;
        }
        final terminalStatuses = [
          'cancelled',
          'declined',
          'missed',
          'ended',
          'rejected',
          'caller_ended',
        ];
        if (status != null && terminalStatuses.contains(status)) {
          CallToast.show(
            message: 'Call is no longer available',
            type: CallToastType.info,
          );
          await endCallSession(updateStatus: false);
          return;
        }
      }
    } catch (e) {
      debugPrint("Error performing pre-check in startCallSession: $e");
    }

    // Timers setup — offline timeout
    _callingTimer = Timer(const Duration(seconds: 15), () {
      if (state.isCallActive) {
        final name = state.remoteName;
        CallToast.show(
          message: '$name is offline or unreachable',
          type: CallToastType.missed,
        );
        endCallSession(targetStatus: 'missed');
      }
    });

    // Subscribe to Firestore call status
    _callStatusSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots(includeMetadataChanges: true)
        .listen((doc) async {
          if (doc.exists && state.isCallActive) {
            final status = doc.data()?['status'] as String?;

            if (status == 'busy') {
              // Receiver became busy after the call was initiated
              final name = state.remoteName;
              CallToast.show(
                message: '$name is busy on another call',
                type: CallToastType.busy,
              );
              await CallFeedbackService.instance.playBusyTone();
              endCallSession(updateStatus: false);
            } else if (status == 'ringing') {
              _callingTimer?.cancel();
              if (_ringingTimer == null) {
                state = state.copyWith(callStatusText: 'Ringing');
                _ringingTimer = Timer(const Duration(seconds: 30), () {
                  if (state.isCallActive) {
                    final name = state.remoteName;
                    CallToast.show(
                      message: '$name is not responding',
                      type: CallToastType.missed,
                    );
                    endCallSession(targetStatus: 'missed');
                  }
                });
              }
            } else if (status == 'rejected') {
              // Use remoteName from state — already populated by document listener below
              final name = state.remoteName;
              final endedByName = doc.data()?['endedByName'] as String?;
              final displayName =
                  (endedByName != null && endedByName.isNotEmpty)
                  ? endedByName
                  : name;
              CallToast.show(
                message: '$displayName declined the call',
                type: CallToastType.declined,
              );
              endCallSession(updateStatus: false);
            } else if (status == 'ended' || status == 'caller_ended') {
              final name = state.remoteName;
              CallToast.show(
                message: '$name ended the call',
                type: CallToastType.ended,
              );
              endCallSession(updateStatus: false);
            } else if (status == 'accepted') {
              _callingTimer?.cancel();
              _ringingTimer?.cancel();
              state = state.copyWith(callStatusText: 'Connected');
            }

            // Fetch remote user name/picture from call document
            final data = doc.data();
            if (data != null) {
              // Check for video upgrade requests mid-call
              if (data.containsKey('videoUpgradeRequest')) {
                final requestUid = data['videoUpgradeRequest'] as String?;
                if (requestUid != null && requestUid.isNotEmpty) {
                  final currentUid = FirebaseAuth.instance.currentUser?.uid;
                  if (currentUid != null &&
                      requestUid != currentUid &&
                      state.videoUpgradeRequest != requestUid) {
                    // A new request from the remote user
                    state = state.copyWith(videoUpgradeRequest: requestUid);
                  } else if (requestUid == currentUid &&
                      state.videoUpgradeRequest != requestUid) {
                    // We sent the request, track it
                    state = state.copyWith(videoUpgradeRequest: requestUid);
                  }
                } else if (requestUid == null &&
                    state.videoUpgradeRequest != null) {
                  // Request was cleared (accepted or rejected)
                  state = state.copyWith(clearVideoUpgradeRequest: true);
                }
              }

              final currentUid = FirebaseAuth.instance.currentUser?.uid;
              if (currentUid != null) {
                String newRemoteName = state.remoteName;
                String newRemotePic = state.remotePic;

                if (data['callerId'] == currentUid) {
                  newRemoteName = data['receiverName'] ?? state.remoteName;
                  newRemotePic = data['receiverPic'] ?? state.remotePic;
                } else {
                  newRemoteName = data['callerName'] ?? state.remoteName;
                  newRemotePic = data['callerPic'] ?? state.remotePic;
                }

                if (newRemoteName != state.remoteName ||
                    newRemotePic != state.remotePic) {
                  Uint8List? bytes;
                  if (newRemotePic.isNotEmpty) {
                    try {
                      bytes = base64Decode(newRemotePic.split(',').last);
                    } catch (_) {}
                  }
                  state = state.copyWith(
                    remoteName: newRemoteName,
                    remotePic: newRemotePic,
                    remotePicBytes: bytes,
                  );
                }
              }
            }
          }
        });

    // Initialize WebRTC engine
    await initAgora(channelId: agoraChannelId, isVideo: isVideo);
  }

  Future<void> initAgora({
    required String channelId,
    required bool isVideo,
  }) async {
    if (state.isInitializing || state.isInitialized) return;
    _isDisposed = false;

    state = state.copyWith(isInitializing: true, clearError: true);

    try {
      final permissions = isVideo
          ? [Permission.microphone, Permission.camera]
          : [Permission.microphone];
      final statuses = await permissions.request();

      if (statuses.values.any((status) => status != PermissionStatus.granted)) {
        state = state.copyWith(
          isInitializing: false,
          errorMsg: 'Required permissions denied.',
        );
        endCallSession(updateStatus: false);
        return;
      }

      final agoraData = await AgoraTokenService.getToken(channelId);
      final dynamicToken = agoraData['token']!;
      final backendAppId = agoraData['appId']!;

      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: backendAppId.isNotEmpty ? backendAppId : _kAgoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      await _engine!.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint("local user ${connection.localUid} joined");
            _engine?.setEnableSpeakerphone(isVideo);
            if (!_isDisposed)
              state = state.copyWith(isJoined: true, clearError: true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint("remote user $remoteUid joined");
            if (!_isDisposed) {
              _callingTimer?.cancel();
              _ringingTimer?.cancel();
              state = state.copyWith(
                remoteUid: remoteUid,
                clearError: true,
                callStatusText: 'Connected',
              );
              _startDurationTimer();
              // ── Haptic: Call Connected ──────────────────────────────────
              HapticFeedback.mediumImpact();
            }
          },
          onUserOffline:
              (
                RtcConnection connection,
                int remoteUid,
                UserOfflineReasonType reason,
              ) {
                debugPrint("remote user $remoteUid left channel");
                if (!_isDisposed) {
                  state = state.copyWith(
                    clearRemoteUid: true,
                    isCallEndedByRemote: true,
                  );
                  endCallSession();
                }
              },
          onUserMuteVideo:
              (RtcConnection connection, int remoteUid, bool muted) {
                debugPrint("remote user $remoteUid muted video: $muted");
                if (!_isDisposed)
                  state = state.copyWith(remoteVideoMuted: muted);
              },
          onNetworkQuality:
              (
                RtcConnection connection,
                int remoteUid,
                QualityType txQuality,
                QualityType rxQuality,
              ) {
                if (remoteUid == 0 && !_isDisposed) {
                  int tx = txQuality.index;
                  int rx = rxQuality.index;
                  int worst = tx > rx ? tx : rx;
                  if (worst == 0) return;

                  String quality = 'Good';
                  Color color = Colors.green;
                  if (worst == 3) {
                    quality = 'Fair';
                    color = Colors.orange;
                  } else if (worst >= 4) {
                    quality = 'Poor';
                    color = Colors.red;
                  }

                  if (state.networkQuality != quality) {
                    state = state.copyWith(
                      networkQuality: quality,
                      networkColor: color,
                    );
                  }

                  // ── Network Fallback ──
                  if (state.isVideo) {
                    if (worst >= 4 && !state.isVideoDegraded) {
                      // Network poor -> Degrade video
                      CallToast.show(
                        message:
                            "Poor connection. Pausing video to improve audio.",
                        type: CallToastType.info,
                      );
                      _engine?.muteLocalVideoStream(true);
                      state = state.copyWith(isVideoDegraded: true);
                    } else if (worst < 4 && state.isVideoDegraded) {
                      // Network recovered -> Restore video
                      CallToast.show(
                        message: "Connection recovered. Restoring video.",
                        type: CallToastType.info,
                      );
                      _engine?.muteLocalVideoStream(
                        state.isVideoOff,
                      ); // Only restore if user didn't explicitly turn it off
                      state = state.copyWith(isVideoDegraded: false);
                    }
                  }
                }
              },
          onAudioVolumeIndication:
              (
                RtcConnection connection,
                List<AudioVolumeInfo> speakers,
                int totalVolume,
                int extra,
              ) {
                if (_isDisposed) return;
                if (speakers.isNotEmpty) {
                  AudioVolumeInfo activeSpeaker = speakers.reduce(
                    (curr, next) =>
                        (curr.volume ?? 0) > (next.volume ?? 0) ? curr : next,
                  );
                  if ((activeSpeaker.volume ?? 0) > 5) {
                    state = state.copyWith(
                      activeSpeakerUid: activeSpeaker.uid == 0
                          ? null
                          : activeSpeaker.uid,
                    );
                  } else {
                    state = state.copyWith(clearActiveSpeaker: true);
                  }
                } else {
                  state = state.copyWith(clearActiveSpeaker: true);
                }
              },
          onTokenPrivilegeWillExpire:
              (RtcConnection connection, String token) async {
                if (_isDisposed || state.callId == null) return;
                debugPrint("Token will expire soon. Renewing...");
                try {
                  final agoraData = await AgoraTokenService.getToken(
                    state.callId!,
                  );
                  await _engine?.renewToken(agoraData['token']!);
                } catch (e) {
                  debugPrint("Failed to renew token: $e");
                }
              },
          onError: (ErrorCodeType err, String msg) {
            debugPrint('[Agora Error] $err : $msg');
            if (!_isDisposed) {
              state = state.copyWith(errorMsg: "Agora Error: ${err.name}");
            }
          },
        ),
      );

      if (isVideo) {
        await _engine!.enableVideo();

        // ── Low Data Mode Optimization ──
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult.contains(ConnectivityResult.mobile)) {
          // Cellular connection: use low data mode (480p, 15fps)
          debugPrint(
            "Cellular network detected. Enabling Low Data Mode for video.",
          );
          await _engine!.setVideoEncoderConfiguration(
            const VideoEncoderConfiguration(
              dimensions: VideoDimensions(width: 480, height: 640),
              frameRate: 15,
              bitrate: 400,
              orientationMode: OrientationMode.orientationModeAdaptive,
            ),
          );
        } else {
          // Wi-Fi or other: use high quality (720p, 30fps)
          await _engine!.setVideoEncoderConfiguration(
            const VideoEncoderConfiguration(
              dimensions: VideoDimensions(width: 720, height: 1280),
              frameRate: 30,
              bitrate: 1130,
              orientationMode: OrientationMode.orientationModeAdaptive,
            ),
          );
        }
        await _engine!.enableDualStreamMode(enabled: true);
        await _engine!.startPreview();
      } else {
        await _engine!.disableVideo();
      }

      await _engine!.enableAudio();

      // ── AI Noise Cancellation ── enabled by default for premium voice quality
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );
      await _engine!.setAINSMode(
        enabled: true,
        mode: AudioAinsMode.ainsModeBalanced,
      );

      // Note: we've already handled startPreview() inside the isVideo block above.

      state = state.copyWith(
        isInitialized: true,
        isInitializing: false,
        callStatusText: 'Connecting...',
      );

      await _engine!.joinChannel(
        token: dynamicToken,
        channelId: channelId,
        uid: 0,
        options: ChannelMediaOptions(
          publishCameraTrack: isVideo,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideo,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (e) {
      debugPrint("Agora Setup Error: $e");
      if (!_isDisposed) {
        state = state.copyWith(
          isInitializing: false,
          errorMsg: "Failed to connect: $e",
        );
      }
    }
  }

  void _startDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.isCallActive) {
        state = state.copyWith(
          callDurationSeconds: state.callDurationSeconds + 1,
        );
      } else {
        timer.cancel();
      }
    });
  }

  void toggleMicrophone() {
    if (_engine == null) return;
    final newMutedState = !state.isMuted;
    _engine!.muteLocalAudioStream(newMutedState);
    state = state.copyWith(isMuted: newMutedState);
    HapticFeedback.lightImpact();
  }

  void toggleCamera() {
    if (_engine == null) return;
    final newVideoOffState = !state.isVideoOff;
    _engine!.muteLocalVideoStream(newVideoOffState);
    state = state.copyWith(isVideoOff: newVideoOffState);
    HapticFeedback.lightImpact();
  }

  void pauseMedia() {
    if (_engine == null) return;
    _engine!.muteLocalAudioStream(true);
    if (!state.isVideoOff) {
      _engine!.muteLocalVideoStream(true);
    }
  }

  void resumeMedia() {
    if (_engine == null) return;
    if (!state.isMuted) {
      _engine!.muteLocalAudioStream(false);
    }
    if (!state.isVideoOff) {
      _engine!.muteLocalVideoStream(false);
    }
  }

  void switchCamera() {
    if (_engine == null) return;
    _engine!.switchCamera();
  }

  Future<void> toggleBlur() async {
    if (_engine == null) return;
    final newBlurState = !state.isBlurEnabled;

    VirtualBackgroundSource source = const VirtualBackgroundSource(
      backgroundSourceType: BackgroundSourceType.backgroundBlur,
      blurDegree: BackgroundBlurDegree.blurDegreeHigh,
    );

    await _engine!.enableVirtualBackground(
      enabled: newBlurState,
      backgroundSource: source,
      segproperty: const SegmentationProperty(
        modelType: SegModelType.segModelAi,
      ),
    );

    state = state.copyWith(isBlurEnabled: newBlurState);
    HapticFeedback.lightImpact();
  }

  void setSpeakerphone(bool enable) {
    if (_engine == null) return;
    _engine!.setEnableSpeakerphone(enable);
  }

  Future<void> endCallSession({
    bool updateStatus = true,
    String? targetStatus,
  }) async {
    if (!state.isCallActive && _engine == null) return;

    // Clear video upgrade request if any
    if (state.callId != null) {
      FirebaseFirestore.instance
          .collection('calls')
          .doc(state.callId)
          .update({'videoUpgradeRequest': FieldValue.delete()})
          .catchError((_) {});
    }

    // ── Haptic: Call Ended ──────────────────────────────────────────────────
    HapticFeedback.heavyImpact();

    final currentCallId = state.callId;
    final durationSeconds = state.callDurationSeconds;
    final remoteUid = state.remoteUid;

    _cleanupTimersAndSubscriptions();
    _isDisposed = true;

    if (_engine != null) {
      try {
        await Future.wait([
          _engine!.leaveChannel(),
          _engine!.stopPreview(),
        ]).timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Error leaving Agora channel: $e");
      }

      try {
        await _engine!.release();
      } catch (e) {
        debugPrint("Error releasing Agora engine: $e");
      } finally {
        _engine = null;
      }
    }

    if (currentCallId != null && currentCallId.isNotEmpty && updateStatus) {
      final repository = CallRepository(FirebaseFirestore.instance);
      final finalStatus =
          targetStatus ?? (remoteUid == null ? 'caller_ended' : 'ended');
      final currentUser = FirebaseAuth.instance.currentUser;
      final name = currentUser?.displayName;

      await repository.endCallTransaction(
        callId: currentCallId,
        status: finalStatus,
        endedBy: currentUser?.uid,
        endedByName: name,
        duration: durationSeconds,
      );
    }

    FlutterCallkitIncoming.endAllCalls().catchError((_) {});

    // Always navigate back to HomeScreen, cleaning stale call routes from the stack
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentState != null &&
          navigatorKey.currentState!.mounted) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    });

    // Reset global state
    state = AgoraState();
  }

  void _cleanupTimersAndSubscriptions() {
    _callingTimer?.cancel();
    _callingTimer = null;
    _ringingTimer?.cancel();
    _ringingTimer = null;
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
    _callStatusSubscription?.cancel();
    _callStatusSubscription = null;
  }

  @override
  void dispose() {
    _cleanupTimersAndSubscriptions();
    if (_engine != null) {
      try {
        _engine!.leaveChannel();
        _engine!.stopPreview();
        _engine!.release();
      } catch (_) {}
      _engine = null;
    }
    super.dispose();
  }

  // ─── Flagship Features ─────────────────────────────────────────────────────

  /// Requests to upgrade an audio call to a video call
  Future<void> requestVideoUpgrade() async {
    if (state.callId == null || state.isVideo) return;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(state.callId)
        .update({'videoUpgradeRequest': currentUid});
  }

  /// Accepts an incoming video upgrade request
  Future<void> acceptVideoUpgrade() async {
    if (state.callId == null || _engine == null) return;

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(state.callId)
        .update({'videoUpgradeRequest': FieldValue.delete(), 'isVideo': true});

    state = state.copyWith(
      isVideo: true,
      clearVideoUpgradeRequest: true,
      isVideoOff: false,
    );

    // Enable video engine and start preview
    await _engine!.enableVideo();
    await _engine!.startPreview();

    // We update local stream to unmuted, remote handles itself via their accept/enableVideo
    await _engine!.muteLocalVideoStream(false);
  }

  /// Rejects an incoming video upgrade request
  Future<void> rejectVideoUpgrade() async {
    if (state.callId == null) return;
    await FirebaseFirestore.instance
        .collection('calls')
        .doc(state.callId)
        .update({'videoUpgradeRequest': FieldValue.delete()});
    state = state.copyWith(clearVideoUpgradeRequest: true);
  }

  /// Toggles native screen sharing capability (Android foreground service required)
  Future<void> toggleScreenShare() async {
    if (_engine == null || !state.isVideo) return;

    final newScreenShareState = !state.isScreenSharing;

    if (newScreenShareState) {
      // Start screen capture
      await _engine!.startScreenCapture(
        const ScreenCaptureParameters2(
          captureAudio: false,
          captureVideo: true,
          videoParams: ScreenVideoParameters(
            dimensions: VideoDimensions(width: 720, height: 1280),
            frameRate: 15,
            bitrate: 1000,
          ),
        ),
      );

      // Stop local camera to save bandwidth and avoid dual-channel complexity
      await _engine!.stopPreview();

      // Switch publisher stream to screen
      await _engine!.updateChannelMediaOptions(
        const ChannelMediaOptions(
          publishCameraTrack: false,
          publishScreenCaptureVideo: true,
          publishScreenCaptureAudio: false,
        ),
      );
    } else {
      // Stop screen capture
      await _engine!.stopScreenCapture();

      // Revert to camera
      await _engine!.updateChannelMediaOptions(
        const ChannelMediaOptions(
          publishCameraTrack: true,
          publishScreenCaptureVideo: false,
          publishScreenCaptureAudio: false,
        ),
      );
      if (!state.isVideoOff) {
        await _engine!.startPreview();
      }
    }

    state = state.copyWith(isScreenSharing: newScreenShareState);
    HapticFeedback.lightImpact();
  }
}

// Global Provider (NOT autoDispose)
final agoraServiceProvider = StateNotifierProvider<AgoraService, AgoraState>((
  ref,
) {
  return AgoraService();
});
