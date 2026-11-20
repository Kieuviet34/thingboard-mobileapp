import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/modules/main/model/main_navigation_item.dart';
import 'package:thingsboard_democloud_app/modules/main/widgets/bottom_navbar_items.dart';

class TbNavigationBarWidget extends StatelessWidget {
  const TbNavigationBarWidget({
    super.key,
    this.backgroundColor,
    required this.customBottomBarItems,
    this.currentIndex = 0,
    required this.onTap,
    this.lineIndicatorWidth = 2,
    this.gradient,
    this.selectedTextStyle,
    this.unSelectedTextStyle,
  });

  final Color? backgroundColor;
  final List<TbMainNavigationItem> customBottomBarItems;
  final int currentIndex;
  final double lineIndicatorWidth;
  final ValueChanged<int> onTap;
  final LinearGradient? gradient;
  final TextStyle? selectedTextStyle;
  final TextStyle? unSelectedTextStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final defaultSelected =
        selectedTextStyle ??
        (textTheme.labelMedium ?? const TextStyle()).copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        );
    final defaultUnselected =
        unSelectedTextStyle ??
        (textTheme.labelMedium ?? const TextStyle()).copyWith(
          color: scheme.onSurfaceVariant,
        );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.surfaceContainer,
        gradient: gradient,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: customBottomBarItems
            .mapIndexed(
              (index, item) => Expanded(
                child: BottomNavbarItems(
                  label: item.title,
                  icon: item.icon,
                  tbIconKind: item.tbIconKind,
                  currentIndex: currentIndex,
                  lineIndicatorWidth: lineIndicatorWidth,
                  index: index,
                  onTap: onTap,
                  selectedTextStyle: defaultSelected,
                  unSelectedTextStyle: defaultUnselected,
                  showAdditionalIcon: item.showAdditionalIcon,
                  additionalIcon: item.additionalIconLarge,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
