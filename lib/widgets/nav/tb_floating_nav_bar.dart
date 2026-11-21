import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/nav/tb_nav_layout.dart';

/// One destination of [TbFloatingNavBar].
@immutable
class TbNavDestination {
  const TbNavDestination({
    required this.label,
    required this.icon,
    this.badgeCount = 0,
    this.badgeSemantics = '',
  });

  final String label;
  final TbIconKind icon;
  final int badgeCount;

  /// Word read after the count, e.g. "unread" or "active".
  final String badgeSemantics;
}

/// Fully rounded glass navigation pill.
///
/// Tapping a destination slides an indicator to it and reveals its label to
/// the **right of the icon**. Motion is GPU-safe: the indicator is a repainted
/// `CustomPainter`, icons/labels move with `Transform.translate`/`Opacity`, so
/// no layout runs while animating. Honors `MediaQuery.disableAnimations`
/// (instant) and `highContrast` (opaque, no blur). On windows too narrow to
/// keep 48dp cells plus a label, labels are hidden (tooltip + semantics stay).
class TbFloatingNavBar extends StatefulWidget {
  const TbFloatingNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(destinations.length >= 2),
       assert(selectedIndex >= 0 && selectedIndex < destinations.length);

  final List<TbNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<TbFloatingNavBar> createState() => _TbFloatingNavBarState();
}

class _TbFloatingNavBarState extends State<TbFloatingNavBar>
    with SingleTickerProviderStateMixin {
  static const double _labelSlide = 12;
  static const double _unboundedWidthFallback = 360;

  late final AnimationController _controller;
  late Animation<double> _position;
  CurvedAnimation? _curve;
  bool _reduceMotion = false;

  /// Previously selected index: its label fades out while the target's fades
  /// in. Tabs the indicator merely passes over never show a label.
  late int _previousIndex = widget.selectedIndex;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DesignTokens.motionSlow,
    );
    _position = AlwaysStoppedAnimation<double>(widget.selectedIndex.toDouble());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce && !_reduceMotion) {
      _goTo(widget.selectedIndex, instant: true);
    }
    _reduceMotion = reduce;
  }

  @override
  void didUpdateWidget(TbFloatingNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _previousIndex = oldWidget.selectedIndex;
      _goTo(widget.selectedIndex, instant: _reduceMotion);
    }
  }

  void _goTo(int target, {required bool instant}) {
    final from = _position.value;
    _controller.stop();
    _curve?.dispose();
    _curve = null;
    if (instant) {
      _position = AlwaysStoppedAnimation<double>(target.toDouble());
      return;
    }
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _curve = curve;
    _position = Tween<double>(
      begin: from,
      end: target.toDouble(),
    ).animate(curve);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _curve?.dispose();
    _controller.dispose();
    super.dispose();
  }

  double _measure(
    String text,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble() + 2;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final labelStyle =
        (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        );

    // Nav labels stay legible without letting 2x text blow the 64dp bar.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final direction = Directionality.of(context);
          final metrics = TbNavMetrics(
            width: constraints.hasBoundedWidth
                ? constraints.maxWidth
                : _unboundedWidthFallback,
            labelWidths: [
              for (final d in widget.destinations)
                _measure(d.label, labelStyle, scaler, direction),
            ],
          );
          return _buildPill(context, scheme, metrics, labelStyle, highContrast);
        },
      ),
    );
  }

  Widget _buildPill(
    BuildContext context,
    ColorScheme scheme,
    TbNavMetrics metrics,
    TextStyle labelStyle,
    bool highContrast,
  ) {
    final pill = Material(
      key: const Key('floating-nav-pill'),
      color: scheme.surfaceContainerHigh.withValues(
        alpha: highContrast ? 1.0 : DesignTokens.navGlassOpacity,
      ),
      elevation: DesignTokens.elevationNone,
      shape: StadiumBorder(
        side: BorderSide(
          color: scheme.outlineVariant.withValues(
            alpha: highContrast ? 1 : 0.7,
          ),
        ),
      ),
      child: SizedBox(
        height: DesignTokens.navBarHeight,
        width: metrics.width,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _IndicatorPainter(
                  metrics: metrics,
                  position: _position,
                  color: scheme.primaryContainer,
                ),
              ),
            ),
            // Own transparent Material: ink (ripple, hover, keyboard focus) is
            // painted by the nearest Material *before* its children, so on the
            // pill's Material it would sit under the opaque indicator.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedBuilder(
                  animation: _position,
                  builder: (context, _) =>
                      _buildItems(context, scheme, metrics, labelStyle),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // StadiumBorder clip keeps both ends fully round at any height.
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: StadiumBorder()),
      child: highContrast
          ? pill
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: DesignTokens.navBlurSigma,
                sigmaY: DesignTokens.navBlurSigma,
              ),
              child: pill,
            ),
    );
  }

  Widget _buildItems(
    BuildContext context,
    ColorScheme scheme,
    TbNavMetrics metrics,
    TextStyle labelStyle,
  ) {
    final position = _position.value;
    final frame = metrics.frameAt(position);
    final children = <Widget>[];

    for (var i = 0; i < widget.destinations.length; i++) {
      final weight = TbNavMetrics.weight(position, i);
      // The selected tab's highlighted pill also covers its label, so the
      // label area is tappable too (re-selecting returns to the tab's root).
      final labelHit = metrics.showLabel && i == widget.selectedIndex
          ? metrics.labelWidths[i] + metrics.labelPadEnd
          : 0.0;
      children.add(
        _shifted(
          dx: frame.cellLeft[i],
          child: SizedBox(
            width: metrics.cell + labelHit,
            height: DesignTokens.navBarHeight,
            child: Row(
              children: [
                SizedBox(
                  width: metrics.cell,
                  child: _buildCell(i, weight, scheme),
                ),
                if (labelHit > 0)
                  SizedBox(
                    width: labelHit,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap: () => widget.onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (metrics.showLabel) {
      for (var i = 0; i < widget.destinations.length; i++) {
        final weight = TbNavMetrics.weight(position, i);
        final opacity = Curves.easeOut.transform(
          ((weight - 0.35) / 0.65).clamp(0.0, 1.0),
        );
        final isRelevant = i == widget.selectedIndex || i == _previousIndex;
        if (!isRelevant || opacity <= 0.01) continue;
        children.add(
          _shifted(
            dx:
                metrics.labelLeft(frame.cellLeft[i]) -
                (1 - opacity) * _labelSlide,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: opacity,
                  child: SizedBox(
                    width: metrics.labelWidths[i],
                    child: Text(
                      widget.destinations[i].label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: labelStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return Stack(fit: StackFit.expand, children: children);
  }

  /// Paint-time shift (no relayout): content sits at the left, then translates.
  Widget _shifted({required double dx, required Widget child}) {
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }

  Widget _buildCell(int index, double weight, ColorScheme scheme) {
    final destination = widget.destinations[index];
    final selected = widget.selectedIndex == index;
    final color = Color.lerp(
      scheme.onSurfaceVariant,
      scheme.onPrimaryContainer,
      weight,
    )!;

    Widget icon = TbIcon(
      destination.icon,
      size: DesignTokens.iconMedium,
      color: color,
      filled: weight > 0.5,
    );
    if (destination.badgeCount > 0) {
      icon = Badge(
        label: Text(
          destination.badgeCount > 99 ? '99+' : '${destination.badgeCount}',
        ),
        backgroundColor: scheme.error,
        textColor: scheme.onError,
        child: icon,
      );
    }

    final semanticLabel = destination.badgeCount > 0
        ? '${destination.label}, ${destination.badgeCount} '
                  '${destination.badgeSemantics}'
              .trim()
        : destination.label;

    return Semantics(
      excludeSemantics: true,
      container: true,
      button: true,
      enabled: true,
      selected: selected,
      label: semanticLabel,
      onTap: () => widget.onSelected(index),
      child: Tooltip(
        message: destination.label,
        child: InkResponse(
          onTap: () => widget.onSelected(index),
          containedInkWell: false,
          highlightShape: BoxShape.circle,
          radius: DesignTokens.minTouchTarget / 2,
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({
    required this.metrics,
    required this.position,
    required this.color,
  }) : super(repaint: position);

  final TbNavMetrics metrics;
  final Animation<double> position;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = metrics.frameAt(position.value);
    final height = metrics.indicatorSize;
    final rect = Rect.fromLTWH(
      frame.indicatorLeft,
      (size.height - height) / 2,
      frame.indicatorWidth,
      height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(height / 2)),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) =>
      old.metrics != metrics || old.color != color || old.position != position;
}
