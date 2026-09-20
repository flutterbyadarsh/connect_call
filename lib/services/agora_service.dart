import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'agora_token_service.dart';

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
  });

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
      activeSpeakerUid: clearActiveSpeaker == true ? null : (activeSpeakerUid ?? this.activeSpeakerUid),
    );
  }
}

class AgoraService extends StateNotifier<AgoraState> {
  AgoraService() : super(AgoraState());

  RtcEngine? _engine;
  bool _isDisposed = false;
  String? _currentCallId;
  DateTime? _callStartTime;

  RtcEngine? get engine => _engine;

  Future<void> initAgora({
    required String channelId,
    required bool isVideo,
  }) async {
    if (state.isInitializing || state.isInitialized) return; // Prevent duplicate init
    _isDisposed = false;
    _currentCallId = channelId;

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
        return;
      }

      // Fetch token and appId first, so we don't rely on local environment variables if they are missing
      final agoraData = await AgoraTokenService.getToken(channelId);
      final dynamicToken = agoraData['token']!;
      final backendAppId = agoraData['appId']!;

      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: backendAppId.isNotEmpty ? backendAppId : _kAgoraAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      await _engine!.enableAudioVolumeIndication(interval: 200, smooth: 3, reportVad: true);

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint("local user ${connection.localUid} joined");
            _callStartTime = DateTime.now();
            _engine?.setEnableSpeakerphone(state.isVideoOff == false); // Enable speaker if video call
            if (!_isDisposed) state = state.copyWith(isJoined: true, clearError: true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint("remote user $remoteUid joined");
            if (!_isDisposed) state = state.copyWith(remoteUid: remoteUid, clearError: true);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint("remote user $remoteUid left channel");
            if (!_isDisposed) {
              state = state.copyWith(clearRemoteUid: true, isCallEndedByRemote: true);
            }
          },
          onUserMuteVideo: (RtcConnection connection, int remoteUid, bool muted) {
            debugPrint("remote user $remoteUid muted video: $muted");
            if (!_isDisposed) state = state.copyWith(remoteVideoMuted: muted);
          },
          onNetworkQuality: (RtcConnection connection, int remoteUid, QualityType txQuality, QualityType rxQuality) {
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
                state = state.copyWith(networkQuality: quality, networkColor: color);
              }
            }
          },
          onAudioVolumeIndication: (RtcConnection connection, List<AudioVolumeInfo> speakers, int totalVolume, int extra) {
            if (_isDisposed) return;
            if (speakers.isNotEmpty) {
              // Find the speaker with the highest volume
              AudioVolumeInfo activeSpeaker = speakers.reduce((curr, next) => (curr.volume ?? 0) > (next.volume ?? 0) ? curr : next);
              if ((activeSpeaker.volume ?? 0) > 5) { // Threshold to prevent breathing noise
                state = state.copyWith(activeSpeakerUid: activeSpeaker.uid == 0 ? null : activeSpeaker.uid);
              } else {
                state = state.copyWith(clearActiveSpeaker: true);
              }
            } else {
              state = state.copyWith(clearActiveSpeaker: true);
            }
          },
          onTokenPrivilegeWillExpire: (RtcConnection connection, String token) async {
            if (_isDisposed || _currentCallId == null) return;
            debugPrint("Token will expire soon. Renewing...");
            try {
              final agoraData = await AgoraTokenService.getToken(_currentCallId!);
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
      } else {
        await _engine!.disableVideo();
      }
      
      await _engine!.enableAudio();
      
      if (isVideo) {
        await _engine!.startPreview();
      }

      state = state.copyWith(isInitialized: true, isInitializing: false);

      await _engine!.joinChannel(
        token: dynamicToken,
        channelId: channelId,
        uid: 0,
        options: ChannelMediaOptions(
          publishCameraTrack: isVideo,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideo,
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

  void toggleMicrophone() {
    if (_engine == null) return;
    final newMutedState = !state.isMuted;
    _engine!.muteLocalAudioStream(newMutedState);
    state = state.copyWith(isMuted: newMutedState);
  }

  void toggleCamera() {
    if (_engine == null) return;
    final newVideoOffState = !state.isVideoOff;
    _engine!.muteLocalVideoStream(newVideoOffState);
    state = state.copyWith(isVideoOff: newVideoOffState);
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
      segproperty: const SegmentationProperty(modelType: SegModelType.segModelAi),
    );
    
    state = state.copyWith(isBlurEnabled: newBlurState);
  }

  void setSpeakerphone(bool enable) {
    if (_engine == null) return;
    _engine!.setEnableSpeakerphone(enable);
  }

  Future<void> leaveChannel() async {
    if (_engine != null) {
      await _engine!.leaveChannel();
      state = state.copyWith(isJoined: false, clearRemoteUid: true);
    }
  }

  Future<void> disposeEngine(String callId) async {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_engine != null) {
      await _engine!.leaveChannel();
      await _engine!.stopPreview();
      await _engine!.release();
      _engine = null;
    }
    
    try {
      final duration = _callStartTime != null ? DateTime.now().difference(_callStartTime!).inSeconds : 0;
      await FirebaseFirestore.instance.collection('calls').doc(callId).update({
        'status': 'ended',
        'duration': duration,
      });
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'isBusy': false});
      }
    } catch (e) {
      debugPrint("Failed to update call status to ended: $e");
    }
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _engine?.leaveChannel();
      _engine?.stopPreview();
      _engine?.release();
      if (_currentCallId != null) {
        final duration = _callStartTime != null ? DateTime.now().difference(_callStartTime!).inSeconds : 0;
        FirebaseFirestore.instance.collection('calls').doc(_currentCallId).update({
          'status': 'ended',
          'duration': duration,
        }).catchError((e) => debugPrint("Failed to update status on dispose: $e"));
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'isBusy': false}).catchError((e) => debugPrint("Failed to update user busy status on dispose: $e"));
        }
      }
    }
    super.dispose();
  }
}

final agoraServiceProvider = StateNotifierProvider.autoDispose<AgoraService, AgoraState>((ref) {
  return AgoraService();
});
