import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';

class LoginHeader extends StatelessWidget {
  const LoginHeader({super.key, this.logoHeight = 44.0, this.trailing});

  final double logoHeight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedHeight = logoHeight.clamp(1.0, 200.0);
    final logo = SvgPicture.asset(
      ThingsboardImage.thingsBoardWithTitle,
      height: clampedHeight,
      colorFilter: ColorFilter.mode(theme.colorScheme.primary, BlendMode.srcIn),
      semanticsLabel: 'ThingsBoard Logo',
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailing != null)
          Align(alignment: Alignment.centerRight, child: trailing!),
        SizedBox(
          height: clampedHeight,
          child: FittedBox(fit: BoxFit.scaleDown, child: logo),
        ),
      ],
    );
  }
}
