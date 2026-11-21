import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';

/// Geometry of the floating nav bar at one (possibly fractional) position.
@immutable
class TbNavFrame {
  const TbNavFrame({
    required this.cellLeft,
    required this.indicatorLeft,
    required this.indicatorWidth,
  });

  /// Left edge of every destination's tap cell.
  final List<double> cellLeft;
  final double indicatorLeft;
  final double indicatorWidth;
}

/// Pure layout math for `TbFloatingNavBar` (no widgets, fully unit-testable).
///
/// Every destination owns a fixed-size cell. The selected destination
/// reserves extra room for its label to the right of the icon; the cells are
/// then spread evenly. Because all sizes are constant, animating between two
/// selections only moves things (paint-time transforms), never relayouts.
@immutable
class TbNavMetrics {
  const TbNavMetrics({
    required this.width,
    required this.labelWidths,
    this.hPad = DesignTokens.spacing8,
    this.cellWidth = DesignTokens.navCellWidth,
    this.minCellWidth = DesignTokens.minTouchTarget,
    this.indicatorSize = DesignTokens.navIndicatorSize,
    this.labelPadEnd = DesignTokens.navLabelPadEnd,
  });

  final double width;
  final List<double> labelWidths;
  final double hPad;
  final double cellWidth;
  final double minCellWidth;
  final double indicatorSize;
  final double labelPadEnd;

  int get count => labelWidths.length;
  double get _available => math.max(0, width - 2 * hPad);

  /// Extra width a destination needs on top of its cell to show its label.
  double _block(int index) => labelWidths[index] + labelPadEnd;

  double get _widestBlock =>
      labelWidths.map((w) => w + labelPadEnd).reduce(math.max);

  /// Labels are shown only when every cell can still be a full touch target.
  bool get showLabel => count * minCellWidth + _widestBlock <= _available;

  /// Cell width is constant across selections so tap targets never jump.
  double get cell {
    final room = showLabel ? _available - _widestBlock : _available;
    return math.min(cellWidth, room / count);
  }

  double _blockFor(int selected) => showLabel ? _block(selected) : 0;

  /// Frame when destination [selected] (integer) is active.
  TbNavFrame frameFor(int selected) {
    final block = _blockFor(selected);
    final leftover = math.max(0.0, _available - count * cell - block);
    final gap = leftover / (count + 1);
    var x = hPad + gap;
    final lefts = <double>[];
    for (var i = 0; i < count; i++) {
      lefts.add(x);
      x += cell + (i == selected ? block : 0) + gap;
    }
    return TbNavFrame(
      cellLeft: lefts,
      indicatorLeft: lefts[selected] + (cell - indicatorSize) / 2,
      indicatorWidth: indicatorSize + block,
    );
  }

  /// Frame at fractional [position] (0..count-1), interpolating neighbours.
  TbNavFrame frameAt(double position) {
    final clamped = position.clamp(0.0, (count - 1).toDouble());
    final lo = clamped.floor();
    final hi = math.min(lo + 1, count - 1);
    final t = clamped - lo;
    final a = frameFor(lo);
    final b = frameFor(hi);
    double mix(double x, double y) => x + (y - x) * t;
    return TbNavFrame(
      cellLeft: [
        for (var i = 0; i < count; i++) mix(a.cellLeft[i], b.cellLeft[i]),
      ],
      indicatorLeft: mix(a.indicatorLeft, b.indicatorLeft),
      indicatorWidth: mix(a.indicatorWidth, b.indicatorWidth),
    );
  }

  /// Left edge of destination [index]'s label when its cell is at [cellLeft].
  double labelLeft(double cellLeft) =>
      cellLeft + (cell - indicatorSize) / 2 + indicatorSize;

  /// 1 when [position] is exactly on [index], falling to 0 one step away.
  static double weight(double position, int index) =>
      (1 - (position - index).abs()).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is TbNavMetrics &&
      other.width == width &&
      listEquals(other.labelWidths, labelWidths) &&
      other.hPad == hPad &&
      other.cellWidth == cellWidth &&
      other.minCellWidth == minCellWidth &&
      other.indicatorSize == indicatorSize &&
      other.labelPadEnd == labelPadEnd;

  @override
  int get hashCode => Object.hash(
    width,
    Object.hashAll(labelWidths),
    hPad,
    cellWidth,
    minCellWidth,
    indicatorSize,
    labelPadEnd,
  );
}
