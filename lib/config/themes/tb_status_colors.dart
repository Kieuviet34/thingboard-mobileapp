import 'package:flutter/material.dart';

/// Semantic IoT status & alarm severity colors for Light and Dark Material 3 themes.
@immutable
class TbStatusColors extends ThemeExtension<TbStatusColors> {
  const TbStatusColors({
    required this.critical,
    required this.onCritical,
    required this.criticalContainer,
    required this.onCriticalContainer,
    required this.major,
    required this.onMajor,
    required this.majorContainer,
    required this.onMajorContainer,
    required this.minor,
    required this.onMinor,
    required this.minorContainer,
    required this.onMinorContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.indeterminate,
    required this.onIndeterminate,
    required this.indeterminateContainer,
    required this.onIndeterminateContainer,
    required this.cleared,
    required this.onCleared,
    required this.clearedContainer,
    required this.onClearedContainer,
    required this.online,
    required this.onOnline,
    required this.onlineContainer,
    required this.onOnlineContainer,
    required this.offline,
    required this.onOffline,
    required this.offlineContainer,
    required this.onOfflineContainer,
    required this.demo,
    required this.onDemo,
    required this.demoContainer,
    required this.onDemoContainer,
  });

  factory TbStatusColors.light() => const TbStatusColors(
    critical: Color(0xFFBA1A1A),
    onCritical: Color(0xFFFFFFFF),
    criticalContainer: Color(0xFFFFDAD6),
    onCriticalContainer: Color(0xFF410002),
    major: Color(0xFFC43E00),
    onMajor: Color(0xFFFFFFFF),
    majorContainer: Color(0xFFFFDBD0),
    onMajorContainer: Color(0xFF3B0B00),
    minor: Color(0xFF9A5700),
    onMinor: Color(0xFFFFFFFF),
    minorContainer: Color(0xFFFFE0B2),
    onMinorContainer: Color(0xFF331B00),
    warning: Color(0xFF7A5900),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFDF9E),
    onWarningContainer: Color(0xFF261A00),
    indeterminate: Color(0xFF475569),
    onIndeterminate: Color(0xFFFFFFFF),
    indeterminateContainer: Color(0xFFE2E8F0),
    onIndeterminateContainer: Color(0xFF1E293B),
    cleared: Color(0xFF0F6D31),
    onCleared: Color(0xFFFFFFFF),
    clearedContainer: Color(0xFFC8F7D4),
    onClearedContainer: Color(0xFF00210B),
    online: Color(0xFF0F6D31),
    onOnline: Color(0xFFFFFFFF),
    onlineContainer: Color(0xFFC8F7D4),
    onOnlineContainer: Color(0xFF00210B),
    offline: Color(0xFF4B5563),
    onOffline: Color(0xFFFFFFFF),
    offlineContainer: Color(0xFFE5E7EB),
    onOfflineContainer: Color(0xFF111827),
    demo: Color(0xFF305680),
    onDemo: Color(0xFFFFFFFF),
    demoContainer: Color(0xFFD6E4F7),
    onDemoContainer: Color(0xFF001C3A),
  );

  factory TbStatusColors.dark() => const TbStatusColors(
    critical: Color(0xFFFFB4AB),
    onCritical: Color(0xFF690005),
    criticalContainer: Color(0xFF93000A),
    onCriticalContainer: Color(0xFFFFDAD6),
    major: Color(0xFFFFB59D),
    onMajor: Color(0xFF5F1A00),
    majorContainer: Color(0xFF7E2700),
    onMajorContainer: Color(0xFFFFDBD0),
    minor: Color(0xFFFFCC80),
    onMinor: Color(0xFF4E2A00),
    minorContainer: Color(0xFF6A3C00),
    onMinorContainer: Color(0xFFFFE0B2),
    warning: Color(0xFFF6C84C),
    onWarning: Color(0xFF402D00),
    warningContainer: Color(0xFF5B4300),
    onWarningContainer: Color(0xFFFFDF9E),
    indeterminate: Color(0xFFCBD5E1),
    onIndeterminate: Color(0xFF1E293B),
    indeterminateContainer: Color(0xFF334155),
    onIndeterminateContainer: Color(0xFFF1F5F9),
    cleared: Color(0xFF82DA9A),
    onCleared: Color(0xFF003915),
    clearedContainer: Color(0xFF005323),
    onClearedContainer: Color(0xFFC8F7D4),
    online: Color(0xFF82DA9A),
    onOnline: Color(0xFF003915),
    onlineContainer: Color(0xFF005323),
    onOnlineContainer: Color(0xFFC8F7D4),
    offline: Color(0xFF9CA3AF),
    onOffline: Color(0xFF1F2937),
    offlineContainer: Color(0xFF374151),
    onOfflineContainer: Color(0xFFF3F4F6),
    demo: Color(0xFFA4C8FF),
    onDemo: Color(0xFF00315E),
    demoContainer: Color(0xFF10467C),
    onDemoContainer: Color(0xFFD6E4F7),
  );

  static TbStatusColors of(BuildContext context) {
    final ext = Theme.of(context).extension<TbStatusColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark
        ? TbStatusColors.dark()
        : TbStatusColors.light();
  }

  final Color critical;
  final Color onCritical;
  final Color criticalContainer;
  final Color onCriticalContainer;
  final Color major;
  final Color onMajor;
  final Color majorContainer;
  final Color onMajorContainer;
  final Color minor;
  final Color onMinor;
  final Color minorContainer;
  final Color onMinorContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color indeterminate;
  final Color onIndeterminate;
  final Color indeterminateContainer;
  final Color onIndeterminateContainer;
  final Color cleared;
  final Color onCleared;
  final Color clearedContainer;
  final Color onClearedContainer;
  final Color online;
  final Color onOnline;
  final Color onlineContainer;
  final Color onOnlineContainer;
  final Color offline;
  final Color onOffline;
  final Color offlineContainer;
  final Color onOfflineContainer;
  final Color demo;
  final Color onDemo;
  final Color demoContainer;
  final Color onDemoContainer;

  @override
  TbStatusColors copyWith({
    Color? critical,
    Color? onCritical,
    Color? criticalContainer,
    Color? onCriticalContainer,
    Color? major,
    Color? onMajor,
    Color? majorContainer,
    Color? onMajorContainer,
    Color? minor,
    Color? onMinor,
    Color? minorContainer,
    Color? onMinorContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? indeterminate,
    Color? onIndeterminate,
    Color? indeterminateContainer,
    Color? onIndeterminateContainer,
    Color? cleared,
    Color? onCleared,
    Color? clearedContainer,
    Color? onClearedContainer,
    Color? online,
    Color? onOnline,
    Color? onlineContainer,
    Color? onOnlineContainer,
    Color? offline,
    Color? onOffline,
    Color? offlineContainer,
    Color? onOfflineContainer,
    Color? demo,
    Color? onDemo,
    Color? demoContainer,
    Color? onDemoContainer,
  }) {
    return TbStatusColors(
      critical: critical ?? this.critical,
      onCritical: onCritical ?? this.onCritical,
      criticalContainer: criticalContainer ?? this.criticalContainer,
      onCriticalContainer: onCriticalContainer ?? this.onCriticalContainer,
      major: major ?? this.major,
      onMajor: onMajor ?? this.onMajor,
      majorContainer: majorContainer ?? this.majorContainer,
      onMajorContainer: onMajorContainer ?? this.onMajorContainer,
      minor: minor ?? this.minor,
      onMinor: onMinor ?? this.onMinor,
      minorContainer: minorContainer ?? this.minorContainer,
      onMinorContainer: onMinorContainer ?? this.onMinorContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      indeterminate: indeterminate ?? this.indeterminate,
      onIndeterminate: onIndeterminate ?? this.onIndeterminate,
      indeterminateContainer:
          indeterminateContainer ?? this.indeterminateContainer,
      onIndeterminateContainer:
          onIndeterminateContainer ?? this.onIndeterminateContainer,
      cleared: cleared ?? this.cleared,
      onCleared: onCleared ?? this.onCleared,
      clearedContainer: clearedContainer ?? this.clearedContainer,
      onClearedContainer: onClearedContainer ?? this.onClearedContainer,
      online: online ?? this.online,
      onOnline: onOnline ?? this.onOnline,
      onlineContainer: onlineContainer ?? this.onlineContainer,
      onOnlineContainer: onOnlineContainer ?? this.onOnlineContainer,
      offline: offline ?? this.offline,
      onOffline: onOffline ?? this.onOffline,
      offlineContainer: offlineContainer ?? this.offlineContainer,
      onOfflineContainer: onOfflineContainer ?? this.onOfflineContainer,
      demo: demo ?? this.demo,
      onDemo: onDemo ?? this.onDemo,
      demoContainer: demoContainer ?? this.demoContainer,
      onDemoContainer: onDemoContainer ?? this.onDemoContainer,
    );
  }

  @override
  TbStatusColors lerp(ThemeExtension<TbStatusColors>? other, double t) {
    if (other is! TbStatusColors) return this;
    return TbStatusColors(
      critical: Color.lerp(critical, other.critical, t)!,
      onCritical: Color.lerp(onCritical, other.onCritical, t)!,
      criticalContainer: Color.lerp(
        criticalContainer,
        other.criticalContainer,
        t,
      )!,
      onCriticalContainer: Color.lerp(
        onCriticalContainer,
        other.onCriticalContainer,
        t,
      )!,
      major: Color.lerp(major, other.major, t)!,
      onMajor: Color.lerp(onMajor, other.onMajor, t)!,
      majorContainer: Color.lerp(majorContainer, other.majorContainer, t)!,
      onMajorContainer: Color.lerp(
        onMajorContainer,
        other.onMajorContainer,
        t,
      )!,
      minor: Color.lerp(minor, other.minor, t)!,
      onMinor: Color.lerp(onMinor, other.onMinor, t)!,
      minorContainer: Color.lerp(minorContainer, other.minorContainer, t)!,
      onMinorContainer: Color.lerp(
        onMinorContainer,
        other.onMinorContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      indeterminate: Color.lerp(indeterminate, other.indeterminate, t)!,
      onIndeterminate: Color.lerp(onIndeterminate, other.onIndeterminate, t)!,
      indeterminateContainer: Color.lerp(
        indeterminateContainer,
        other.indeterminateContainer,
        t,
      )!,
      onIndeterminateContainer: Color.lerp(
        onIndeterminateContainer,
        other.onIndeterminateContainer,
        t,
      )!,
      cleared: Color.lerp(cleared, other.cleared, t)!,
      onCleared: Color.lerp(onCleared, other.onCleared, t)!,
      clearedContainer: Color.lerp(
        clearedContainer,
        other.clearedContainer,
        t,
      )!,
      onClearedContainer: Color.lerp(
        onClearedContainer,
        other.onClearedContainer,
        t,
      )!,
      online: Color.lerp(online, other.online, t)!,
      onOnline: Color.lerp(onOnline, other.onOnline, t)!,
      onlineContainer: Color.lerp(onlineContainer, other.onlineContainer, t)!,
      onOnlineContainer: Color.lerp(
        onOnlineContainer,
        other.onOnlineContainer,
        t,
      )!,
      offline: Color.lerp(offline, other.offline, t)!,
      onOffline: Color.lerp(onOffline, other.onOffline, t)!,
      offlineContainer: Color.lerp(
        offlineContainer,
        other.offlineContainer,
        t,
      )!,
      onOfflineContainer: Color.lerp(
        onOfflineContainer,
        other.onOfflineContainer,
        t,
      )!,
      demo: Color.lerp(demo, other.demo, t)!,
      onDemo: Color.lerp(onDemo, other.onDemo, t)!,
      demoContainer: Color.lerp(demoContainer, other.demoContainer, t)!,
      onDemoContainer: Color.lerp(onDemoContainer, other.onDemoContainer, t)!,
    );
  }
}
