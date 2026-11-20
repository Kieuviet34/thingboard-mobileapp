import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';

class OAuthButton extends StatelessWidget {
  const OAuthButton({
    super.key,
    required this.logo,
    required this.onTap,
    this.title,
    this.semanticLabel,
  });

  final Widget logo;
  final VoidCallback onTap;
  final String? title;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: semanticLabel ?? title ?? 'OAuth sign in',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            DesignTokens.minTouchTarget,
            DesignTokens.buttonHeightLarge,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacing16,
            vertical: DesignTokens.spacing12,
          ),
        ),
        onPressed: onTap,
        child: Row(
          spacing: DesignTokens.spacing8,
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            if (title != null)
              Flexible(
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
