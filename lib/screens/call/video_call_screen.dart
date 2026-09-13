import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

const String appId = "fd5f9d592fc54c8d9623c27892c2a64b"; 
const String token = "007eJxTYFh+bbfIpYKbvhaW3BdeS4bPDxHftPjM7XDTSQ3XbO5Ff3yvwJCWYppmmWJqaZSWbGqSbJFiaWZknGxkbmFplGyUaGaS9HjzsqyGQEaGx19PMzIyQCCIz8FQklpckpyYk8PAAACN1SSZ"; 

class VideoCallScreen extends StatefulWidget {
  final String callerName; // This is the Channel ID (Contact UID)
  const VideoCallScreen({super.key, required this.callerName});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  int? _remoteUid;
  bool _localUserJoined = false;
  RtcEngine? _engine;
  bool _isEngineInitialized = false;

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isEmulator = false;

  String _networkQuality = 'Good';
  Color _networkColor = Colors.green;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _checkDeviceAndInitAgora();
  }

  Future<void> _checkDeviceAndInitAgora() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      _isEmulator = !androidInfo.isPhysicalDevice;
      debugPrint("Device is emulator: $_isEmulator");
    } else {
      _isEmulator = false; // iOS physical or simulator (Texture view works on iOS simulator)
    }
    await initAgora();
  }

  Future<void> initAgora() async {
    final statuses = await [Permission.microphone, Permission.camera].request();
    if (statuses[Permission.microphone] != PermissionStatus.granted || statuses[Permission.camera] != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camera and Microphone permissions are required')));
        Navigator.pop(context);
      }
      return;
    }

    // Create and initialize engine
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    if (mounted) {
      setState(() {
        _isEngineInitialized = true;
      });
    }

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("local user ${connection.localUid} joined");
          setState(() {
            _localUserJoined = true;
          });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("remote user $remoteUid joined");
          setState(() {
            _remoteUid = remoteUid;
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint("remote user $remoteUid left channel");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call ended')));
            Navigator.pop(context);
          }
        },
        onNetworkQuality: (RtcConnection connection, int remoteUid, QualityType txQuality, QualityType rxQuality) {
          if (remoteUid == 0) {
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
            
            if (_networkQuality != quality) {
              setState(() {
                _networkQuality = quality;
                _networkColor = color;
              });
            }
          }
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint('[Agora Error] $err : $msg');
          if (mounted) {
            setState(() {
              _errorMsg = "Agora Error: ${err.name}";
            });
          }
        },
      ),
    );

    try {
      await _engine!.enableVideo();
      await _engine!.enableAudio();
      await _engine!.startPreview();

      // Join channel
      await _engine!.joinChannel(
        token: token,
        channelId: 'testcall',
        uid: 0,
        options: const ChannelMediaOptions(
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
      
      // Set speakerphone MUST be called after joining channel or starting audio
      await _engine!.setEnableSpeakerphone(true);
    } catch (e) {
      debugPrint("Agora Setup Error: $e");
    }

    // Listen to call status changes from receiver (e.g. declined or ended)
    FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callerName)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        final status = doc.data()?['status'] as String?;
        if (status == 'declined') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call declined')));
          Navigator.pop(context);
        } else if (status == 'ended' && _remoteUid == null) {
          // If receiver ends it before joining
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call ended')));
          Navigator.pop(context);
        }
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _dispose();
  }

  Future<void> _dispose() async {
    if (_engine != null) {
      await _engine!.leaveChannel();
      await _engine!.release();
    }
    try {
      await FirebaseFirestore.instance.collection('calls').doc(widget.callerName).update({
        'status': 'ended',
      });
    } catch (e) {
      debugPrint("Failed to update call status to ended: $e");
    }
  }

  void _toggleMicrophone() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _engine?.muteLocalAudioStream(_isMuted);
  }

  void _toggleCamera() {
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
    _engine?.muteLocalVideoStream(_isVideoOff);
  }

  void _switchCamera() {
    _engine?.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEngineInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Initializing camera...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video
          Center(
            child: _remoteUid != null
                ? AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: _engine!,
                      canvas: VideoCanvas(uid: _remoteUid),
                      connection: const RtcConnection(channelId: 'testcall'),
                      useFlutterTexture: _isEmulator,
                    ),
                  )
                : Text(
                    _errorMsg ?? 'Waiting for other user to join...',
                    style: TextStyle(color: _errorMsg != null ? Colors.red : Colors.white, fontWeight: _errorMsg != null ? FontWeight.bold : FontWeight.normal),
                    textAlign: TextAlign.center,
                  ),
          ),
          
          // App Bar Area Overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Secure Video Call',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.signal_cellular_alt, color: _networkColor, size: 16),
                            const SizedBox(width: 4),
                            Text('Network: $_networkQuality', style: TextStyle(color: _networkColor, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ), // Closes Expanded
                ],
              ),
            ),
          ),
          
          // Local Camera Preview Overlay
          Positioned(
            right: 16,
            bottom: 120,
            child: SizedBox(
              width: 100,
              height: 150,
              child: !_isVideoOff
                  ? AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                        useFlutterTexture: _isEmulator,
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade700,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Center(child: Icon(Icons.videocam_off, color: Colors.white54)),
                    ),
            ),
          ),
          
          // Floating Control Bar
          Positioned(
            left: 16,
            right: 16,
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    isActive: _isMuted,
                    onTap: _toggleMicrophone,
                  ),
                  _ControlButton(
                    icon: Icons.flip_camera_ios,
                    onTap: _switchCamera,
                  ),
                  _ControlButton(
                    icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
                    isActive: _isVideoOff,
                    onTap: _toggleCamera,
                  ),
                  _ControlButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    iconColor: Colors.white,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final Color? iconColor;
  final bool isActive;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.color,
    this.iconColor,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color ?? (isActive ? Colors.white : Colors.white24),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 28,
          color: iconColor ?? (isActive ? Colors.black : Colors.white),
        ),
      ),
    );
  }
}
