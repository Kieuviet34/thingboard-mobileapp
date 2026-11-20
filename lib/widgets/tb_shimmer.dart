import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';

/// GPU-safe shimmer placeholder honoring [MediaQuery.disableAnimationsOf].
class TbShimmer extends StatefulWidget {
  const TbShimmer({
    super.key,
    this.width,
    required this.height,
    this.borderRadius,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<TbShimmer> createState() => _TbShimmerState();
}

class _TbShimmerState extends State<TbShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _opacity = Tween<double>(
      begin: 0.45,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final box = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: widget.borderRadius ?? DesignTokens.borderRadiusMedium,
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) {
      return ExcludeSemantics(child: box);
    }

    return ExcludeSemantics(
      child: FadeTransition(opacity: _opacity, child: box),
    );
  }
}

/// Minimal skeleton list matching 3-line IoT entity rows.
class TbShimmerList extends StatelessWidget {
  const TbShimmerList({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          Container(
            padding: DesignTokens.cardPadding,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: DesignTokens.borderRadiusLarge,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: TbShimmer(height: 16)),
                    SizedBox(width: DesignTokens.spacing12),
                    TbShimmer(width: 72, height: 22),
                  ],
                ),
                SizedBox(height: DesignTokens.spacing8),
                TbShimmer(width: 160, height: 12),
                SizedBox(height: DesignTokens.spacing8),
                Row(
                  children: [
                    TbShimmer(width: 84, height: 26),
                    SizedBox(width: DesignTokens.spacing8),
                    TbShimmer(width: 84, height: 26),
                  ],
                ),
              ],
            ),
          ),
          if (i < itemCount - 1) const SizedBox(height: DesignTokens.spacing8),
        ],
      ],
    );
  }
}
