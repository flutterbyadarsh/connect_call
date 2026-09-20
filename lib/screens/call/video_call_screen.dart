import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:async';
import 'package:pip_view/pip_view.dart';
import '../../services/agora_service.dart';
import '../../services/auth_service.dart';
import '../home/home_screen.dart';

class VideoCallScreen extends ConsumerStatefulWidget {
  final String callerName; // This is now the Firestore callId (UUID)
  final String agoraChannelId;

  const VideoCallScreen({super.key, required this.callerName, required this.agoraChannelId});

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> with WidgetsBindingObserver {
  bool _isEmulator = false;
  Timer? _missedCallTimer;
  Key _videoKey = UniqueKey();
  StreamSubscription? _callStatusSubscription;
  bool _canPop = false;
  
  String _remoteName = 'Connecting...';
  String _remotePic = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCall();
  }

  Future<void> _initCall() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      _isEmulator = !androidInfo.isPhysicalDevice;
      debugPrint("Device is emulator: $_isEmulator");
    } else {
      _isEmulator = false;
    }

    // Initialize Agora non-blocking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agoraServiceProvider.notifier).initAgora(
        channelId: widget.agoraChannelId,
        isVideo: true,
      );
    });

    // Missed call timer (45 seconds)
    _missedCallTimer = Timer(const Duration(seconds: 45), () async {
      final state = ref.read(agoraServiceProvider);
      if (state.remoteUid == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call Missed')));
        try {
          await FirebaseFirestore.instance.collection('calls').doc(widget.callerName).update({'status': 'missed'});
        } catch (e) {
          debugPrint("Failed to update status to missed: $e");
        }
        if (mounted) Navigator.pop(context);
      }
    });

    // Listen to call status changes from receiver (e.g. declined or ended)
    _callStatusSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callerName)
        .snapshots(includeMetadataChanges: true)
        .listen((doc) {
      if (doc.metadata.isFromCache) return; // Prevent popping immediately from local cache
      
      if (doc.exists && mounted) {
        final status = doc.data()?['status'] as String?;
        final state = ref.read(agoraServiceProvider);
        
        if (status == 'declined') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call Declined')));
          Navigator.pop(context);
        } else if (status == 'ended') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call Ended')));
          Navigator.pop(context);
        } else if (status == 'accepted') {
          _missedCallTimer?.cancel();
        }
        
        final data = doc.data();
        if (data != null) {
           final currentUid = ref.read(authServiceProvider).currentUser?.uid;
           if (currentUid != null) {
              String newRemoteName = _remoteName;
              String newRemotePic = _remotePic;
              
              if (data['callerId'] == currentUid) {
                 newRemoteName = data['receiverName'] ?? 'Unknown';
                 newRemotePic = data['receiverPic'] ?? '';
              } else {
                 newRemoteName = data['callerName'] ?? 'Unknown';
                 newRemotePic = data['callerPic'] ?? '';
              }
              
              if (newRemoteName != _remoteName || newRemotePic != _remotePic) {
                 setState(() {
                   _remoteName = newRemoteName;
                   _remotePic = newRemotePic;
                 });
              }
           }
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When app resumes, force recreate the SurfaceView to fix black/missing screen issues on Android
      if (mounted) {
        setState(() {
          _videoKey = UniqueKey();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _missedCallTimer?.cancel();
    _callStatusSubscription?.cancel();
    
    super.dispose();
  }

  void _endCall() {
    if (_canPop) return;
    
    _callStatusSubscription?.cancel();
    final notifier = ref.read(agoraServiceProvider.notifier);
    
    // Run in background without awaiting to prevent UI freeze
    notifier.disposeEngine(widget.callerName);
    
    if (mounted) {
      setState(() {
        _canPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final agoraState = ref.watch(agoraServiceProvider);
    final agoraNotifier = ref.read(agoraServiceProvider.notifier);

    ref.listen<AgoraState>(agoraServiceProvider, (previous, next) {
      if (next.isCallEndedByRemote && !(previous?.isCallEndedByRemote ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call ended by remote user')));
        _endCall();
      }
    });

    if (!agoraState.isInitialized && agoraState.errorMsg == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Connecting securely...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _endCall();
      },
      child: PIPView(
        builder: (context, isFloating) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
          // Remote Video
          Center(
            child: agoraState.remoteUid != null
                ? Container(
                    decoration: BoxDecoration(
                      border: agoraState.activeSpeakerUid == agoraState.remoteUid 
                          ? Border.all(color: Colors.greenAccent, width: 4) 
                          : null,
                    ),
                    child: (agoraState.remoteVideoMuted
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.videocam_off, color: Colors.white54, size: 80),
                              SizedBox(height: 16),
                              Text(
                                'Camera turned off',
                                style: TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            ],
                          )
                        : AgoraVideoView(
                            key: ValueKey('remote_${_videoKey.hashCode}'),
                            controller: VideoViewController.remote(
                              rtcEngine: agoraNotifier.engine!,
                              canvas: VideoCanvas(uid: agoraState.remoteUid!),
                              connection: RtcConnection(channelId: widget.agoraChannelId),
                              useFlutterTexture: _isEmulator,
                            ),
                          )),
                  )
                : Text(
                    agoraState.errorMsg ?? 'Calling...',
                    style: TextStyle(
                      color: agoraState.errorMsg != null ? Colors.red : Colors.white,
                      fontWeight: agoraState.errorMsg != null ? FontWeight.bold : FontWeight.normal,
                    ),
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
                        Text(
                          _remoteName,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                            Icon(Icons.signal_cellular_alt, color: agoraState.networkColor, size: 16),
                            const SizedBox(width: 4),
                            Text('Network: ${agoraState.networkQuality}', style: TextStyle(color: agoraState.networkColor, fontSize: 12, fontWeight: FontWeight.bold)),
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
          
          // Local Camera Preview Overlay (Hide in PiP)
          if (!isFloating)
            Positioned(
            right: 16,
            bottom: 120,
            child: SizedBox(
              width: 100,
              height: 150,
              child: !agoraState.isVideoOff && agoraNotifier.engine != null
                  ? AgoraVideoView(
                      key: ValueKey('local_${_videoKey.hashCode}'),
                      controller: VideoViewController(
                        rtcEngine: agoraNotifier.engine!,
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
          
          // Floating Control Bar (Hide in PiP)
          if (!isFloating)
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
                    icon: agoraState.isMuted ? Icons.mic_off : Icons.mic,
                    isActive: agoraState.isMuted,
                    onTap: () => agoraNotifier.toggleMicrophone(),
                  ),
                  _ControlButton(
                    icon: Icons.flip_camera_ios,
                    onTap: () => agoraNotifier.switchCamera(),
                  ),
                  _ControlButton(
                    icon: agoraState.isVideoOff ? Icons.videocam_off : Icons.videocam,
                    isActive: agoraState.isVideoOff,
                    onTap: () => agoraNotifier.toggleCamera(),
                  ),
                  _ControlButton(
                    icon: Icons.blur_on,
                    isActive: agoraState.isBlurEnabled,
                    onTap: () => agoraNotifier.toggleBlur(),
                  ),
                  _ControlButton(
                    icon: Icons.picture_in_picture_alt,
                    onTap: () {
                      PIPView.of(context)?.presentBelow(const HomeScreen());
                    },
                  ),
                  _ControlButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    iconColor: Colors.white,
                    onTap: () => _endCall(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }));
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
