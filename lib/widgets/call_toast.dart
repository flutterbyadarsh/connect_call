import 'package:flutter/material.dart';
import '../main.dart';

enum CallToastType { info, ended, declined, missed, busy, waiting }

/// Premium floating toast for call state changes.
/// Renders a styled card at the top of the screen via [ScaffoldMessenger].
class CallToast {
  // ── Palette ───────────────────────────────────────────────────────────────
  static const Color _colorEnded = Color(0xFF374151); // slate-700
  static const Color _colorDeclined = Color(0xFFDC2626); // red-600
  static const Color _colorMissed = Color(0xFFD97706); // amber-600
  static const Color _colorBusy = Color(0xFFB45309); // amber-700
  static const Color _colorInfo = Color(0xFF2563EB); // blue-600

  static Color _colorFor(CallToastType type) {
    return switch (type) {
      CallToastType.ended => _colorEnded,
      CallToastType.declined => _colorDeclined,
      CallToastType.missed => _colorMissed,
      CallToastType.busy => _colorBusy,
      CallToastType.waiting => _colorInfo,
      CallToastType.info => _colorInfo,
    };
  }

  static IconData _iconFor(CallToastType type) {
    return switch (type) {
      CallToastType.ended => Icons.call_end_rounded,
      CallToastType.declined => Icons.phone_disabled_rounded,
      CallToastType.missed => Icons.phone_missed_rounded,
      CallToastType.busy => Icons.phone_locked_rounded,
      CallToastType.waiting => Icons.call_rounded,
      CallToastType.info => Icons.info_outline_rounded,
    };
  }

  /// Shows a premium floating toast. Safe to call from any isolate context.
  static void show({
    required String message,
    CallToastType type = CallToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    final color = _colorFor(type);
    final icon = _iconFor(type);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: duration,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: EdgeInsets.zero,
          content: _CallToastContent(
            message: message,
            color: color,
            icon: icon,
          ),
        ),
      );
  }
}

class _CallToastContent extends StatefulWidget {
  final String message;
  final Color color;
  final IconData icon;

  const _CallToastContent({
    required this.message,
    required this.color,
    required this.icon,
  });

  @override
  State<_CallToastContent> createState() => _CallToastContentState();
}

class _CallToastContentState extends State<_CallToastContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
