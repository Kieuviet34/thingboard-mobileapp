import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

enum TbStatusTone {
  critical,
  major,
  minor,
  warning,
  indeterminate,
  cleared,
  online,
  offline,
  demo,
}

/// Compact 1-word status badge pairing geometric [TbIcon] + semantic color + label.
class TbStatusBadge extends StatelessWidget {
  const TbStatusBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
    this.compact = false,
  });

  factory TbStatusBadge.severity(
    AlarmSeverity severity, {
    Key? key,
    bool compact = false,
  }) {
    final tone = switch (severity) {
      AlarmSeverity.critical => TbStatusTone.critical,
      AlarmSeverity.major => TbStatusTone.major,
      AlarmSeverity.minor => TbStatusTone.minor,
      AlarmSeverity.warning => TbStatusTone.warning,
      AlarmSeverity.indeterminate => TbStatusTone.indeterminate,
    };
    return TbStatusBadge(
      key: key,
      label: severity.wireValue,
      icon: TbIcons.kindForSeverity(severity),
      tone: tone,
      compact: compact,
    );
  }

  factory TbStatusBadge.online(bool active, {Key? key, bool compact = false}) {
    return TbStatusBadge(
      key: key,
      label: active ? 'ONLINE' : 'OFFLINE',
      icon: active ? TbIconKind.livePulse : TbIconKind.offlineNode,
      tone: active ? TbStatusTone.online : TbStatusTone.offline,
      compact: compact,
    );
  }

  factory TbStatusBadge.cleared({Key? key, bool compact = false}) {
    return TbStatusBadge(
      key: key,
      label: 'CLEARED',
      icon: TbIconKind.statusCleared,
      tone: TbStatusTone.cleared,
      compact: compact,
    );
  }

  factory TbStatusBadge.demo({Key? key, bool compact = false}) {
    return TbStatusBadge(
      key: key,
      label: 'DEMO',
      icon: TbIconKind.demoFlask,
      tone: TbStatusTone.demo,
      compact: compact,
    );
  }

  final String label;
  final TbIconKind icon;
  final TbStatusTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final statusColors = TbStatusColors.of(context);
    final (bg, fg, accent) = switch (tone) {
      TbStatusTone.critical => (
        statusColors.criticalContainer,
        statusColors.onCriticalContainer,
        statusColors.critical,
      ),
      TbStatusTone.major => (
        statusColors.majorContainer,
        statusColors.onMajorContainer,
        statusColors.major,
      ),
      TbStatusTone.minor => (
        statusColors.minorContainer,
        statusColors.onMinorContainer,
        statusColors.minor,
      ),
      TbStatusTone.warning => (
        statusColors.warningContainer,
        statusColors.onWarningContainer,
        statusColors.warning,
      ),
      TbStatusTone.indeterminate => (
        statusColors.indeterminateContainer,
        statusColors.onIndeterminateContainer,
        statusColors.indeterminate,
      ),
      TbStatusTone.cleared => (
        statusColors.clearedContainer,
        statusColors.onClearedContainer,
        statusColors.cleared,
      ),
      TbStatusTone.online => (
        statusColors.onlineContainer,
        statusColors.onOnlineContainer,
        statusColors.online,
      ),
      TbStatusTone.offline => (
        statusColors.offlineContainer,
        statusColors.onOfflineContainer,
        statusColors.offline,
      ),
      TbStatusTone.demo => (
        statusColors.demoContainer,
        statusColors.onDemoContainer,
        statusColors.demo,
      ),
    };

    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: label,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? DesignTokens.spacing8 : DesignTokens.spacing12,
          vertical: compact ? DesignTokens.spacing2 : DesignTokens.spacing4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: DesignTokens.borderRadiusRound,
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TbIcon(
              icon,
              size: compact ? DesignTokens.iconXs : DesignTokens.iconSmall,
              color: accent,
            ),
            const SizedBox(width: DesignTokens.spacing4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
