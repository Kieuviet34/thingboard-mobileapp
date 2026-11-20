import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/app_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

/// Compact IoT telemetry metric pill (`[TbIcon] value unit`) using tabular figures.
class TbMetricPill extends StatelessWidget {
  const TbMetricPill({
    super.key,
    required this.icon,
    required this.value,
    this.unit,
    this.label,
    this.accentColor,
  });

  final TbIconKind icon;
  final String value;
  final String? unit;
  final String? label;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final resolvedAccent =
        accentColor ?? _resolveMetricAccent(unit, icon, scheme);
    final formattedValue = (unit != null && unit!.isNotEmpty)
        ? '$value $unit'
        : value;

    final valueStyle = TbTextStyles.tabular(
      textTheme.labelLarge ?? TbTextStyles.metricValue,
    ).copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600);

    final valueWidget = disableAnimations
        ? Text(
            formattedValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: valueStyle,
          )
        : AnimatedSwitcher(
            duration: DesignTokens.motionFast,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              formattedValue,
              key: ValueKey<String>(formattedValue),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          );

    return Semantics(
      label: label != null ? '$label $formattedValue' : formattedValue,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing12,
          vertical: DesignTokens.spacing8,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: DesignTokens.borderRadiusLarge,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TbIcon(icon, size: DesignTokens.iconSmall, color: resolvedAccent),
            const SizedBox(width: DesignTokens.spacing8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null && label!.isNotEmpty)
                    Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  valueWidget,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _resolveMetricAccent(
    String? unit,
    TbIconKind icon,
    ColorScheme scheme,
  ) {
    final u = (unit ?? '').toLowerCase();
    if (u.contains('v') ||
        u.contains('volt') ||
        u.contains('w') ||
        u.contains('kw') ||
        icon == TbIconKind.voltagePower) {
      return AppColors.metricVoltage;
    }
    if (u.contains('°c') ||
        u.contains('°f') ||
        icon == TbIconKind.temperature) {
      return AppColors.metricTemperature;
    }
    if (u.contains('%') || icon == TbIconKind.humidity) {
      return AppColors.metricHumidity;
    }
    if (u.contains('l/min') ||
        u.contains('m3') ||
        icon == TbIconKind.flowRate ||
        icon == TbIconKind.waterSensor) {
      return AppColors.metricFlow;
    }
    if (u.contains('dbm') || icon == TbIconKind.signalRssi) {
      return AppColors.metricRssi;
    }
    return scheme.primary;
  }
}
