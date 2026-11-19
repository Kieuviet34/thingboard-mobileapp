import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum AlarmSeverityType {
  critical('Critical', Color(0xFFD12730)),
  major('Major', Color(0xFFF66716)),
  minor('Minor', Color(0xFFF2DA05)),
  warning('Warning', Color(0xFFFAA405)),
  indeterminate('Indeterminate', Color(0x61000000));

  const AlarmSeverityType(this.label, this.color);
  final String label;
  final Color color;
}

enum AlarmStatusFilter {
  active('Active'),
  cleared('Cleared'),
  acknowledged('Acknowledged'),
  unacknowledged('Unacknowledged');

  const AlarmStatusFilter(this.label);
  final String label;
}

class MockDashboard {
  const MockDashboard({
    required this.id,
    required this.title,
    required this.description,
    required this.metrics,
  });

  final String id;
  final String title;
  final String description;
  final Map<String, String> metrics;
}

class MockAlarmComment {
  const MockAlarmComment({
    required this.id,
    required this.authorName,
    required this.initials,
    required this.text,
    required this.createdTime,
    this.isSystem = false,
  });

  final String id;
  final String authorName;
  final String initials;
  final String text;
  final DateTime createdTime;
  final bool isSystem;
}

class MockAlarm {
  const MockAlarm({
    required this.id,
    required this.type,
    required this.originatorName,
    required this.severity,
    required this.isActive,
    required this.isAcknowledged,
    required this.createdTime,
    this.assigneeName,
    this.dashboardId,
    this.comments = const [],
  });

  final String id;
  final String type;
  final String originatorName;
  final AlarmSeverityType severity;
  final bool isActive;
  final bool isAcknowledged;
  final DateTime createdTime;
  final String? assigneeName;
  final String? dashboardId;
  final List<MockAlarmComment> comments;

  String get statusLabel {
    final activePart = isActive ? 'Active' : 'Cleared';
    final ackPart = isAcknowledged ? 'Acknowledged' : 'Unacknowledged';
    return '$activePart $ackPart';
  }

  MockAlarm copyWith({
    bool? isActive,
    bool? isAcknowledged,
    String? assigneeName,
    List<MockAlarmComment>? comments,
  }) {
    return MockAlarm(
      id: id,
      type: type,
      originatorName: originatorName,
      severity: severity,
      isActive: isActive ?? this.isActive,
      isAcknowledged: isAcknowledged ?? this.isAcknowledged,
      createdTime: createdTime,
      assigneeName: assigneeName ?? this.assigneeName,
      dashboardId: dashboardId,
      comments: comments ?? this.comments,
    );
  }
}

class MockDeviceProfile {
  const MockDeviceProfile({
    required this.id,
    required this.name,
    required this.activeCount,
    required this.inactiveCount,
  });

  final String id;
  final String name;
  final int activeCount;
  final int inactiveCount;
}

class MockDevice {
  const MockDevice({
    required this.id,
    required this.name,
    required this.label,
    required this.type,
    required this.active,
    required this.createdTime,
    required this.customerName,
    required this.telemetry,
  });

  final String id;
  final String name;
  final String label;
  final String type;
  final bool active;
  final DateTime createdTime;
  final String customerName;
  final Map<String, String> telemetry;
}

class MockCustomer {
  const MockCustomer({
    required this.id,
    required this.title,
    required this.country,
    required this.city,
    required this.state,
    required this.zip,
    required this.address,
    required this.address2,
    required this.phone,
    required this.email,
    required this.createdTime,
  });

  final String id;
  final String title;
  final String country;
  final String city;
  final String state;
  final String zip;
  final String address;
  final String address2;
  final String phone;
  final String email;
  final DateTime createdTime;
}

class MockAsset {
  const MockAsset({
    required this.id,
    required this.name,
    required this.type,
    required this.label,
    required this.customerName,
    required this.createdTime,
  });

  final String id;
  final String name;
  final String type;
  final String label;
  final String customerName;
  final DateTime createdTime;
}

class MockAuditLog {
  const MockAuditLog({
    required this.id,
    required this.entityName,
    required this.entityType,
    required this.actionType,
    required this.isSuccess,
    required this.createdTime,
    required this.actionData,
    this.failureDetails,
  });

  final String id;
  final String entityName;
  final String entityType;
  final String actionType;
  final bool isSuccess;
  final DateTime createdTime;
  final Map<String, dynamic> actionData;
  final String? failureDetails;
}

class MockNotificationItem {
  const MockNotificationItem({
    required this.id,
    required this.subject,
    required this.text,
    required this.createdTime,
    this.isRead = false,
    this.severity,
    this.icon = Icons.notifications_outlined,
  });

  final String id;
  final String subject;
  final String text;
  final DateTime createdTime;
  final bool isRead;
  final AlarmSeverityType? severity;
  final IconData icon;

  MockNotificationItem copyWith({bool? isRead}) {
    return MockNotificationItem(
      id: id,
      subject: subject,
      text: text,
      createdTime: createdTime,
      isRead: isRead ?? this.isRead,
      severity: severity,
      icon: icon,
    );
  }
}

class MockUserProfile {
  const MockUserProfile({
    this.email = 'tenant@thingsboard.org',
    this.firstName = 'John',
    this.lastName = 'Doe',
    this.authority = 'Tenant Administrator',
    this.phone = '+1 415 555 0199',
    this.language = 'English (US)',
    this.unitSystem = 'Metric',
    this.homeDashboardTitle = 'Smart Office Monitoring',
    this.hideHomeDashboardToolbar = true,
  });

  final String email;
  final String firstName;
  final String lastName;
  final String authority;
  final String phone;
  final String language;
  final String unitSystem;
  final String homeDashboardTitle;
  final bool hideHomeDashboardToolbar;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? email : full;
  }

  String get shortName {
    final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    final combined = '$f$l';
    if (combined.isNotEmpty) return combined;
    return email.isNotEmpty ? email.substring(0, 1).toUpperCase() : 'U';
  }

  MockUserProfile copyWith({
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    String? language,
    String? unitSystem,
    String? homeDashboardTitle,
    bool? hideHomeDashboardToolbar,
  }) {
    return MockUserProfile(
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      authority: authority,
      phone: phone ?? this.phone,
      language: language ?? this.language,
      unitSystem: unitSystem ?? this.unitSystem,
      homeDashboardTitle: homeDashboardTitle ?? this.homeDashboardTitle,
      hideHomeDashboardToolbar:
          hideHomeDashboardToolbar ?? this.hideHomeDashboardToolbar,
    );
  }
}

final dashboardsProvider = Provider<List<MockDashboard>>((ref) {
  return const [
    MockDashboard(
      id: 'dash-1',
      title: 'Smart Office Monitoring',
      description: 'Real-time environmental & HVAC telemetry across floors',
      metrics: {
        'Temperature': '22.4 °C',
        'Humidity': '48 %',
        'CO2 Level': '412 ppm',
        'Power Consumption': '3.8 kW',
      },
    ),
    MockDashboard(
      id: 'dash-2',
      title: 'Energy Metering',
      description: 'Main grid, solar inverter, and sub-meter consumption',
      metrics: {
        'Voltage': '230.8 V',
        'Current': '16.5 A',
        'Active Power': '3.81 kW',
        'Daily Energy': '68.4 kWh',
      },
    ),
    MockDashboard(
      id: 'dash-3',
      title: 'Fleet Tracking',
      description: 'Live vehicle GPS coordinates, fuel levels, and speed',
      metrics: {
        'Active Vehicles': '14 / 16',
        'Avg Speed': '62 km/h',
        'Avg Fuel Level': '74 %',
        'Active Alerts': '1',
      },
    ),
    MockDashboard(
      id: 'dash-4',
      title: 'Water Quality & Pumps',
      description: 'Flow rate, pressure, pH, and turbidity sensors',
      metrics: {
        'Flow Rate': '124 L/min',
        'Pipe Pressure': '4.2 bar',
        'Water pH': '7.2',
        'Turbidity': '0.8 NTU',
      },
    ),
    MockDashboard(
      id: 'dash-5',
      title: 'Cold Chain Storage',
      description: 'Refrigerated warehouse zones A-D monitoring',
      metrics: {
        'Zone A Temp': '-18.5 °C',
        'Zone B Temp': '-19.1 °C',
        'Door Status': 'Closed',
        'Compressor': 'Running',
      },
    ),
    MockDashboard(
      id: 'dash-6',
      title: 'Solar Farm Overview',
      description: 'PV array generation and battery storage state of charge',
      metrics: {
        'PV Generation': '142.6 kW',
        'Battery SoC': '89 %',
        'Grid Export': '94.2 kW',
        'Inverter Temp': '41.2 °C',
      },
    ),
  ];
});

class AlarmsStateNotifier extends StateNotifier<List<MockAlarm>> {
  AlarmsStateNotifier()
    : super([
        MockAlarm(
          id: 'alarm-1',
          type: 'High Temperature',
          originatorName: 'Thermostat-Floor-3',
          severity: AlarmSeverityType.critical,
          isActive: true,
          isAcknowledged: false,
          createdTime: DateTime(2026, 11, 17, 14, 10),
          assigneeName: 'John Doe',
          dashboardId: 'dash-1',
          comments: [
            MockAlarmComment(
              id: 'c-1',
              authorName: 'System',
              initials: 'SY',
              text: 'Alarm was created by rule engine (Threshold > 30 °C)',
              createdTime: DateTime(2026, 11, 17, 14, 10),
              isSystem: true,
            ),
            MockAlarmComment(
              id: 'c-2',
              authorName: 'John Doe',
              initials: 'JD',
              text: 'Checking HVAC damper on Floor 3.',
              createdTime: DateTime(2026, 11, 17, 14, 22),
            ),
          ],
        ),
        MockAlarm(
          id: 'alarm-2',
          type: 'Low Battery Voltage',
          originatorName: 'GPS-Tracker-Van-04',
          severity: AlarmSeverityType.major,
          isActive: true,
          isAcknowledged: true,
          createdTime: DateTime(2026, 11, 17, 11, 45),
          assigneeName: 'John Doe',
          dashboardId: 'dash-3',
          comments: [
            MockAlarmComment(
              id: 'c-3',
              authorName: 'System',
              initials: 'SY',
              text: 'Alarm was acknowledged by John Doe',
              createdTime: DateTime(2026, 11, 17, 12, 0),
              isSystem: true,
            ),
          ],
        ),
        MockAlarm(
          id: 'alarm-3',
          type: 'Communication Timeout',
          originatorName: 'Water-Pump-Station-2',
          severity: AlarmSeverityType.warning,
          isActive: true,
          isAcknowledged: false,
          createdTime: DateTime(2026, 11, 16, 19, 30),
          dashboardId: 'dash-4',
        ),
        MockAlarm(
          id: 'alarm-4',
          type: 'High Humidity',
          originatorName: 'Cold-Storage-Zone-B',
          severity: AlarmSeverityType.minor,
          isActive: false,
          isAcknowledged: true,
          createdTime: DateTime(2026, 11, 15, 9, 15),
          dashboardId: 'dash-5',
        ),
        MockAlarm(
          id: 'alarm-5',
          type: 'Firmware Update Pending',
          originatorName: 'Gateway-Main-Bldg',
          severity: AlarmSeverityType.indeterminate,
          isActive: false,
          isAcknowledged: false,
          createdTime: DateTime(2026, 11, 14, 16, 0),
        ),
      ]);

  void acknowledge(String id) {
    state = [
      for (final alarm in state)
        if (alarm.id == id)
          alarm.copyWith(
            isAcknowledged: true,
            comments: [
              ...alarm.comments,
              MockAlarmComment(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                authorName: 'System',
                initials: 'SY',
                text: 'Alarm was acknowledged by John Doe',
                createdTime: DateTime.now(),
                isSystem: true,
              ),
            ],
          )
        else
          alarm,
    ];
  }

  void clear(String id) {
    state = [
      for (final alarm in state)
        if (alarm.id == id)
          alarm.copyWith(
            isActive: false,
            comments: [
              ...alarm.comments,
              MockAlarmComment(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                authorName: 'System',
                initials: 'SY',
                text: 'Alarm was cleared by John Doe',
                createdTime: DateTime.now(),
                isSystem: true,
              ),
            ],
          )
        else
          alarm,
    ];
  }

  void assign(String id, String? assigneeName) {
    state = [
      for (final alarm in state)
        if (alarm.id == id)
          alarm.copyWith(assigneeName: assigneeName)
        else
          alarm,
    ];
  }

  void addComment(String id, String text, String authorName, String initials) {
    if (text.trim().isEmpty) return;
    state = [
      for (final alarm in state)
        if (alarm.id == id)
          alarm.copyWith(
            comments: [
              ...alarm.comments,
              MockAlarmComment(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                authorName: authorName,
                initials: initials,
                text: text.trim(),
                createdTime: DateTime.now(),
              ),
            ],
          )
        else
          alarm,
    ];
  }
}

final alarmsProvider =
    StateNotifierProvider<AlarmsStateNotifier, List<MockAlarm>>((ref) {
      return AlarmsStateNotifier();
    });

final deviceProfilesProvider = Provider<List<MockDeviceProfile>>((ref) {
  return const [
    MockDeviceProfile(
      id: 'dp-1',
      name: 'Thermostat',
      activeCount: 4,
      inactiveCount: 1,
    ),
    MockDeviceProfile(
      id: 'dp-2',
      name: 'Energy Meter',
      activeCount: 3,
      inactiveCount: 0,
    ),
    MockDeviceProfile(
      id: 'dp-3',
      name: 'GPS Tracker',
      activeCount: 2,
      inactiveCount: 1,
    ),
    MockDeviceProfile(
      id: 'dp-4',
      name: 'Water Sensor',
      activeCount: 2,
      inactiveCount: 1,
    ),
  ];
});

final devicesProvider = Provider<List<MockDevice>>((ref) {
  return [
    MockDevice(
      id: 'dev-1',
      name: 'Thermostat-Floor-1',
      label: 'Main Lobby HVAC',
      type: 'Thermostat',
      active: true,
      createdTime: DateTime(2026, 10, 12),
      customerName: 'Acme Smart Buildings',
      telemetry: {
        'temperature': '21.8 °C',
        'humidity': '46 %',
        'targetTemp': '22.0 °C',
        'rssi': '-58 dBm',
      },
    ),
    MockDevice(
      id: 'dev-2',
      name: 'Thermostat-Floor-3',
      label: 'Server Room Adjunct',
      type: 'Thermostat',
      active: true,
      createdTime: DateTime(2026, 10, 14),
      customerName: 'Acme Smart Buildings',
      telemetry: {
        'temperature': '31.2 °C',
        'humidity': '52 %',
        'targetTemp': '21.0 °C',
        'rssi': '-64 dBm',
      },
    ),
    MockDevice(
      id: 'dev-3',
      name: 'Thermostat-Warehouse',
      label: 'Storage East Wing',
      type: 'Thermostat',
      active: false,
      createdTime: DateTime(2026, 9, 20),
      customerName: 'Global Cold Logistics',
      telemetry: {
        'temperature': '18.0 °C',
        'humidity': '41 %',
        'targetTemp': '18.0 °C',
        'rssi': 'Offline',
      },
    ),
    MockDevice(
      id: 'dev-4',
      name: 'EM-Main-Feeder-01',
      label: 'Substation Panel A',
      type: 'Energy Meter',
      active: true,
      createdTime: DateTime(2026, 10, 1),
      customerName: 'Metro Energy Grid',
      telemetry: {
        'voltage': '231.2 V',
        'current': '18.4 A',
        'power': '4.25 kW',
        'energy': '1428.5 kWh',
      },
    ),
    MockDevice(
      id: 'dev-5',
      name: 'GPS-Tracker-Van-04',
      label: 'Delivery Fleet #04',
      type: 'GPS Tracker',
      active: true,
      createdTime: DateTime(2026, 10, 22),
      customerName: 'Global Cold Logistics',
      telemetry: {
        'latitude': '37.7749',
        'longitude': '-122.4194',
        'speed': '58 km/h',
        'batteryLevel': '14 %',
      },
    ),
    MockDevice(
      id: 'dev-6',
      name: 'Water-Pump-Station-2',
      label: 'North Reservoir Intake',
      type: 'Water Sensor',
      active: false,
      createdTime: DateTime(2026, 8, 19),
      customerName: 'City Water Works',
      telemetry: {
        'flowRate': '0.0 L/min',
        'pressure': '1.1 bar',
        'ph': '7.1',
        'status': 'Standby',
      },
    ),
  ];
});

final customersProvider = Provider<List<MockCustomer>>((ref) {
  return [
    MockCustomer(
      id: 'cust-1',
      title: 'Acme Smart Buildings',
      country: 'United States',
      city: 'San Francisco',
      state: 'CA',
      zip: '94105',
      address: '415 Mission Street, Suite 2400',
      address2: 'Floor 24',
      phone: '+1 415-890-2210',
      email: 'ops@acmesmartbuildings.io',
      createdTime: DateTime(2026, 6, 15),
    ),
    MockCustomer(
      id: 'cust-2',
      title: 'Global Cold Logistics',
      country: 'Germany',
      city: 'Hamburg',
      state: 'HH',
      zip: '20457',
      address: 'Am Sandtorkai 50',
      address2: 'Port Terminal B',
      phone: '+49 40 3198-0',
      email: 'fleet@globalcold.de',
      createdTime: DateTime(2026, 7, 2),
    ),
    MockCustomer(
      id: 'cust-3',
      title: 'Metro Energy Grid',
      country: 'United Kingdom',
      city: 'London',
      state: 'Greater London',
      zip: 'EC2A 4NE',
      address: '22 Bishopsgate',
      address2: '',
      phone: '+44 20 7946 0921',
      email: 'noc@metroenergy.co.uk',
      createdTime: DateTime(2026, 8, 11),
    ),
    MockCustomer(
      id: 'cust-4',
      title: 'City Water Works',
      country: 'Singapore',
      city: 'Singapore',
      state: 'Central',
      zip: '018989',
      address: '10 Marina Boulevard',
      address2: 'Tower 2',
      phone: '+65 6788 1200',
      email: 'scada@citywater.sg',
      createdTime: DateTime(2026, 9, 5),
    ),
  ];
});

final assetsProvider = Provider<List<MockAsset>>((ref) {
  return [
    MockAsset(
      id: 'asset-1',
      name: 'Headquarters Building A',
      type: 'Building',
      label: 'Corporate HQ - 12 Floors',
      customerName: 'Acme Smart Buildings',
      createdTime: DateTime(2026, 6, 20),
    ),
    MockAsset(
      id: 'asset-2',
      name: 'Cold Storage Warehouse #2',
      type: 'Warehouse',
      label: 'Frozen Goods Facility',
      customerName: 'Global Cold Logistics',
      createdTime: DateTime(2026, 7, 12),
    ),
    MockAsset(
      id: 'asset-3',
      name: 'Solar Substation North',
      type: 'Substation',
      label: '25MW Grid Tie',
      customerName: 'Metro Energy Grid',
      createdTime: DateTime(2026, 8, 18),
    ),
    MockAsset(
      id: 'asset-4',
      name: 'Reservoir Pumping Zone 1',
      type: 'Water Station',
      label: 'Primary Treatment Plant',
      customerName: 'City Water Works',
      createdTime: DateTime(2026, 9, 10),
    ),
  ];
});

final auditLogsProvider = Provider<List<MockAuditLog>>((ref) {
  return [
    MockAuditLog(
      id: 'log-1',
      entityName: 'Thermostat-Floor-3',
      entityType: 'Device',
      actionType: 'Attributes updated',
      isSuccess: true,
      createdTime: DateTime(2026, 11, 17, 14, 30),
      actionData: {
        'scope': 'SHARED_SCOPE',
        'attributes': {
          'targetTemp': 21.0,
          'fanMode': 'AUTO',
          'updatedBy': 'tenant@thingsboard.org',
        },
      },
    ),
    MockAuditLog(
      id: 'log-2',
      entityName: 'High Temperature',
      entityType: 'Alarm',
      actionType: 'Alarm acknowledged',
      isSuccess: true,
      createdTime: DateTime(2026, 11, 17, 12, 5),
      actionData: {
        'alarmId': 'alarm-2',
        'severity': 'MAJOR',
        'acknowledgedBy': 'John Doe',
      },
    ),
    MockAuditLog(
      id: 'log-3',
      entityName: 'Water-Pump-Station-2',
      entityType: 'Device',
      actionType: 'RPC call',
      isSuccess: false,
      createdTime: DateTime(2026, 11, 16, 19, 32),
      actionData: {
        'method': 'setPumpState',
        'params': {'enabled': true, 'rpm': 1800},
      },
      failureDetails:
          'TimeoutException: Device Water-Pump-Station-2 did not respond within 5000ms.',
    ),
    MockAuditLog(
      id: 'log-4',
      entityName: 'Smart Office Monitoring',
      entityType: 'Dashboard',
      actionType: 'Updated',
      isSuccess: true,
      createdTime: DateTime(2026, 11, 15, 10, 20),
      actionData: {
        'dashboardId': 'dash-1',
        'title': 'Smart Office Monitoring',
        'widgetsCount': 12,
      },
    ),
  ];
});

class NotificationsStateNotifier
    extends StateNotifier<List<MockNotificationItem>> {
  NotificationsStateNotifier()
    : super([
        MockNotificationItem(
          id: 'notif-1',
          subject: 'New Critical Alarm: High Temperature',
          text:
              'Originator: Thermostat-Floor-3 reported 31.2 °C (threshold: 30.0 °C).',
          createdTime: DateTime.now().subtract(const Duration(minutes: 14)),
          isRead: false,
          severity: AlarmSeverityType.critical,
          icon: Icons.warning_amber_rounded,
        ),
        MockNotificationItem(
          id: 'notif-2',
          subject: 'Low Battery on GPS-Tracker-Van-04',
          text: 'Battery level dropped to 14%. Please schedule charging.',
          createdTime: DateTime.now().subtract(const Duration(hours: 2)),
          isRead: false,
          severity: AlarmSeverityType.major,
          icon: Icons.battery_alert_outlined,
        ),
        MockNotificationItem(
          id: 'notif-3',
          subject: 'Device Disconnected: Water-Pump-Station-2',
          text: 'Telemetry heartbeat timeout detected on North Reservoir.',
          createdTime: DateTime.now().subtract(const Duration(hours: 18)),
          isRead: true,
          severity: AlarmSeverityType.warning,
          icon: Icons.cloud_off_outlined,
        ),
        MockNotificationItem(
          id: 'notif-4',
          subject: 'Endpoint Connected: thingsboard.democloud.xyz',
          text: 'Mobile application workspace initialized with DemoCloud PE.',
          createdTime: DateTime.now().subtract(const Duration(days: 1)),
          isRead: true,
          icon: Icons.info_outline,
        ),
      ]);

  void markAsRead(String id) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(isRead: true) else item,
    ];
  }

  void markAllAsRead() {
    state = [for (final item in state) item.copyWith(isRead: true)];
  }

  void deleteNotification(String id) {
    state = [
      for (final item in state)
        if (item.id != id) item,
    ];
  }

  void deleteSelected(Set<String> ids) {
    state = [
      for (final item in state)
        if (!ids.contains(item.id)) item,
    ];
  }

  void markSelectedAsRead(Set<String> ids) {
    state = [
      for (final item in state)
        if (ids.contains(item.id)) item.copyWith(isRead: true) else item,
    ];
  }
}

final notificationsProvider = StateNotifierProvider<
  NotificationsStateNotifier,
  List<MockNotificationItem>
>((ref) {
  return NotificationsStateNotifier();
});

class UserProfileNotifier extends StateNotifier<MockUserProfile> {
  UserProfileNotifier() : super(const MockUserProfile());

  void updateProfile(MockUserProfile updated) {
    state = updated;
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, MockUserProfile>((ref) {
      return UserProfileNotifier();
    });
