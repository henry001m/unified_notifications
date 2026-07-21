import 'package:collection/collection.dart';

import '../models/notification_group.dart';
import '../models/unified_notification_event.dart';

class NotificationGrouper {
  const NotificationGrouper();

  List<NotificationGroup> group(List<UnifiedNotificationEvent> events) {
    final grouped = groupBy(events, (UnifiedNotificationEvent event) {
      return event.groupKey;
    });

    return grouped.entries.map((entry) {
      final items = List<UnifiedNotificationEvent>.from(entry.value)
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      return NotificationGroup(
        groupKey: entry.key,
        title: items.first.effectiveTitle,
        items: items,
        unreadCount: items.length,
        lastEventAt: items.first.receivedAt,
      );
    }).toList()
      ..sort((a, b) => b.lastEventAt.compareTo(a.lastEventAt));
  }
}
