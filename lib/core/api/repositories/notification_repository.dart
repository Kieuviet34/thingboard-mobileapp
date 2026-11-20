import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/notification_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';

/// User notifications inbox, preferences, and mobile push session boundary.
abstract interface class NotificationRepository {
  Future<PageData<TbNotification>> getNotifications(
    PageQuery query, {
    bool unreadOnly = false,
    CancelToken? cancelToken,
  });

  Future<int> getUnreadCount();
  Future<void> markAsRead(String notificationId);
  Future<void> markAllAsRead();
  Future<void> deleteNotification(String notificationId);
  Future<TbUserNotificationSettings> getNotificationSettings();
  Future<TbUserNotificationSettings> saveNotificationSettings(
    TbUserNotificationSettings settings,
  );
  Future<void> registerMobileSession(String fcmToken);
  Future<void> removeMobileSession(String fcmToken);
}

final class RestNotificationRepository implements NotificationRepository {
  RestNotificationRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<PageData<TbNotification>> getNotifications(
    PageQuery query, {
    bool unreadOnly = false,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/notifications',
      queryParameters: <String, dynamic>{
        ...query.toQueryParameters(),
        'unreadOnly': unreadOnly,
      },
      cancelToken: cancelToken,
    );
    return PageData<TbNotification>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbNotification.fromJson,
    );
  }

  @override
  Future<int> getUnreadCount() async {
    final response = await _client.get<num>('/api/notifications/unread/count');
    return response.data?.toInt() ?? 0;
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _client.put<void>('/api/notification/$notificationId/read');
  }

  @override
  Future<void> markAllAsRead() async {
    await _client.put<void>('/api/notifications/read');
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    await _client.delete<void>('/api/notification/$notificationId');
  }

  @override
  Future<TbUserNotificationSettings> getNotificationSettings() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/notification/settings/user',
    );
    return TbUserNotificationSettings.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  @override
  Future<TbUserNotificationSettings> saveNotificationSettings(
    TbUserNotificationSettings settings,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/notification/settings/user',
      data: settings.toJson(),
    );
    return TbUserNotificationSettings.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  @override
  Future<void> registerMobileSession(String fcmToken) async {
    await _client.post<void>(
      '/api/user/mobile/session',
      data: <String, dynamic>{
        'fcmTokenTimestamp': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(headers: <String, dynamic>{'X-Mobile-Token': fcmToken}),
    );
  }

  @override
  Future<void> removeMobileSession(String fcmToken) async {
    await _client.delete<void>(
      '/api/user/mobile/session',
      options: Options(headers: <String, dynamic>{'X-Mobile-Token': fcmToken}),
    );
  }
}

final class DemoNotificationRepository implements NotificationRepository {
  DemoNotificationRepository(List<MockNotificationItem> seed)
    : _items = [
        for (final n in seed)
          TbNotification(
            id: n.id,
            subject: n.subject,
            text: n.text,
            createdTime: n.createdTime.millisecondsSinceEpoch,
            isRead: n.isRead,
            severity: switch (n.severity) {
              AlarmSeverityType.critical => AlarmSeverity.critical,
              AlarmSeverityType.major => AlarmSeverity.major,
              AlarmSeverityType.minor => AlarmSeverity.minor,
              AlarmSeverityType.warning => AlarmSeverity.warning,
              AlarmSeverityType.indeterminate => AlarmSeverity.indeterminate,
              null => null,
            },
          ),
      ];

  final List<TbNotification> _items;
  TbUserNotificationSettings _settings = demoNotificationSettings;

  @override
  Future<PageData<TbNotification>> getNotifications(
    PageQuery query, {
    bool unreadOnly = false,
    CancelToken? cancelToken,
  }) async {
    final search = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = _items
        .where((n) {
          if (unreadOnly && n.isRead) return false;
          if (search.isNotEmpty &&
              !n.subject.toLowerCase().contains(search) &&
              !n.text.toLowerCase().contains(search)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    return PageData<TbNotification>(
      data: filtered,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
    );
  }

  @override
  Future<int> getUnreadCount() async => _items.where((n) => !n.isRead).length;

  @override
  Future<void> markAsRead(String notificationId) async {
    final idx = _items.indexWhere((n) => n.id == notificationId);
    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(isRead: true);
    }
  }

  @override
  Future<void> markAllAsRead() async {
    for (var i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isRead: true);
    }
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    _items.removeWhere((n) => n.id == notificationId);
  }

  @override
  Future<TbUserNotificationSettings> getNotificationSettings() async =>
      _settings;

  @override
  Future<TbUserNotificationSettings> saveNotificationSettings(
    TbUserNotificationSettings settings,
  ) async {
    _settings = settings;
    return _settings;
  }

  @override
  Future<void> registerMobileSession(String fcmToken) async {}

  @override
  Future<void> removeMobileSession(String fcmToken) async {}
}
