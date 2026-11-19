import 'package:flutter/material.dart';

class TbMainNavigationItem {
  const TbMainNavigationItem({
    required this.title,
    required this.icon,
    required this.path,
    this.id,
    this.showAdditionalIcon = false,
    this.additionalIconLarge,
    this.additionalIconSmall,
  });

  final String title;
  final IconData icon;
  final String path;
  final String? id;
  final bool showAdditionalIcon;
  final Widget? additionalIconLarge;
  final Widget? additionalIconSmall;
}
