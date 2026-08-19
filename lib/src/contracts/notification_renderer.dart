import '../models/unified_notification_event.dart';

abstract class NotificationRenderer {
  Future<void> initialize();
  Future<void> show(UnifiedNotificationEvent event);
  Future<void> clearAll();
  Future<void> clearEvent(String eventId);
  Future<void> clearGroup(String groupKey);
  Stream<UnifiedNotificationEvent> get onNotificationTap;
  List<UnifiedNotificationEvent> takePendingOpened();
}
