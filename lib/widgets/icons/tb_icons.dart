import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icon_painters.dart';

export 'tb_icon_painters.dart' show TbIconKind, TbIconPainter;

/// Theme-aware custom ThingsBoard IoT vector icon wrapped in a [RepaintBoundary].
class TbIcon extends StatelessWidget {
  const TbIcon(
    this.kind, {
    super.key,
    this.size = DesignTokens.iconMedium,
    this.color,
    this.filled = false,
    this.semanticLabel,
  });

  final TbIconKind kind;
  final double size;
  final Color? color;
  final bool filled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;

    final painted = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: TbIconPainter(
          kind: kind,
          color: resolvedColor,
          filled: filled,
        ),
      ),
    );

    if (semanticLabel != null && semanticLabel!.isNotEmpty) {
      return Semantics(label: semanticLabel, image: true, child: painted);
    }

    return ExcludeSemantics(child: painted);
  }
}

/// Convenience constructors & semantic icon mappers for ThingsBoard IoT domain.
abstract final class TbIcons {
  static TbIconKind kindForSeverity(AlarmSeverity severity) {
    return switch (severity) {
      AlarmSeverity.critical => TbIconKind.severityCritical,
      AlarmSeverity.major => TbIconKind.severityMajor,
      AlarmSeverity.minor => TbIconKind.severityMinor,
      AlarmSeverity.warning => TbIconKind.severityWarning,
      AlarmSeverity.indeterminate => TbIconKind.severityIndeterminate,
    };
  }

  static TbIconKind kindForDeviceType(String? type) {
    final normalized = (type ?? '').toLowerCase();
    if (normalized.contains('gateway') || normalized.contains('router')) {
      return TbIconKind.gateway;
    }
    if (normalized.contains('energy') ||
        normalized.contains('meter') ||
        normalized.contains('power')) {
      return TbIconKind.energyMeter;
    }
    if (normalized.contains('gps') || normalized.contains('tracker')) {
      return TbIconKind.gpsTracker;
    }
    if (normalized.contains('water') ||
        normalized.contains('leak') ||
        normalized.contains('flow')) {
      return TbIconKind.waterSensor;
    }
    if (normalized.contains('thermostat') || normalized.contains('hvac')) {
      return TbIconKind.thermostat;
    }
    if (normalized.contains('switch') ||
        normalized.contains('relay') ||
        normalized.contains('actuator')) {
      return TbIconKind.actuator;
    }
    return TbIconKind.sensorNode;
  }

  static TbIconKind kindForTelemetryKey(String key) {
    final k = key.toLowerCase();
    if (k.contains('temp')) return TbIconKind.temperature;
    if (k.contains('humid')) return TbIconKind.humidity;
    if (k.contains('volt') || k.contains('power') || k.contains('watt')) {
      return TbIconKind.voltagePower;
    }
    if (k.contains('rssi') || k.contains('signal') || k.contains('wifi')) {
      return TbIconKind.signalRssi;
    }
    if (k.contains('batt')) return TbIconKind.battery;
    if (k.contains('flow') || k.contains('water')) return TbIconKind.flowRate;
    return TbIconKind.sensorNode;
  }

  static Widget severity(
    AlarmSeverity severity, {
    double size = DesignTokens.iconSmall,
    Color? color,
    String? semanticLabel,
  }) => TbIcon(
    kindForSeverity(severity),
    size: size,
    color: color,
    semanticLabel: semanticLabel,
  );

  static Widget deviceType(
    String? type, {
    double size = DesignTokens.iconMedium,
    Color? color,
    String? semanticLabel,
  }) => TbIcon(
    kindForDeviceType(type),
    size: size,
    color: color,
    semanticLabel: semanticLabel,
  );
}
