import '../models/unified_notification_event.dart';

abstract class NotificationStore {
  Future<void> saveInboxEvent(UnifiedNotificationEvent event);
  Future<List<UnifiedNotificationEvent>> getInbox();
  Future<int> getInboxCount();
  Future<int> getUnreadCount();
  Future<void> markAllRead();
  Future<void> updateItem(UnifiedNotificationEvent event);
  Future<void> clearAll();
  Future<void> clearEvent(String eventId);
  Future<void> clearGroup(String groupKey);
  Future<void> enqueuePendingEvent(UnifiedNotificationEvent event);
  Future<List<UnifiedNotificationEvent>> drainPendingEvents();
  Future<void> markOpened(String eventId);
  Future<bool> wasRecentlyDelivered(String eventId);
  Future<void> registerDelivered(String eventId);
  Future<bool> wasRecentlyOpened(String eventId);
  Future<void> registerOpened(String eventId);
}
