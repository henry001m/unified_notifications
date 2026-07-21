import '../models/unified_notification_event.dart';

abstract class NotificationRouter {
  Future<void> handle(UnifiedNotificationEvent event);

  Map<String, String> get routeMap;
}
