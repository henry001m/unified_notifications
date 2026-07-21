import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../contracts/notification_store.dart';
import '../models/unified_notification_event.dart';

class HiveNotificationStore implements NotificationStore {
  HiveNotificationStore({required this.boxName}) : _box = Hive.box(boxName);

  final String boxName;
  final Box _box;

  static const String _inboxKey = 'notificaciones';
  static const String _pendingKey = 'pending_queue';
  static const String _deliveredKey = 'recent_delivered';
  static const String _openedKey = 'recent_opened';

  @override
  Future<void> clearAll() async {
    await _box.delete(_inboxKey);
    await _box.delete(_pendingKey);
    await _box.delete(_deliveredKey);
    await _box.delete(_openedKey);
  }

  @override
  Future<void> clearGroup(String groupKey) async {
    final inbox = await getInbox();
    final filtered = inbox.where((item) => item.groupKey != groupKey).toList();
    await _writeInbox(filtered);
  }

  @override
  Future<List<UnifiedNotificationEvent>> drainPendingEvents() async {
    final events = await _readEventList(_pendingKey);
    await _box.delete(_pendingKey);
    return events;
  }

  @override
  Future<void> enqueuePendingEvent(UnifiedNotificationEvent event) async {
    final events = await _readEventList(_pendingKey);
    events.removeWhere((item) => item.eventId == event.eventId);
    events.add(event);
    await _writeEventList(_pendingKey, events);
  }

  @override
  Future<List<UnifiedNotificationEvent>> getInbox() async {
    return _readEventList(_inboxKey);
  }

  @override
  Future<int> getInboxCount() async {
    return (await getInbox()).length;
  }

  @override
  Future<int> getUnreadCount() async {
    final inbox = await getInbox();
    return inbox.where((item) => !item.isRead).length;
  }

  @override
  Future<void> markAllRead() async {
    final inbox = await getInbox();
    final updated = inbox.map((item) => item.markAsRead()).toList();
    await _writeInbox(updated);
  }

  @override
  Future<void> updateItem(UnifiedNotificationEvent event) async {
    final inbox = await getInbox();
    final index = inbox.indexWhere((item) => item.eventId == event.eventId);
    if (index == -1) return;
    inbox[index] = event;
    await _writeInbox(inbox);
  }

  @override
  Future<void> markOpened(String eventId) async {
    await registerOpened(eventId);
  }

  @override
  Future<void> registerDelivered(String eventId) async {
    await _writeRecent(_deliveredKey, eventId);
  }

  @override
  Future<void> registerOpened(String eventId) async {
    await _writeRecent(_openedKey, eventId);
  }

  @override
  Future<void> saveInboxEvent(UnifiedNotificationEvent event) async {
    final events = await _readEventList(_inboxKey);
    events.removeWhere((item) => item.eventId == event.eventId);
    events.add(event);
    events.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    await _writeInbox(events);
  }

  @override
  Future<bool> wasRecentlyDelivered(String eventId) async {
    return _containsRecent(_deliveredKey, eventId);
  }

  @override
  Future<bool> wasRecentlyOpened(String eventId) async {
    return _containsRecent(_openedKey, eventId);
  }

  Future<void> _writeInbox(List<UnifiedNotificationEvent> events) async {
    await _writeEventList(_inboxKey, events);
    unawaited(_emitBoxChange());
  }

  Future<void> _emitBoxChange() async {
    final json = jsonEncode(
      (await _readEventList(_inboxKey)).map((e) => e.toJson()).toList(),
    );
    await _box.put(_inboxKey, json);
  }

  Future<List<UnifiedNotificationEvent>> _readEventList(String key) async {
    final raw = _box.get(key)?.toString();
    if (raw == null || raw.isEmpty) return <UnifiedNotificationEvent>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <UnifiedNotificationEvent>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => UnifiedNotificationEvent.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return <UnifiedNotificationEvent>[];
    }
  }

  Future<void> _writeEventList(
    String key,
    List<UnifiedNotificationEvent> events,
  ) async {
    await _box.put(
      key,
      jsonEncode(events.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _writeRecent(String key, String eventId) async {
    final raw = _box.get(key)?.toString();
    final map = <String, int>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            map[entry.key.toString()] = (entry.value as num).toInt();
          }
        }
      } catch (_) {}
    }
    final now = DateTime.now();
    map.removeWhere(
      (_, value) =>
          now.difference(DateTime.fromMillisecondsSinceEpoch(value)) >
          const Duration(minutes: 10),
    );
    map[eventId] = now.millisecondsSinceEpoch;
    await _box.put(key, jsonEncode(map));
  }

  Future<bool> _containsRecent(String key, String eventId) async {
    final raw = _box.get(key)?.toString();
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final now = DateTime.now();
      for (final entry in decoded.entries) {
        final timestamp = (entry.value as num).toInt();
        if (now.difference(DateTime.fromMillisecondsSinceEpoch(timestamp)) >
            const Duration(minutes: 10)) {
          continue;
        }
        if (entry.key.toString() == eventId) return true;
      }
    } catch (_) {}
    return false;
  }
}
