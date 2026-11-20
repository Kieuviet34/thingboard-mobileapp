import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Canonical ThingsBoard IoT custom vector icon identifiers.
enum TbIconKind {
  // Navigation (support `filled: true` duotone active state)
  navHome,
  navAlarms,
  navDevices,
  navMore,

  // IoT entities & modules
  sensorNode,
  gateway,
  energyMeter,
  gpsTracker,
  waterSensor,
  thermostat,
  actuator,
  assetBuilding,
  customerOrg,
  dashboardTile,
  auditLog,
  notificationInbox,

  // Telemetry & RPC channels
  temperature,
  humidity,
  voltagePower,
  signalRssi,
  battery,
  flowRate,
  rpcCommand,
  attributesTag,
  relationsGraph,

  // Shape-distinct alarm severities & status (never color-only)
  severityCritical,
  severityMajor,
  severityMinor,
  severityWarning,
  severityIndeterminate,
  statusCleared,

  // Session & scanner
  livePulse,
  offlineNode,
  demoFlask,
  qrFrame,
}

/// Custom `24x24` viewBox vector painter with `1.75dp` stroke and rounded joins.
class TbIconPainter extends CustomPainter {
  const TbIconPainter({
    required this.kind,
    required this.color,
    this.filled = false,
  });

  final TbIconKind kind;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final softFill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    switch (kind) {
      case TbIconKind.navHome:
        _paintNavHome(canvas, stroke, fill, softFill);
      case TbIconKind.navAlarms:
        _paintNavAlarms(canvas, stroke, fill, softFill);
      case TbIconKind.navDevices:
        _paintNavDevices(canvas, stroke, fill, softFill);
      case TbIconKind.navMore:
        _paintNavMore(canvas, stroke, fill, softFill);
      case TbIconKind.sensorNode:
        _paintSensorNode(canvas, stroke, fill);
      case TbIconKind.gateway:
        _paintGateway(canvas, stroke, fill);
      case TbIconKind.energyMeter:
        _paintEnergyMeter(canvas, stroke, fill);
      case TbIconKind.gpsTracker:
        _paintGpsTracker(canvas, stroke, fill);
      case TbIconKind.waterSensor:
        _paintWaterSensor(canvas, stroke);
      case TbIconKind.thermostat:
        _paintThermostat(canvas, stroke, fill);
      case TbIconKind.actuator:
        _paintActuator(canvas, stroke, fill);
      case TbIconKind.assetBuilding:
        _paintAssetBuilding(canvas, stroke, fill);
      case TbIconKind.customerOrg:
        _paintCustomerOrg(canvas, stroke);
      case TbIconKind.dashboardTile:
        _paintDashboardTile(canvas, stroke, softFill);
      case TbIconKind.auditLog:
        _paintAuditLog(canvas, stroke);
      case TbIconKind.notificationInbox:
        _paintNotificationInbox(canvas, stroke, fill);
      case TbIconKind.temperature:
        _paintTemperature(canvas, stroke, fill);
      case TbIconKind.humidity:
        _paintHumidity(canvas, stroke);
      case TbIconKind.voltagePower:
        _paintVoltagePower(canvas, stroke);
      case TbIconKind.signalRssi:
        _paintSignalRssi(canvas, stroke);
      case TbIconKind.battery:
        _paintBattery(canvas, stroke, fill);
      case TbIconKind.flowRate:
        _paintFlowRate(canvas, stroke);
      case TbIconKind.rpcCommand:
        _paintRpcCommand(canvas, stroke, fill);
      case TbIconKind.attributesTag:
        _paintAttributesTag(canvas, stroke, fill);
      case TbIconKind.relationsGraph:
        _paintRelationsGraph(canvas, stroke, fill);
      case TbIconKind.severityCritical:
        _paintSeverityCritical(canvas, stroke, fill, softFill);
      case TbIconKind.severityMajor:
        _paintSeverityMajor(canvas, stroke, fill, softFill);
      case TbIconKind.severityMinor:
        _paintSeverityMinor(canvas, stroke, fill, softFill);
      case TbIconKind.severityWarning:
        _paintSeverityWarning(canvas, stroke, fill, softFill);
      case TbIconKind.severityIndeterminate:
        _paintSeverityIndeterminate(canvas, stroke, fill);
      case TbIconKind.statusCleared:
        _paintStatusCleared(canvas, stroke, softFill);
      case TbIconKind.livePulse:
        _paintLivePulse(canvas, stroke, fill);
      case TbIconKind.offlineNode:
        _paintOfflineNode(canvas, stroke);
      case TbIconKind.demoFlask:
        _paintDemoFlask(canvas, stroke, softFill);
      case TbIconKind.qrFrame:
        _paintQrFrame(canvas, stroke, fill);
    }

    canvas.restore();
  }

  void _paintNavHome(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final roof = Path()
      ..moveTo(3.5, 10.5)
      ..lineTo(12, 3.5)
      ..lineTo(20.5, 10.5)
      ..lineTo(19, 10.5)
      ..lineTo(19, 19.5)
      ..lineTo(5, 19.5)
      ..lineTo(5, 10.5)
      ..close();
    if (filled) {
      canvas.drawPath(roof, softFill);
    }
    canvas.drawPath(
      Path()
        ..moveTo(3.5, 10.5)
        ..lineTo(12, 3.5)
        ..lineTo(20.5, 10.5),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(5.5, 9.5)
        ..lineTo(5.5, 19.5)
        ..lineTo(18.5, 19.5)
        ..lineTo(18.5, 9.5),
      stroke,
    );
    // IoT pulse node inside home
    canvas.drawCircle(const Offset(12, 14), filled ? 2.2 : 1.6, fill);
  }

  void _paintNavAlarms(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Paint softFill,
  ) {
    final bell = Path()
      ..moveTo(6.5, 16.5)
      ..lineTo(6.5, 11)
      ..arcToPoint(const Offset(17.5, 11), radius: const Radius.circular(5.5))
      ..lineTo(17.5, 16.5)
      ..lineTo(19.5, 18)
      ..lineTo(4.5, 18)
      ..close();
    if (filled) {
      canvas.drawPath(bell, softFill);
    }
    canvas.drawPath(bell, stroke);
    canvas.drawLine(const Offset(12, 3.5), const Offset(12, 5.5), stroke);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(12, 18.5), radius: 2),
      0,
      math.pi,
      false,
      stroke,
    );
    if (filled) {
      canvas.drawCircle(const Offset(18, 6.5), 2.2, fill);
    }
  }

  void _paintNavDevices(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Paint softFill,
  ) {
    final core = RRect.fromRectAndRadius(
      const Rect.fromLTWH(6.5, 6.5, 11, 11),
      const Radius.circular(2.5),
    );
    if (filled) {
      canvas.drawRRect(core, softFill);
    }
    canvas.drawRRect(core, stroke);
    canvas.drawCircle(const Offset(12, 12), 2.0, filled ? fill : stroke);
    // Chip pins on 4 sides
    for (final offset in const [9.5, 14.5]) {
      canvas.drawLine(Offset(offset, 3.5), Offset(offset, 6.5), stroke);
      canvas.drawLine(Offset(offset, 17.5), Offset(offset, 20.5), stroke);
      canvas.drawLine(Offset(3.5, offset), Offset(6.5, offset), stroke);
      canvas.drawLine(Offset(17.5, offset), Offset(20.5, offset), stroke);
    }
  }

  void _paintNavMore(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final rects = const [
      Rect.fromLTWH(4, 4, 6.5, 6.5),
      Rect.fromLTWH(13.5, 4, 6.5, 6.5),
      Rect.fromLTWH(4, 13.5, 6.5, 6.5),
    ];
    for (final r in rects) {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(1.8));
      if (filled) canvas.drawRRect(rr, softFill);
      canvas.drawRRect(rr, stroke);
    }
    if (filled) {
      canvas.drawCircle(const Offset(16.75, 16.75), 3.25, softFill);
    }
    canvas.drawCircle(const Offset(16.75, 16.75), 3.25, stroke);
  }

  void _paintSensorNode(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(12, 12), 2.3, fill);
    for (final r in const [6.0, 9.2]) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(12, 12), radius: r),
        -0.75,
        1.5,
        false,
        stroke,
      );
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(12, 12), radius: r),
        math.pi - 0.75,
        1.5,
        false,
        stroke,
      );
    }
  }

  void _paintGateway(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.5, 12.5, 17, 7),
        const Radius.circular(2.2),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(8, 12.5), const Offset(8, 7.5), stroke);
    canvas.drawLine(const Offset(16, 12.5), const Offset(16, 5.5), stroke);
    canvas.drawCircle(const Offset(8, 6.5), 1.2, fill);
    canvas.drawCircle(const Offset(16, 4.5), 1.2, fill);
    canvas.drawCircle(const Offset(7.5, 16), 1.1, fill);
    canvas.drawCircle(const Offset(11.5, 16), 1.1, fill);
    canvas.drawLine(const Offset(15, 16), const Offset(17.5, 16), stroke);
  }

  void _paintEnergyMeter(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4.5, 3.5, 15, 17),
        const Radius.circular(2.5),
      ),
      stroke,
    );
    canvas.drawCircle(const Offset(12, 11), 4.2, stroke);
    canvas.drawLine(const Offset(12, 11), const Offset(14.5, 8.8), stroke);
    canvas.drawCircle(const Offset(8.5, 17.5), 1.0, fill);
    canvas.drawCircle(const Offset(12, 17.5), 1.0, fill);
    canvas.drawCircle(const Offset(15.5, 17.5), 1.0, fill);
  }

  void _paintGpsTracker(Canvas canvas, Paint stroke, Paint fill) {
    final pin = Path()
      ..moveTo(12, 20.5)
      ..quadraticBezierTo(5.5, 14.5, 5.5, 9.8)
      ..arcToPoint(const Offset(18.5, 9.8), radius: const Radius.circular(6.5))
      ..quadraticBezierTo(18.5, 14.5, 12, 20.5)
      ..close();
    canvas.drawPath(pin, stroke);
    canvas.drawCircle(const Offset(12, 9.8), 2.2, fill);
  }

  void _paintWaterSensor(Canvas canvas, Paint stroke) {
    final drop = Path()
      ..moveTo(12, 3.5)
      ..quadraticBezierTo(18, 10.5, 18, 14.5)
      ..arcToPoint(const Offset(6, 14.5), radius: const Radius.circular(6))
      ..quadraticBezierTo(6, 10.5, 12, 3.5)
      ..close();
    canvas.drawPath(drop, stroke);
    canvas.drawArc(
      const Rect.fromLTWH(8.5, 12.5, 5, 5),
      0.3,
      1.6,
      false,
      stroke,
    );
  }

  void _paintThermostat(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(12, 12), 8.2, stroke);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(12, 12), radius: 5.0),
      2.3,
      4.8,
      false,
      stroke,
    );
    canvas.drawCircle(const Offset(12, 12), 1.5, fill);
  }

  void _paintActuator(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.5, 7.5, 17, 9),
        const Radius.circular(4.5),
      ),
      stroke,
    );
    canvas.drawCircle(const Offset(15.5, 12), 2.5, fill);
  }

  void _paintAssetBuilding(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4.5, 4, 9.5, 16),
        const Radius.circular(1.5),
      ),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(14, 9.5)
        ..lineTo(19.5, 9.5)
        ..lineTo(19.5, 20)
        ..lineTo(4.5, 20),
      stroke,
    );
    for (final y in const [7.5, 11.5, 15.5]) {
      canvas.drawCircle(Offset(7.8, y), 0.9, fill);
      canvas.drawCircle(Offset(11.0, y), 0.9, fill);
    }
    canvas.drawCircle(const Offset(16.8, 13.5), 0.9, fill);
  }

  void _paintCustomerOrg(Canvas canvas, Paint stroke) {
    canvas.drawCircle(const Offset(9.5, 8.2), 3.0, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(4.0, 19.5)
        ..quadraticBezierTo(4.0, 14.2, 9.5, 14.2)
        ..quadraticBezierTo(15.0, 14.2, 15.0, 19.5),
      stroke,
    );
    canvas.drawCircle(const Offset(16.2, 9.2), 2.2, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(16.2, 14.5)
        ..quadraticBezierTo(20.0, 14.8, 20.0, 19.5),
      stroke,
    );
  }

  void _paintDashboardTile(Canvas canvas, Paint stroke, Paint softFill) {
    final r1 = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3.5, 3.5, 7.5, 9),
      const Radius.circular(1.8),
    );
    final r2 = RRect.fromRectAndRadius(
      const Rect.fromLTWH(13, 3.5, 7.5, 5.5),
      const Radius.circular(1.8),
    );
    final r3 = RRect.fromRectAndRadius(
      const Rect.fromLTWH(13, 11, 7.5, 9.5),
      const Radius.circular(1.8),
    );
    final r4 = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3.5, 14.5, 7.5, 6),
      const Radius.circular(1.8),
    );
    canvas.drawRRect(r1, softFill);
    for (final r in [r1, r2, r3, r4]) {
      canvas.drawRRect(r, stroke);
    }
  }

  void _paintAuditLog(Canvas canvas, Paint stroke) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 3.5, 14, 17),
        const Radius.circular(2.2),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(8.5, 8.5), const Offset(15.5, 8.5), stroke);
    canvas.drawLine(const Offset(8.5, 12.5), const Offset(15.5, 12.5), stroke);
    canvas.drawLine(const Offset(8.5, 16.5), const Offset(12.5, 16.5), stroke);
  }

  void _paintNotificationInbox(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.5, 4.5, 17, 15),
        const Radius.circular(2.5),
      ),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(3.5, 14)
        ..lineTo(8.5, 14)
        ..lineTo(10, 16)
        ..lineTo(14, 16)
        ..lineTo(15.5, 14)
        ..lineTo(20.5, 14),
      stroke,
    );
    canvas.drawCircle(const Offset(16.5, 8.5), 1.6, fill);
  }

  void _paintTemperature(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9.5, 3.5, 5, 11),
        const Radius.circular(2.5),
      ),
      stroke,
    );
    canvas.drawCircle(const Offset(12, 16.8), 3.6, stroke);
    canvas.drawCircle(const Offset(12, 16.8), 1.6, fill);
    canvas.drawLine(const Offset(12, 9.5), const Offset(12, 15.2), stroke);
  }

  void _paintHumidity(Canvas canvas, Paint stroke) {
    _paintWaterSensor(canvas, stroke);
  }

  void _paintVoltagePower(Canvas canvas, Paint stroke) {
    final bolt = Path()
      ..moveTo(13.2, 3.5)
      ..lineTo(6.5, 13.2)
      ..lineTo(11.6, 13.2)
      ..lineTo(10.8, 20.5)
      ..lineTo(17.5, 10.8)
      ..lineTo(12.4, 10.8)
      ..close();
    canvas.drawPath(bolt, stroke);
  }

  void _paintSignalRssi(Canvas canvas, Paint stroke) {
    canvas.drawLine(const Offset(5, 19), const Offset(5, 15.5), stroke);
    canvas.drawLine(const Offset(9.5, 19), const Offset(9.5, 12.5), stroke);
    canvas.drawLine(const Offset(14, 19), const Offset(14, 9.0), stroke);
    canvas.drawLine(const Offset(18.5, 19), const Offset(18.5, 5.5), stroke);
  }

  void _paintBattery(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.5, 7, 15.5, 10),
        const Radius.circular(2.0),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(20.5, 10), const Offset(20.5, 14), stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 9.5, 8.5, 5),
        const Radius.circular(1.0),
      ),
      fill,
    );
  }

  void _paintFlowRate(Canvas canvas, Paint stroke) {
    for (final y in const [7.5, 12.5, 17.5]) {
      canvas.drawPath(
        Path()
          ..moveTo(4, y)
          ..quadraticBezierTo(8, y - 2.2, 12, y)
          ..quadraticBezierTo(16, y + 2.2, 20, y),
        stroke,
      );
    }
  }

  void _paintRpcCommand(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.5, 4.5, 17, 15),
        const Radius.circular(2.5),
      ),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(7.5, 9.5)
        ..lineTo(10.5, 12)
        ..lineTo(7.5, 14.5),
      stroke,
    );
    canvas.drawLine(const Offset(12.5, 14.5), const Offset(16.5, 14.5), stroke);
    canvas.drawCircle(const Offset(17, 8), 1.1, fill);
  }

  void _paintAttributesTag(Canvas canvas, Paint stroke, Paint fill) {
    final tag = Path()
      ..moveTo(4, 11.5)
      ..lineTo(4, 4.5)
      ..lineTo(11, 4.5)
      ..lineTo(19.5, 13)
      ..lineTo(12.5, 20)
      ..close();
    canvas.drawPath(tag, stroke);
    canvas.drawCircle(const Offset(8.2, 8.5), 1.2, fill);
  }

  void _paintRelationsGraph(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(6, 6.5), 2.5, stroke);
    canvas.drawCircle(const Offset(18, 6.5), 2.5, stroke);
    canvas.drawCircle(const Offset(12, 17.5), 2.5, fill);
    canvas.drawLine(const Offset(8.5, 6.5), const Offset(15.5, 6.5), stroke);
    canvas.drawLine(const Offset(7.2, 8.8), const Offset(10.8, 15.2), stroke);
    canvas.drawLine(const Offset(16.8, 8.8), const Offset(13.2, 15.2), stroke);
  }

  void _paintSeverityCritical(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Paint softFill,
  ) {
    // Octagon + exclamation mark
    final oct = Path()
      ..moveTo(8.5, 3.5)
      ..lineTo(15.5, 3.5)
      ..lineTo(20.5, 8.5)
      ..lineTo(20.5, 15.5)
      ..lineTo(15.5, 20.5)
      ..lineTo(8.5, 20.5)
      ..lineTo(3.5, 15.5)
      ..lineTo(3.5, 8.5)
      ..close();
    canvas.drawPath(oct, softFill);
    canvas.drawPath(oct, stroke);
    canvas.drawLine(const Offset(12, 8), const Offset(12, 13), stroke);
    canvas.drawCircle(const Offset(12, 16), 1.1, fill);
  }

  void _paintSeverityMajor(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Paint softFill,
  ) {
    // Triangle + exclamation mark
    final tri = Path()
      ..moveTo(12, 3.8)
      ..lineTo(20.5, 19.2)
      ..lineTo(3.5, 19.2)
      ..close();
    canvas.drawPath(tri, softFill);
    canvas.drawPath(tri, stroke);
    canvas.drawLine(const Offset(12, 9.2), const Offset(12, 13.8), stroke);
    canvas.drawCircle(const Offset(12, 16.5), 1.05, fill);
  }

  void _paintSeverityMinor(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Paint softFill,
  ) {
    // Diamond + center dot
    final dia = Path()
      ..moveTo(12, 3.5)
      ..lineTo(20.5, 12)
      ..lineTo(12, 20.5)
      ..lineTo(3.5, 12)
      ..close();
    canvas.drawPath(dia, softFill);
    canvas.drawPath(dia, stroke);
    canvas.drawCircle(const Offset(12, 12), 1.8, fill);
  }

  void _paintSeverityWarning(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Paint softFill,
  ) {
    // Circle + exclamation
    canvas.drawCircle(const Offset(12, 12), 8.5, softFill);
    canvas.drawCircle(const Offset(12, 12), 8.5, stroke);
    canvas.drawLine(const Offset(12, 8), const Offset(12, 13), stroke);
    canvas.drawCircle(const Offset(12, 16), 1.1, fill);
  }

  void _paintSeverityIndeterminate(Canvas canvas, Paint stroke, Paint fill) {
    // Dashed circle arc segments + dot/question mark
    for (var i = 0; i < 6; i++) {
      final start = i * (math.pi / 3);
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(12, 12), radius: 8.5),
        start,
        math.pi / 5,
        false,
        stroke,
      );
    }
    canvas.drawArc(
      const Rect.fromLTWH(9.6, 7.6, 4.8, 4.2),
      math.pi,
      math.pi * 1.35,
      false,
      stroke,
    );
    canvas.drawCircle(const Offset(12, 15.8), 1.05, fill);
  }

  void _paintStatusCleared(Canvas canvas, Paint stroke, Paint softFill) {
    // Shield + check
    final shield = Path()
      ..moveTo(12, 3.5)
      ..lineTo(19, 6.2)
      ..lineTo(19, 11.8)
      ..quadraticBezierTo(19, 17, 12, 20.5)
      ..quadraticBezierTo(5, 17, 5, 11.8)
      ..lineTo(5, 6.2)
      ..close();
    canvas.drawPath(shield, softFill);
    canvas.drawPath(shield, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(8.5, 12)
        ..lineTo(11, 14.5)
        ..lineTo(15.8, 9.5),
      stroke,
    );
  }

  void _paintLivePulse(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(12, 12), 3.0, fill);
    canvas.drawCircle(const Offset(12, 12), 6.5, stroke);
  }

  void _paintOfflineNode(Canvas canvas, Paint stroke) {
    canvas.drawCircle(const Offset(12, 12), 6.5, stroke);
    canvas.drawLine(const Offset(5.5, 5.5), const Offset(18.5, 18.5), stroke);
  }

  void _paintDemoFlask(Canvas canvas, Paint stroke, Paint softFill) {
    final flask = Path()
      ..moveTo(9.5, 4)
      ..lineTo(14.5, 4)
      ..moveTo(10.2, 4)
      ..lineTo(10.2, 9.5)
      ..lineTo(5.5, 18.2)
      ..quadraticBezierTo(4.8, 19.8, 6.6, 19.8)
      ..lineTo(17.4, 19.8)
      ..quadraticBezierTo(19.2, 19.8, 18.5, 18.2)
      ..lineTo(13.8, 9.5)
      ..lineTo(13.8, 4);
    canvas.drawPath(
      Path()
        ..moveTo(7.2, 15)
        ..lineTo(16.8, 15)
        ..lineTo(18.5, 18.2)
        ..quadraticBezierTo(19.2, 19.8, 17.4, 19.8)
        ..lineTo(6.6, 19.8)
        ..quadraticBezierTo(4.8, 19.8, 5.5, 18.2)
        ..close(),
      softFill,
    );
    canvas.drawPath(flask, stroke);
  }

  void _paintQrFrame(Canvas canvas, Paint stroke, Paint fill) {
    // 4 corner brackets
    canvas.drawPath(
      Path()
        ..moveTo(4, 8.5)
        ..lineTo(4, 4)
        ..lineTo(8.5, 4),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(15.5, 4)
        ..lineTo(20, 4)
        ..lineTo(20, 8.5),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(4, 15.5)
        ..lineTo(4, 20)
        ..lineTo(8.5, 20),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(15.5, 20)
        ..lineTo(20, 20)
        ..lineTo(20, 15.5),
      stroke,
    );
    canvas.drawRect(const Rect.fromLTWH(8, 8, 3, 3), fill);
    canvas.drawRect(const Rect.fromLTWH(13, 8, 3, 3), fill);
    canvas.drawRect(const Rect.fromLTWH(8, 13, 3, 3), fill);
    canvas.drawLine(const Offset(13, 14.5), const Offset(16, 14.5), stroke);
  }

  @override
  bool shouldRepaint(covariant TbIconPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.filled != filled;
}
