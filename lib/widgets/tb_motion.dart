import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';

/// GPU-safe staggered list entrance (`Transform.translate` + `Opacity`).
///
/// Capped to `<= 320ms` total delay and skipped immediately when
/// [MediaQuery.disableAnimationsOf] is `true`.
class TbStaggeredEntry extends StatefulWidget {
  const TbStaggeredEntry({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<TbStaggeredEntry> createState() => _TbStaggeredEntryState();
}

class _TbStaggeredEntryState extends State<TbStaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DesignTokens.motionMedium,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
      return;
    }
    final delayMs = math.min(widget.index * 36, 320);
    if (delayMs <= 0) {
      _controller.forward();
    } else {
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Tactile GPU-safe press scale (`1.0 -> 0.98`) wrapper.
class TbPressScale extends StatefulWidget {
  const TbPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  State<TbPressScale> createState() => _TbPressScaleState();
}

class _TbPressScaleState extends State<TbPressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DesignTokens.motionFast,
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final ink = InkWell(
      borderRadius: widget.borderRadius ?? DesignTokens.borderRadiusLarge,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null || disableAnimations
          ? null
          : (_) => _controller.forward(),
      onTapUp: widget.onTap == null || disableAnimations
          ? null
          : (_) => _controller.reverse(),
      onTapCancel: widget.onTap == null || disableAnimations
          ? null
          : () => _controller.reverse(),
      child: widget.child,
    );

    if (disableAnimations) return ink;
    return ScaleTransition(scale: _scale, child: ink);
  }
}

/// Subtle live telemetry / WebSocket pulse indicator dot.
class LivePulseDot extends StatefulWidget {
  const LivePulseDot({
    super.key,
    required this.active,
    this.size = 10.0,
    this.semanticLabel,
  });

  final bool active;
  final double size;
  final String? semanticLabel;

  @override
  State<LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = Tween<double>(
      begin: 0.55,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant LivePulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (!widget.active || disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColors = TbStatusColors.of(context);
    final dotColor = widget.active ? statusColors.online : statusColors.offline;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final coreDot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
    );

    final content = SizedBox(
      width: widget.size * 2,
      height: widget.size * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.active && !disableAnimations)
            FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          coreDot,
        ],
      ),
    );

    if (widget.semanticLabel != null && widget.semanticLabel!.isNotEmpty) {
      return Semantics(label: widget.semanticLabel, child: content);
    }
    return ExcludeSemantics(child: content);
  }
}

/// Lightweight GPU-friendly telemetry sparkline chart wrapped in [RepaintBoundary].
class TbSparklineChart extends StatelessWidget {
  const TbSparklineChart({
    super.key,
    required this.values,
    this.height = 56.0,
    this.color,
    this.semanticLabel,
  });

  final List<double> values;
  final double height;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = color ?? scheme.primary;

    final chart = RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(
          painter: _SparklinePainter(
            values: values,
            lineColor: lineColor,
            gridColor: scheme.outlineVariant,
          ),
        ),
      ),
    );

    if (semanticLabel != null && semanticLabel!.isNotEmpty) {
      return Semantics(label: semanticLabel, image: true, child: chart);
    }
    return ExcludeSemantics(child: chart);
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;

    final baselinePaint = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      baselinePaint,
    );

    var minVal = values.first;
    var maxVal = values.first;
    for (final v in values) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }
    final range = (maxVal - minVal).abs();
    final padY = 6.0;
    final usableHeight = math.max(1.0, size.height - padY * 2);

    final linePath = Path();
    final fillPath = Path();
    final count = values.length;

    for (var i = 0; i < count; i++) {
      final x = count == 1 ? size.width / 2 : (i / (count - 1)) * size.width;
      final norm = range < 1e-9 ? 0.5 : (values[i] - minVal) / range;
      final y = size.height - padY - norm * usableHeight;
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(count == 1 ? size.width / 2 : size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.24),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);

    if (count > 0) {
      final lastNorm = range < 1e-9 ? 0.5 : (values.last - minVal) / range;
      final lastX = count == 1 ? size.width / 2 : size.width - 2;
      final lastY = size.height - padY - lastNorm * usableHeight;
      canvas.drawCircle(Offset(lastX, lastY), 3.2, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.values.length != values.length ||
      !_listEquals(oldDelegate.values, values);

  bool _listEquals(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
