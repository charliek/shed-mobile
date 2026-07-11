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
  // Created exactly ONCE, eagerly in initState. SingleTickerProviderStateMixin
  // vends a single ticker for the State's lifetime: constructing a second
  // AnimationController (the old code did, whenever `animate` flipped back to
  // true — e.g. a session's activity badge pulsing working → idle → working)
  // trips createTicker's '_dependents.isEmpty' assert and red-screens the
  // tree. Animate changes now just repeat()/stop() this one controller.
  // (Eager, not a `late final` initializer: that would lazily create the
  // controller on first touch — which for a never-animated dot is dispose(),
  // where createTicker's TickerMode ancestor lookup is illegal.)
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.animate) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.animate == old.animate) return;
    if (widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0; // rest fully opaque while static
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
    if (!widget.animate) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(_controller),
      child: dot,
    );
  }
}

/// A status pill: a tone-tinted background with a dot + mono label (the design's
/// session-status badge).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.tone,
    required this.label,
    this.pulse = false,
  });

  final ShedStatusTone tone;
  final String label;

  /// Whether the dot pulses (e.g. an actively-`working` activity badge).
  final bool pulse;

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
          StatusDot(tone: tone, size: 6, animate: pulse),
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
