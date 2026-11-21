import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

/// Top-level shell destination shown in the nav bar / rail.
class TbMainNavigationItem {
  const TbMainNavigationItem({
    required this.title,
    required this.tbIconKind,
    required this.path,
    this.badgeSemantics = '',
  });

  final String title;
  final TbIconKind tbIconKind;
  final String path;

  /// Word read after the badge count (e.g. "active", "unread").
  final String badgeSemantics;
}
