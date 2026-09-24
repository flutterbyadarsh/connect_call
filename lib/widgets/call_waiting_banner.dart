import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/call_repository.dart';
import '../screens/call/incoming_call_screen.dart';
import '../main.dart';

/// Manages a non-intrusive top-of-screen call-waiting banner via [OverlayEntry].
/// Does NOT push any route — renders above all existing screens without
/// interrupting the active call session.
class CallWaitingBannerController {
  CallWaitingBannerController._();
  static final CallWaitingBannerController instance =
      CallWaitingBannerController._();

  OverlayEntry? _entry;
  Timer? _autoDeclineTimer;
  bool _isShowing = false;

  bool get isShowing => _isShowing;

  /// Shows the call-waiting banner for [callerName] with [callId].
  /// Automatically declines after [autoDeclineSecs] seconds (default 30).
  void show({
    required String callId,
    required String callerName,
    required String callerPic,
    required String agoraChannelId,
    required bool isVideo,
    int autoDeclineSecs = 30,
  }) {
    if (_isShowing) return; // Don't stack banners
    _isShowing = true;

    _entry = OverlayEntry(
      builder: (_) => _CallWaitingBannerWidget(
        callId: callId,
        callerName: callerName,
        callerPic: callerPic,
        agoraChannelId: agoraChannelId,
        isVideo: isVideo,
        onDismiss: () => dismiss(),
      ),
    );

    // Insert above everything in the overlay
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      _isShowing = false;
      return;
    }
    overlay.insert(_entry!);

    // Auto-decline after timeout
    _autoDeclineTimer = Timer(Duration(seconds: autoDeclineSecs), () async {
      if (_isShowing) {
        await _declineWaitingCall(callId);
        dismiss();
      }
    });
  }

  void dismiss() {
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = null;
    _entry?.remove();
    _entry = null;
    _isShowing = false;
  }

  static Future<void> _declineWaitingCall(String callId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String? name = user?.displayName;
      if (user != null && (name == null || name.isEmpty)) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        name = doc.data()?['name'];
      }
      await CallRepository(FirebaseFirestore.instance).endCallTransaction(
        callId: callId,
        status: 'rejected',
        endedBy: user?.uid,
        endedByName: name,
      );
    } catch (e) {
      debugPrint('[CallWaitingBanner] _declineWaitingCall error: $e');
    }
  }
}

// ── Private Widget ─────────────────────────────────────────────────────────

class _CallWaitingBannerWidget extends StatefulWidget {
  final String callId;
  final String callerName;
  final String callerPic;
  final String agoraChannelId;
  final bool isVideo;
  final VoidCallback onDismiss;

  const _CallWaitingBannerWidget({
    required this.callId,
    required this.callerName,
    required this.callerPic,
    required this.agoraChannelId,
    required this.isVideo,
    required this.onDismiss,
  });

  @override
  State<_CallWaitingBannerWidget> createState() =>
      _CallWaitingBannerWidgetState();
}

class _CallWaitingBannerWidgetState extends State<_CallWaitingBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _animateOut(VoidCallback then) async {
    if (_isDismissing) return;
    setState(() => _isDismissing = true);
    await _ctrl.reverse();
    then();
  }

  Future<void> _onDecline() async {
    await _animateOut(() async {
      await CallWaitingBannerController._declineWaitingCall(widget.callId);
      widget.onDismiss();
    });
  }

  Future<void> _onAccept(BuildContext ctx) async {
    // Industry standard: confirm ending the current call to accept the waiting one
    final confirmed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.call_rounded, color: Color(0xFF2563EB)),
            const SizedBox(width: 10),
            const Text(
              'Switch Call?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Your current call will end to answer ${widget.callerName}\'s call. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Keep current'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _animateOut(() {
      widget.onDismiss();
      // Push IncomingCallScreen for the waiting call via the global navigator
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              callId: widget.callId,
              callerName: widget.callerName,
              callerPic: widget.callerPic,
              agoraChannelId: widget.agoraChannelId,
              isVideo: widget.isVideo,
            ),
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                elevation: 12,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1D4ED8).withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      // Pulsing call icon
                      _PulsingIcon(isVideo: widget.isVideo),
                      const SizedBox(width: 12),
                      // Caller info
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.callerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Incoming ${widget.isVideo ? 'video' : 'audio'} call • waiting',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Decline
                      _ActionButton(
                        icon: Icons.call_end_rounded,
                        color: const Color(0xFFDC2626),
                        onTap: _onDecline,
                        tooltip: 'Decline',
                      ),
                      const SizedBox(width: 8),
                      // Accept
                      _ActionButton(
                        icon: widget.isVideo
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        color: const Color(0xFF16A34A),
                        onTap: () => _onAccept(context),
                        tooltip: 'Answer',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _PulsingIcon extends StatefulWidget {
  final bool isVideo;
  const _PulsingIcon({required this.isVideo});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30, width: 1.5),
        ),
        child: Icon(
          widget.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
