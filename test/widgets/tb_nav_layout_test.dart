import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/widgets/nav/tb_nav_layout.dart';

TbNavMetrics _metrics(double width) =>
    TbNavMetrics(width: width, labelWidths: const [40, 48, 52, 36]);

void main() {
  group('TbNavMetrics layout', () {
    test('every cell is a >= 48dp touch target whenever labels are shown', () {
      for (final width in [296.0, 320.0, 360.0, 390.0, 430.0, 480.0]) {
        final m = _metrics(width);
        expect(m.showLabel, isTrue, reason: 'width $width');
        expect(m.cell, greaterThanOrEqualTo(DesignTokens.minTouchTarget));
      }
    });

    test(
      'labels are dropped (not squeezed) when 48dp cells + label do not fit',
      () {
        final narrow = _metrics(240);
        expect(narrow.showLabel, isFalse);
        // Icons still share the whole bar equally.
        final frame = narrow.frameFor(0);
        expect(frame.indicatorWidth, narrow.indicatorSize);
      },
    );

    test('cells never overlap and stay inside the bar for every selection', () {
      for (final width in [296.0, 360.0, 390.0, 480.0]) {
        final m = _metrics(width);
        for (var selected = 0; selected < m.count; selected++) {
          final f = m.frameFor(selected);
          for (var i = 0; i < m.count - 1; i++) {
            final reserved =
                m.cell + (i == selected ? m.labelWidths[i] + m.labelPadEnd : 0);
            expect(
              f.cellLeft[i + 1],
              greaterThanOrEqualTo(f.cellLeft[i] + reserved - 0.001),
              reason: 'w=$width sel=$selected cell $i overlaps $i+1',
            );
          }
          final last = m.count - 1;
          final lastRight =
              f.cellLeft[last] +
              m.cell +
              (selected == last ? m.labelWidths[last] + m.labelPadEnd : 0);
          expect(f.cellLeft.first, greaterThanOrEqualTo(m.hPad));
          expect(lastRight, lessThanOrEqualTo(width - m.hPad + 0.001));
        }
      }
    });

    test('indicator wraps the selected icon and the label that follows it', () {
      final m = _metrics(390);
      final f = m.frameFor(2);
      final iconCenter = f.cellLeft[2] + m.cell / 2;
      expect(f.indicatorLeft, closeTo(iconCenter - m.indicatorSize / 2, 0.001));
      expect(
        f.indicatorWidth,
        closeTo(m.indicatorSize + m.labelWidths[2] + m.labelPadEnd, 0.001),
      );
      // Label starts right after the 40dp icon zone, i.e. to the RIGHT of the icon.
      expect(
        m.labelLeft(f.cellLeft[2]),
        closeTo(f.indicatorLeft + m.indicatorSize, 0.001),
      );
      expect(m.labelLeft(f.cellLeft[2]), greaterThan(iconCenter + 12));
    });

    test('fractional position interpolates between neighbouring frames', () {
      final m = _metrics(390);
      final a = m.frameFor(0);
      final b = m.frameFor(1);
      final mid = m.frameAt(0.5);
      expect(
        mid.indicatorLeft,
        closeTo((a.indicatorLeft + b.indicatorLeft) / 2, 0.001),
      );
      expect(
        mid.indicatorWidth,
        closeTo((a.indicatorWidth + b.indicatorWidth) / 2, 0.001),
      );
      expect(
        mid.cellLeft[3],
        closeTo((a.cellLeft[3] + b.cellLeft[3]) / 2, 0.001),
      );
    });

    test('position is clamped to the valid range', () {
      final m = _metrics(390);
      expect(m.frameAt(-3).indicatorLeft, m.frameFor(0).indicatorLeft);
      expect(m.frameAt(99).indicatorLeft, m.frameFor(3).indicatorLeft);
    });

    test('weight is 1 on the index and fades to 0 one step away', () {
      expect(TbNavMetrics.weight(2, 2), 1);
      expect(TbNavMetrics.weight(2.5, 2), closeTo(0.5, 1e-9));
      expect(TbNavMetrics.weight(2, 0), 0);
      expect(TbNavMetrics.weight(2, 3), 0);
    });
  });
}
