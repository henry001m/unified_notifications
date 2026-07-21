import '../models/notification_token_bundle.dart';
import '../models/unified_notification_event.dart';

abstract class PushBridge {
  Future<void> initialize();
  Future<String?> getFcmToken();
  Future<String?> getApnsToken();
  Stream<UnifiedNotificationEvent> get onForegroundMessage;
  Stream<UnifiedNotificationEvent> get onOpenedMessage;
  Stream<NotificationTokenBundle> get onTokenRefresh;
}
