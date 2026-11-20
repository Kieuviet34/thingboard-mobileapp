import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';

/// Compact circular initials avatar styled via Material 3 [ColorScheme] and [TextTheme].
class UserInfoAvatarWidget extends StatelessWidget {
  const UserInfoAvatarWidget({
    required this.shortName,
    this.color,
    this.foregroundColor,
    this.size = 32,
    this.semanticLabel,
    super.key,
  });

  final String shortName;
  final Color? color;
  final Color? foregroundColor;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final trimmed = shortName.trim();
    final initials = trimmed.isEmpty
        ? 'U'
        : (trimmed.length > 2 ? trimmed.substring(0, 2) : trimmed)
              .toUpperCase();

    final background = color ?? scheme.primaryContainer;
    final foreground =
        foregroundColor ??
        (color == null ? scheme.onPrimaryContainer : scheme.onPrimary);

    final avatar = Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(DesignTokens.spacing4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: DesignTokens.borderRadiusRound,
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          initials,
          maxLines: 1,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: foreground,
          ),
        ),
      ),
    );

    if (semanticLabel != null && semanticLabel!.isNotEmpty) {
      return Semantics(label: semanticLabel, child: avatar);
    }
    return ExcludeSemantics(child: avatar);
  }
}
