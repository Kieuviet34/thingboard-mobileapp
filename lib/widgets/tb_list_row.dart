import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';

/// Shared compact list row for every list page: title, one meta line, optional
/// leading icon and trailing action. Minimum 48dp height, single-line text.
class TbListRow extends StatelessWidget {
  const TbListRow({
    super.key,
    required this.title,
    this.meta,
    this.leading,
    this.trailing,
    this.onTap,
    this.contentPadding,
  });

  final String title;
  final String? meta;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final metaText = meta?.trim() ?? '';
    final insideSectionCard = TbSectionCardScope.isInside(context);
    final resolvedPadding =
        contentPadding ??
        (insideSectionCard
            ? const EdgeInsets.symmetric(vertical: DesignTokens.spacing8)
            : const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacing16,
                vertical: DesignTokens.spacing12,
              ));

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: DesignTokens.minTouchTarget),
      child: Padding(
        padding: resolvedPadding,
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: DesignTokens.spacing12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignTokens.spacing2,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (metaText.isNotEmpty)
                    Text(
                      metaText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: DesignTokens.spacing8),
              trailing!,
            ],
          ],
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: insideSectionCard
                  ? DesignTokens.borderRadiusMedium
                  : null,
              child: content,
            ),
    );
  }
}
