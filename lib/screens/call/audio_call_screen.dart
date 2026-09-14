import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_theme.dart';
import 'dart:async';

const String appId = "fd5f9d592fc54c8d9623c27892c2a64b"; 
const String token = "007eJxTYFh+bbfIpYKbvhaW3BdeS4bPDxHftPjM7XDTSQ3XbO5Ff3yvwJCWYppmmWJqaZSWbGqSbJFiaWZknGxkbmFplGyUaGaS9HjzsqyGQEaGx19PMzIyQCCIz8FQklpckpyYk8PAAACN1SSZ"; 

class AudioCallScreen extends StatefulWidget {
  final String callerName;
  const AudioCallScreen({super.key, required this.callerName});

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  bool _isMuted = false;
  bool _isSpeaker = false;
  
  int? _remoteUid;
  bool _localUserJoined = false;
  RtcEngine? _engine;
  bool _isEngineInitialized = false;
  Timer? _missedCallTimer;

  @override
  void initState() {
    super.initState();
    initAgora();
  }

  Future<void> initAgora() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permission Denied'),
            content: const Text('Microphone permission is required to make this call.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      }
      return;
    }

    // Missed call timer (45 seconds)
    _missedCallTimer = Timer(const Duration(seconds: 45), () async {
      if (_remoteUid == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call Missed')));
        try {
          await FirebaseFirestore.instance.collection('calls').doc(widget.callerName).update({'status': 'missed'});
        } catch (e) {
          debugPrint("Failed to update status to missed: $e");
        }
        if (mounted) Navigator.pop(context);
      }
    });

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
          if (mounted) {
            setState(() {
              _remoteUid = remoteUid;
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call Connected')));
            _missedCallTimer?.cancel();
          }
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint("remote user $remoteUid left channel");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call ended')));
            Navigator.pop(context);
          }
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint('[Agora Error] $err : $msg');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Agora Error: ${err.name}')));
          }
        },
      ),
    );

    try {
      // Disable video for audio-only call
      await _engine!.disableVideo();
      await _engine!.enableAudio();

      await _engine!.joinChannel(
        token: token,
        channelId: 'testcall',
        uid: 0,
        options: const ChannelMediaOptions(
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          publishCameraTrack: false,
          autoSubscribeVideo: false,
        ),
      );
      
      // Use earpiece by default for audio calls. MUST be called after joining.
      await _engine!.setEnableSpeakerphone(false);
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User rejected the call')));
          Navigator.pop(context);
        } else if (status == 'ended' && _remoteUid == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call Ended')));
          Navigator.pop(context);
        }
      }
    });
  }

  @override
  void dispose() {
    _missedCallTimer?.cancel();
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

  void _toggleSpeaker() {
    setState(() {
      _isSpeaker = !_isSpeaker;
    });
    _engine?.setEnableSpeakerphone(_isSpeaker);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEngineInitialized) {
      return Scaffold(
        backgroundColor: Colors.grey.shade900,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Initializing microphone...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            const Text(
              'Secure Audio Call',
              style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _remoteUid != null ? 'Connected' : 'Calling...',
              style: const TextStyle(fontSize: 18, color: Colors.white70),
            ),
            Expanded(
              child: Center(
                child: CircleAvatar(
                  radius: 80,
                  backgroundColor: AppTheme.primaryColor,
                  child: Text(
                    widget.callerName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 60, color: Colors.white),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(bottom: 40, top: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    isActive: _isMuted,
                    onTap: _toggleMicrophone,
                  ),
                  _ControlButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    iconColor: Colors.white,
                    onTap: () => Navigator.pop(context),
                  ),
                  _ControlButton(
                    icon: _isSpeaker ? Icons.volume_up : Icons.volume_off,
                    isActive: _isSpeaker,
                    onTap: _toggleSpeaker,
                  ),
                ],
              ),
            ),
          ],
        ),
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color ?? (isActive ? Colors.white : Colors.white24),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 32,
          color: iconColor ?? (isActive ? Colors.black : Colors.white),
        ),
      ),
    );
  }
}
