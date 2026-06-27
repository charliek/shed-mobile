import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';

/// A small status dot in the tone's saturated color, optionally pulsing (the
/// design's `animation:pulse` for transient states like "starting").
class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    required this.tone,
    this.size = 9,
    this.animate = false,
  });

  final ShedStatusTone tone;
  final double size;
  final bool animate;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _startPulse();
  }

  void _startPulse() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && _controller == null) {
      _startPulse();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: context.shed.toneDot(widget.tone),
        shape: BoxShape.circle,
      ),
    );
    final c = _controller;
    if (c == null) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(c),
      child: dot,
    );
  }
}

/// A status pill: a tone-tinted background with a dot + mono label (the design's
/// session-status badge).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.tone, required this.label});

  final ShedStatusTone tone;
  final String label;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: shed.toneBg(tone),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(tone: tone, size: 6),
          const SizedBox(width: 5),
          Text(
            label,
            style: monoStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: shed.toneFg(tone),
            ),
          ),
        ],
      ),
    );
  }
}
