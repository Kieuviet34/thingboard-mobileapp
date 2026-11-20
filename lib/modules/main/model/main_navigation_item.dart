import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

class TbMainNavigationItem {
  const TbMainNavigationItem({
    required this.title,
    required this.icon,
    required this.path,
    this.tbIconKind,
    this.id,
    this.showAdditionalIcon = false,
    this.additionalIconLarge,
    this.additionalIconSmall,
    this.badgeCount = 0,
  });

  final String title;
  final IconData icon;
  final TbIconKind? tbIconKind;
  final String path;
  final String? id;
  final bool showAdditionalIcon;
  final Widget? additionalIconLarge;
  final Widget? additionalIconSmall;
  final int badgeCount;
}
