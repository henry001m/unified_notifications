import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../contracts/notification_store.dart';
import '../models/unified_notification_event.dart';
import 'notification_store_keys.dart';

class SharedPrefsNotificationStore implements NotificationStore {
  SharedPrefsNotificationStore({this.window = const Duration(minutes: 10)});

  final Duration window;

  Future<SharedPreferences> _prefs({bool reload = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (reload) {
      await prefs.reload();
    }
    return prefs;
  }

  @override
  Future<void> clearAll() async {
    final prefs = await _prefs();
    await prefs.remove(NotificationStoreKeys.inbox);
    await prefs.remove(NotificationStoreKeys.pending);
    await prefs.remove(NotificationStoreKeys.delivered);
    await prefs.remove(NotificationStoreKeys.opened);
    await prefs.remove(NotificationStoreKeys.displayedIdsByGroup);
    await prefs.remove(NotificationStoreKeys.recentlyDeliveredEventIds);
  }

  @override
  Future<void> clearEvent(String eventId) async {
    final inbox = await getInbox();
    inbox.removeWhere((item) => item.eventId == eventId);
    await _writeEventList(NotificationStoreKeys.inbox, inbox);

    final pending = await _readEventList(NotificationStoreKeys.pending);
    pending.removeWhere((item) => item.eventId == eventId);
    await _writeEventList(NotificationStoreKeys.pending, pending);
  }

  @override
  Future<void> clearGroup(String groupKey) async {
    final inbox = await getInbox();
    final filtered = inbox.where((item) => item.groupKey != groupKey).toList();
    await _writeEventList(NotificationStoreKeys.inbox, filtered);

    final pending = await _readEventList(NotificationStoreKeys.pending);
    final filteredPending =
        pending.where((item) => item.groupKey != groupKey).toList();
    await _writeEventList(NotificationStoreKeys.pending, filteredPending);
  }

  @override
  Future<List<UnifiedNotificationEvent>> drainPendingEvents() async {
    final events = await _readEventList(NotificationStoreKeys.pending);
    final prefs = await _prefs();
    await prefs.remove(NotificationStoreKeys.pending);
    return events;
  }

  @override
  Future<void> enqueuePendingEvent(UnifiedNotificationEvent event) async {
    final events = await _readEventList(NotificationStoreKeys.pending);
    events.removeWhere((item) => item.eventId == event.eventId);
    events.add(event);
    await _writeEventList(NotificationStoreKeys.pending, events);
  }

  @override
  Future<List<UnifiedNotificationEvent>> getInbox() async {
    return _readEventList(NotificationStoreKeys.inbox);
  }

  @override
  Future<int> getInboxCount() async {
    final inbox = await getInbox();
    return inbox.length;
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
    await _writeEventList(NotificationStoreKeys.inbox, updated);

    final pending = await _readEventList(NotificationStoreKeys.pending);
    final pendingUpdated = pending.map((item) => item.markAsRead()).toList();
    await _writeEventList(NotificationStoreKeys.pending, pendingUpdated);
  }

  @override
  Future<void> updateItem(UnifiedNotificationEvent event) async {
    final inbox = await getInbox();
    final index = inbox.indexWhere((item) => item.eventId == event.eventId);
    if (index == -1) return;
    inbox[index] = event;
    await _writeEventList(NotificationStoreKeys.inbox, inbox);
  }

  @override
  Future<void> markOpened(String eventId) async {
    final inbox = await getInbox();
    final index = inbox.indexWhere((item) => item.eventId == eventId);
    if (index != -1 && !inbox[index].isRead) {
      inbox[index] = inbox[index].markAsRead();
      await _writeEventList(NotificationStoreKeys.inbox, inbox);
    }

    final pending = await _readEventList(NotificationStoreKeys.pending);
    final pendingIndex = pending.indexWhere((item) => item.eventId == eventId);
    if (pendingIndex != -1) {
      pending[pendingIndex] = pending[pendingIndex].markAsRead();
      await _writeEventList(NotificationStoreKeys.pending, pending);
    }

    await registerOpened(eventId);
  }

  @override
  Future<void> registerDelivered(String eventId) async {
    await _writeRecent(NotificationStoreKeys.delivered, eventId);
  }

  @override
  Future<void> registerOpened(String eventId) async {
    await _writeRecent(NotificationStoreKeys.opened, eventId);
  }

  @override
  Future<void> saveInboxEvent(UnifiedNotificationEvent event) async {
    final events = await _readEventList(NotificationStoreKeys.inbox);
    final existingIndex = events.indexWhere((item) => item.eventId == event.eventId);
    final existing = existingIndex == -1 ? null : events[existingIndex];
    final normalizedEvent =
        existing != null && existing.isRead && !event.isRead
            ? event.markAsRead()
            : event;

    events.removeWhere((item) => item.eventId == event.eventId);
    events.add(normalizedEvent);
    events.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    await _writeEventList(NotificationStoreKeys.inbox, events);
  }

  @override
  Future<bool> wasRecentlyDelivered(String eventId) async {
    return _containsRecent(NotificationStoreKeys.delivered, eventId);
  }

  @override
  Future<bool> wasRecentlyOpened(String eventId) async {
    return _containsRecent(NotificationStoreKeys.opened, eventId);
  }

  Future<List<UnifiedNotificationEvent>> _readEventList(String key) async {
    final prefs = await _prefs(reload: true);
    final raw = prefs.getString(key);
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
    final prefs = await _prefs();
    await prefs.setString(
      key,
      jsonEncode(events.map((item) => item.toJson()).toList()),
    );
  }

  Future<Map<String, int>> _readRecent(String key) async {
    final prefs = await _prefs(reload: true);
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      return decoded.map(
        (dynamic rawKey, dynamic value) =>
            MapEntry(rawKey.toString(), (value as num).toInt()),
      );
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> _writeRecent(String key, String eventId) async {
    final prefs = await _prefs();
    final map = await _readRecent(key);
    final now = DateTime.now();
    map.removeWhere(
      (_, value) =>
          now.difference(DateTime.fromMillisecondsSinceEpoch(value)) > window,
    );
    map[eventId] = now.millisecondsSinceEpoch;
    await prefs.setString(key, jsonEncode(map));
  }

  Future<bool> _containsRecent(String key, String eventId) async {
    final map = await _readRecent(key);
    final now = DateTime.now();
    map.removeWhere(
      (_, value) =>
          now.difference(DateTime.fromMillisecondsSinceEpoch(value)) > window,
    );
    return map.containsKey(eventId);
  }
}
