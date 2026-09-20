import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../services/agora_service.dart';
import '../../services/auth_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class AudioCallScreen extends ConsumerStatefulWidget {
  final String callerName; // This is now the Firestore callId (UUID)
  final String agoraChannelId;

  const AudioCallScreen({super.key, required this.callerName, required this.agoraChannelId});

  @override
  ConsumerState<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends ConsumerState<AudioCallScreen> {
  Timer? _missedCallTimer;
  StreamSubscription? _callStatusSubscription;
  bool _canPop = false;
  
  String _remoteName = 'Connecting...';
  String _remotePic = '';
  Uint8List? _remotePicBytes;
  
  Timer? _callDurationTimer;
  int _callDurationSeconds = 0;
  
  String get _formattedDuration {
    final minutes = (_callDurationSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  void _initCall() {
    // Initialize Agora non-blocking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agoraServiceProvider.notifier).initAgora(
        channelId: widget.agoraChannelId,
        isVideo: false,
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
                   if (_remotePic.isNotEmpty) {
                     try {
                       _remotePicBytes = base64Decode(_remotePic.split(',').last);
                     } catch (e) {
                       _remotePicBytes = null;
                     }
                   } else {
                     _remotePicBytes = null;
                   }
                 });
              }
           }
        }
      }
    });
  }

  @override
  void dispose() {
    _missedCallTimer?.cancel();
    _callStatusSubscription?.cancel();
    _callDurationTimer?.cancel();
    super.dispose();
  }

  void _startDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
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
      if (next.remoteUid != null && (previous?.remoteUid == null)) {
        _startDurationTimer();
      }
    });
    
    final isConnected = agoraState.remoteUid != null;
    final statusText = agoraState.errorMsg ?? (isConnected ? _formattedDuration : 'Calling...');

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _endCall();
      },
      child: Scaffold(
        body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primaryColor.withOpacity(0.8),
              Colors.black87,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 50),
              
              // Caller Info
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white24,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: ClipOval(
                        child: _remotePicBytes != null
                            ? Image.memory(
                                _remotePicBytes!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (c, e, s) => const Icon(Icons.person, size: 60, color: Colors.white),
                              )
                            : const Icon(Icons.person, size: 60, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _remoteName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!agoraState.isInitialized && agoraState.errorMsg == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                      )
                    else
                      Text(
                        statusText,
                        style: TextStyle(
                          color: agoraState.errorMsg != null ? Colors.red : Colors.white70,
                          fontSize: 16,
                          fontWeight: agoraState.errorMsg != null ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Controls
              Container(
                padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 40),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(40),
                    topRight: Radius.circular(40),
                  ),
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
                      icon: Icons.call_end,
                      color: Colors.red,
                      iconColor: Colors.white,
                      size: 64,
                      iconSize: 32,
                      onTap: () => _endCall(),
                    ),
                    _SpeakerButton(agoraNotifier: agoraNotifier),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

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
    return _ControlButton(
      icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
      isActive: _isSpeaker,
      onTap: () {
        setState(() {
          _isSpeaker = !_isSpeaker;
        });
        widget.agoraNotifier.setSpeakerphone(_isSpeaker);
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final Color? iconColor;
  final bool isActive;
  final double size;
  final double iconSize;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.color,
    this.iconColor,
    this.isActive = false,
    this.size = 56,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? (isActive ? Colors.white : Colors.white24),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor ?? (isActive ? Colors.black : Colors.white),
        ),
      ),
    );
  }
}
