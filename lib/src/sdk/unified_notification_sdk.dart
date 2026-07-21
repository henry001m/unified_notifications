import '../config/unified_notification_config.dart';
import '../models/notification_group.dart';
import '../models/notification_token_bundle.dart';
import '../models/unified_notification_event.dart';

abstract class UnifiedNotificationSdk {
  Future<void> init({required UnifiedNotificationConfig config});
  Future<void> login({required String userId});
  Future<void> logout();
  Future<void> enableNotifications();
  Future<void> disableNotifications();
  Future<String?> getFcmToken();
  Future<String?> getApnsToken();
  Future<String?> getOneSignalId();
  Future<String?> getOneSignalSubscripcionId();
  Future<NotificationTokenBundle> getTokenBundle();
  Future<String?> getCurrentUserId();
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);
  Future<void> clearNotifications();
  Future<void> clearNotificationGroup(String groupKey);
  Future<void> markNotificationAsOpened(String eventId);
  Future<void> markAllAsRead();
  Future<int> getUnreadCount();
  Future<List<UnifiedNotificationEvent>> getInbox();
  Future<List<NotificationGroup>> getGroupedInbox();
  Stream<UnifiedNotificationEvent> get onNotificationReceived;
  Stream<UnifiedNotificationEvent> get onNotificationOpened;
  Stream<NotificationTokenBundle> get onTokenUpdated;
  Stream<void> get onMqttConnected;
  Stream<void> get onMqttDisconnected;
  Stream<UnifiedNotificationEvent> get onMqttMessage;
  Stream<UnifiedNotificationEvent> get onAllEvents;
}
