import '../contracts/notification_store.dart';
import '../models/unified_notification_event.dart';

class NotificationDeduplicator {
  const NotificationDeduplicator({required this.store});

  final NotificationStore store;

  Future<bool> shouldProcessReceived(UnifiedNotificationEvent event) async {
    if (event.eventId.isEmpty) return true;
    final exists = await store.wasRecentlyDelivered(event.eventId);
    if (exists) return false;
    await store.registerDelivered(event.eventId);
    return true;
  }

  Future<bool> shouldProcessOpened(UnifiedNotificationEvent event) async {
    if (event.eventId.isEmpty) return true;
    final exists = await store.wasRecentlyOpened(event.eventId);
    if (exists) return false;
    await store.registerOpened(event.eventId);
    return true;
  }

  bool shouldProcessReceivedSync(
    UnifiedNotificationEvent event,
    Map<String, DateTime> localCache,
  ) {
    if (event.eventId.isEmpty) return true;
    final now = DateTime.now();
    localCache.removeWhere(
      (_, t) => now.difference(t) > const Duration(minutes: 10),
    );
    if (localCache.containsKey(event.eventId)) return false;
    localCache[event.eventId] = now;
    if (localCache.length > 250) {
      final oldest = localCache.keys.first;
      localCache.remove(oldest);
    }
    return true;
  }
}
