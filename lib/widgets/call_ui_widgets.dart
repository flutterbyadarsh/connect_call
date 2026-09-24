import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EncryptionBadge
// Glassmorphism pill displayed on both call screens.
// ─────────────────────────────────────────────────────────────────────────────

class EncryptionBadge extends StatelessWidget {
  const EncryptionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, color: Colors.white60, size: 11),
              const SizedBox(width: 5),
              const Text(
                'End-to-end encrypted',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RippleAvatar
// Shows a pulsing concentric-ring animation behind the caller's avatar while
// the call is in "Ringing" state.  Rings stop and a green border replaces them
// the moment the remote user joins (isConnected = true).
// ─────────────────────────────────────────────────────────────────────────────

class RippleAvatar extends StatefulWidget {
  final Uint8List? imageBytes;

  /// True when the call status is "Ringing" (remote not yet joined).
  final bool isRinging;

  /// True when remoteUid is non-null (call connected).
  final bool isConnected;

  const RippleAvatar({
    super.key,
    this.imageBytes,
    required this.isRinging,
    required this.isConnected,
  });

  @override
  State<RippleAvatar> createState() => _RippleAvatarState();
}

class _RippleAvatarState extends State<RippleAvatar>
    with TickerProviderStateMixin {
  // Two independently-offset ripple controllers for staggered timing.
  late final AnimationController _ctrl1;
  late final AnimationController _ctrl2;
  // Green ring glow on connection.
  late final AnimationController _connectCtrl;
  late final Animation<double> _connectBorder;

  @override
  void initState() {
    super.initState();

    _ctrl1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _ctrl2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _connectCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _connectBorder = CurvedAnimation(
      parent: _connectCtrl,
      curve: Curves.easeOut,
    );

    if (widget.isRinging) _startRipples();
    if (widget.isConnected) _connectCtrl.value = 1.0;
  }

  void _startRipples() {
    _ctrl1.repeat();
    // Start second ring 700ms later for natural stagger.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _ctrl2.repeat();
    });
  }

  void _stopRipples() {
    _ctrl1.stop();
    _ctrl2.stop();
  }

  @override
  void didUpdateWidget(RippleAvatar old) {
    super.didUpdateWidget(old);

    if (widget.isRinging && !old.isRinging) _startRipples();
    if (!widget.isRinging && old.isRinging) _stopRipples();

    if (widget.isConnected && !old.isConnected) {
      _stopRipples();
      _connectCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl1.dispose();
    _ctrl2.dispose();
    _connectCtrl.dispose();
    super.dispose();
  }

  Widget _rippleRing(AnimationController ctrl, double maxExtra) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final v = ctrl.value;
        return Container(
          width: 120 + maxExtra * v,
          height: 120 + maxExtra * v,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: (1.0 - v) * 0.45),
              width: 2.0,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple rings (visible only while ringing)
          if (widget.isRinging) ...[
            _rippleRing(_ctrl1, 80),
            _rippleRing(_ctrl2, 55),
          ],

          // Avatar with animated border
          AnimatedBuilder(
            animation: _connectBorder,
            builder: (_, child) {
              final borderColor = widget.isConnected
                  ? Color.lerp(
                      Colors.white,
                      Colors.greenAccent,
                      _connectBorder.value,
                    )!
                  : Colors.white;
              final borderWidth = widget.isConnected
                  ? 2.0 + _connectBorder.value * 1.5
                  : 2.0;
              return Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white24,
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: widget.isConnected
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.withValues(
                              alpha: 0.35 * _connectBorder.value,
                            ),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: ClipOval(child: child),
              );
            },
            child: widget.imageBytes != null
                ? Image.memory(
                    widget.imageBytes!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.person, size: 60, color: Colors.white),
                  )
                : const Icon(Icons.person, size: 60, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CallStatusText
// Smooth fade-transition from status string → green live timer the instant
// the remote user joins the channel.
// ─────────────────────────────────────────────────────────────────────────────

class CallStatusText extends StatefulWidget {
  final bool isConnected;
  final bool isInitialized;
  final String statusText;
  final String formattedDuration;
  final String? errorMsg;

  const CallStatusText({
    super.key,
    required this.isConnected,
    required this.isInitialized,
    required this.statusText,
    required this.formattedDuration,
    this.errorMsg,
  });

  @override
  State<CallStatusText> createState() => _CallStatusTextState();
}

class _CallStatusTextState extends State<CallStatusText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (widget.isConnected) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(CallStatusText old) {
    super.didUpdateWidget(old);
    if (widget.isConnected && !old.isConnected) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Error state
    if (widget.errorMsg != null) {
      return Text(
        widget.errorMsg!,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    // Initialising spinner
    if (!widget.isInitialized && widget.errorMsg == null) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(color: Colors.white60, strokeWidth: 2),
      );
    }

    // Connected — live timer fades in
    if (widget.isConnected) {
      return FadeTransition(
        opacity: _fade,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timer_outlined,
              color: Colors.greenAccent,
              size: 16,
            ),
            const SizedBox(width: 5),
            Text(
              widget.formattedDuration,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      );
    }

    // Default status text (Calling… / Ringing)
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        widget.statusText,
        key: ValueKey(widget.statusText),
        style: const TextStyle(color: Colors.white70, fontSize: 16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HapticControlButton
// Identical to the private _ControlButton widgets, but with built-in
// HapticFeedback.lightImpact on every tap — shared between both call screens.
// ─────────────────────────────────────────────────────────────────────────────

class HapticControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final Color? iconColor;
  final bool isActive;
  final double size;
  final double iconSize;
  final String? tooltip;

  const HapticControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.iconColor,
    this.isActive = false,
    this.size = 56,
    this.iconSize = 28,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn = GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
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

    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}
