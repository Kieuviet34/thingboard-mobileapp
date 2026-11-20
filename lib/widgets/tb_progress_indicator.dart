import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';

class TbProgressIndicator extends StatefulWidget {
  const TbProgressIndicator({super.key, this.size = 36.0, this.valueColor});
  final double size;
  final Color? valueColor;

  @override
  State<TbProgressIndicator> createState() => _TbProgressIndicatorState();
}

class _TbProgressIndicatorState extends State<TbProgressIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
    );
    _rotation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.valueColor ?? theme.colorScheme.secondary;
    return Stack(
      children: [
        SvgPicture.asset(
          ThingsboardImage.thingsboardCenter,
          height: widget.size,
          width: widget.size,
          colorFilter: ColorFilter.mode(
            theme.colorScheme.secondary,
            BlendMode.srcIn,
          ),
        ),
        AnimatedBuilder(
          animation: _rotation,
          child: SvgPicture.asset(
            ThingsboardImage.thingsboardOuter,
            height: widget.size,
            width: widget.size,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
          builder: (BuildContext context, Widget? child) {
            return Transform.rotate(
              angle: _rotation.value * pi * 2,
              child: child,
            );
          },
        ),
      ],
    );
  }
}
