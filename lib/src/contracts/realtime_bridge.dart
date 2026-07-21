import '../models/unified_notification_event.dart';

abstract class RealtimeBridge {
  Future<void> connect({
    required String userId,
    required String topic,
  });

  Future<void> disconnect();
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);

  Stream<UnifiedNotificationEvent> get onMessage;
  Stream<void> get onConnected;
  Stream<void> get onDisconnected;
}
