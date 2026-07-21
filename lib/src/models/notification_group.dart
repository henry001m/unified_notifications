import 'unified_notification_event.dart';

class NotificationGroup {
  const NotificationGroup({
    required this.groupKey,
    required this.title,
    required this.items,
    required this.unreadCount,
    required this.lastEventAt,
  });

  final String groupKey;
  final String title;
  final List<UnifiedNotificationEvent> items;
  final int unreadCount;
  final DateTime lastEventAt;
}
