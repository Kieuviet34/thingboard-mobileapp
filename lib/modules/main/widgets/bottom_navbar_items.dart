import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

class BottomNavbarItems extends StatelessWidget {
  const BottomNavbarItems({
    required this.label,
    required this.icon,
    required this.selectedTextStyle,
    required this.unSelectedTextStyle,
    required this.onTap,
    required this.index,
    this.tbIconKind,
    this.currentIndex,
    this.lineIndicatorWidth = 3,
    this.showAdditionalIcon = false,
    this.additionalIcon,
    super.key,
  });

  final String label;
  final IconData icon;
  final TbIconKind? tbIconKind;
  final int? currentIndex;
  final int index;
  final ValueChanged<int> onTap;
  final double lineIndicatorWidth;
  final TextStyle selectedTextStyle;
  final TextStyle unSelectedTextStyle;
  final bool showAdditionalIcon;
  final Widget? additionalIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = currentIndex == index;
    final iconColor = isSelected ? scheme.primary : scheme.onSurfaceVariant;

    return SafeArea(
      left: false,
      right: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: DesignTokens.minTouchTarget,
              minHeight: DesignTokens.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacing8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tbIconKind != null)
                        TbIcon(
                          tbIconKind!,
                          size: DesignTokens.iconMedium,
                          color: iconColor,
                          filled: isSelected,
                        )
                      else
                        Icon(
                          icon,
                          size: DesignTokens.iconMedium,
                          color: iconColor,
                        ),
                      if (showAdditionalIcon && additionalIcon != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: DesignTokens.spacing4,
                          ),
                          child: additionalIcon,
                        ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spacing4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isSelected ? selectedTextStyle : unSelectedTextStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
