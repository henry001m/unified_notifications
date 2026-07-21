import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/unified_notification_config.dart';
import '../contracts/notification_renderer.dart';
import '../models/unified_notification_event.dart';
import '../storage/notification_store_keys.dart';
import 'android_channel_manager.dart';

const Set<String> _availableCustomSounds = {
  'boecoin',
  'boecoins',
  'cupon',
  'garantiaaceptada',
  'garantiaaprobada',
  'garantiafabrica',
  'garantianormal',
  'garantiarechazada',
  'reclamo',
  'wallet',
  'walletdescuento',
};

const String _foregroundChannelId = 'unified_emqx_foreground_service';
const String _foregroundChannelName = 'Notification Sync';
const String _deliveryChannelId = 'unified_emqx_delivery';
const String _deliveryChannelName = 'Notifications';

class LocalNotificationRenderer implements NotificationRenderer {
  LocalNotificationRenderer({required this.config})
      : _channelManager = AndroidChannelManager(_plugin);

  final UnifiedNotificationConfig config;
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AndroidChannelManager _channelManager;
  static bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final androidSettings =
        AndroidInitializationSettings(config.android.iconResource);
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );

    await _plugin.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        _foregroundChannelId,
        _foregroundChannelName,
        description: 'Silent channel for background notification service',
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        _deliveryChannelId,
        _deliveryChannelName,
        description: 'Notification delivery channel',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    await androidImplementation?.requestNotificationsPermission();

    final iosImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    _initialized = true;
  }

  Future<void> ensureForegroundChannel() async {
    await _channelManager.ensureChannel(
      channelId: _foregroundChannelId,
      channelName: _foregroundChannelName,
      description: 'Silent channel for background service',
      importance: Importance.min,
    );
  }

  @override
  Future<void> clearAll() => _plugin.cancelAll();

  @override
  Future<void> clearGroup(String groupKey) async {
    final removedIds = await _removeDisplayedNotificationIds(groupKey);
    for (final id in removedIds) {
      await _plugin.cancel(id);
    }
    await _plugin.cancel(_summaryId(groupKey));
  }

  @override
  Future<void> show(UnifiedNotificationEvent event) async {
    final notificationId = event.eventId.hashCode & 0x7fffffff;

    if (!await _tryReserveEventId(event.eventId)) {
      debugPrint(
        '[Notifications] Notificación local omitida por deduplicación | event_id=${event.eventId}',
      );
      return;
    }

    final groupKey = event.groupKey;
    final rawSound = event.sound;
    final androidSound = _resolveAndroidSoundName(rawSound);
    final iosSound = _resolveIosSoundName(rawSound);
    final channelId = _resolveDeliveryChannelId(androidSound);
    final channelName = _resolveDeliveryChannelName(androidSound);

    try {
      await _ensureAndroidDeliveryChannel(
        channelId: channelId,
        channelName: channelName,
        androidSound: androidSound,
      );

      await _plugin.show(
        notificationId,
        event.effectiveTitle,
        event.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'Notification delivery channel',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            sound: androidSound != null
                ? RawResourceAndroidNotificationSound(androidSound)
                : null,
            enableVibration: true,
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.message,
            ticker: event.effectiveTitle,
            channelShowBadge: true,
            audioAttributesUsage: AudioAttributesUsage.notification,
            groupKey: groupKey,
            setAsGroupSummary: false,
            groupAlertBehavior: GroupAlertBehavior.children,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
            sound: iosSound,
            threadIdentifier: groupKey,
          ),
        ),
        payload: jsonEncode(event.toJson()),
      );

      await _persistDisplayedNotificationId(groupKey, notificationId);
      await _showAndroidGroupSummary(
        groupKey: groupKey,
        summaryTitle: event.effectiveTitle,
      );
    } on Exception catch (e) {
      debugPrint('[Notifications] Error con sonido personalizado, usando default: $e');

      await _ensureAndroidDeliveryChannel(
        channelId: _deliveryChannelId,
        channelName: _deliveryChannelName,
      );

      await _plugin.show(
        notificationId,
        event.effectiveTitle,
        event.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _deliveryChannelId,
            _deliveryChannelName,
            channelDescription: 'Notification delivery channel',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.message,
            ticker: event.effectiveTitle,
            channelShowBadge: true,
            audioAttributesUsage: AudioAttributesUsage.notification,
            groupKey: groupKey,
            setAsGroupSummary: false,
            groupAlertBehavior: GroupAlertBehavior.children,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
            threadIdentifier: groupKey,
          ),
        ),
        payload: jsonEncode(event.toJson()),
      );

      await _persistDisplayedNotificationId(groupKey, notificationId);
      await _showAndroidGroupSummary(
        groupKey: groupKey,
        summaryTitle: event.effectiveTitle,
      );
    }
  }

  Future<void> _showAndroidGroupSummary({
    required String groupKey,
    required String summaryTitle,
  }) async {
    if (!Platform.isAndroid) return;

    final registry = await _readDisplayedNotificationRegistry();
    final totalNotifications = registry[groupKey]?.length ?? 0;
    if (totalNotifications <= 0) {
      await _plugin.cancel(_summaryId(groupKey));
      return;
    }

    final summaryId = _summaryId(groupKey);
    final summaryText =
        '$totalNotifications notificacion${totalNotifications == 1 ? "" : "es"}';

    await _plugin.show(
      summaryId,
      summaryTitle,
      summaryText,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _deliveryChannelId,
          _deliveryChannelName,
          channelDescription: 'Notification delivery channel',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          channelShowBadge: true,
          category: AndroidNotificationCategory.status,
          groupKey: groupKey,
          setAsGroupSummary: true,
          groupAlertBehavior: GroupAlertBehavior.children,
          styleInformation: InboxStyleInformation(
            const <String>[],
            summaryText: summaryText,
          ),
        ),
      ),
    );
  }

  Future<void> _ensureAndroidDeliveryChannel({
    required String channelId,
    required String channelName,
    String? androidSound,
  }) async {
    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        channelName,
        description: 'Notification delivery channel',
        importance: Importance.max,
        playSound: true,
        sound: androidSound != null
            ? RawResourceAndroidNotificationSound(androidSound)
            : null,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  Future<bool> _tryReserveEventId(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      NotificationStoreKeys.recentlyDeliveredEventIds,
    );
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
      (_, timestamp) =>
          now.difference(DateTime.fromMillisecondsSinceEpoch(timestamp)) >
          const Duration(minutes: 10),
    );

    if (map.containsKey(eventId)) return false;

    map[eventId] = now.millisecondsSinceEpoch;
    await prefs.setString(
      NotificationStoreKeys.recentlyDeliveredEventIds,
      jsonEncode(map),
    );
    return true;
  }

  Future<void> _persistDisplayedNotificationId(
    String groupKey,
    int notificationId,
  ) async {
    final registry = await _readDisplayedNotificationRegistry();
    final ids = registry[groupKey] ?? <int>[];
    if (!ids.contains(notificationId)) {
      ids.add(notificationId);
    }
    registry[groupKey] = ids;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      NotificationStoreKeys.displayedIdsByGroup,
      jsonEncode(registry),
    );
  }

  Future<Map<String, List<int>>> _readDisplayedNotificationRegistry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NotificationStoreKeys.displayedIdsByGroup);
    if (raw == null || raw.isEmpty) {
      return <String, List<int>>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, List<int>>{};
      return decoded.map((key, value) {
        final ids = <int>[];
        if (value is List) {
          for (final item in value) {
            if (item is int) {
              ids.add(item);
            } else if (item is num) {
              ids.add(item.toInt());
            }
          }
        }
        return MapEntry(key.toString(), ids);
      });
    } catch (_) {
      return <String, List<int>>{};
    }
  }

  Future<List<int>> _removeDisplayedNotificationIds(String groupKey) async {
    final registry = await _readDisplayedNotificationRegistry();
    final removed = registry.remove(groupKey) ?? <int>[];
    final prefs = await SharedPreferences.getInstance();
    if (registry.isEmpty) {
      await prefs.remove(NotificationStoreKeys.displayedIdsByGroup);
    } else {
      await prefs.setString(
        NotificationStoreKeys.displayedIdsByGroup,
        jsonEncode(registry),
      );
    }
    return removed;
  }

  int _summaryId(String groupKey) =>
      ('unified_summary_$groupKey').hashCode & 0x7fffffff;

  String? _resolveAndroidSoundName(String? rawSound) {
    final sound = rawSound?.trim();
    if (sound == null || sound.isEmpty) return null;
    final normalized = sound
        .toLowerCase()
        .replaceAll(RegExp(r'\.(wav|mp3|ogg|caf|aiff)$'), '');
    if (normalized.isEmpty) return null;
    return _availableCustomSounds.contains(normalized) ? normalized : null;
  }

  String? _resolveIosSoundName(String? rawSound) {
    final sound = rawSound?.trim();
    if (sound == null || sound.isEmpty) return null;
    final lower = sound.toLowerCase();
    if (lower.endsWith('.wav') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.caf') ||
        lower.endsWith('.aiff')) {
      final baseName = lower
          .replaceAll(RegExp(r'\.(wav|mp3|caf|aiff)$'), '')
          .trim();
      return _availableCustomSounds.contains(baseName) ? sound : null;
    }
    return _availableCustomSounds.contains(lower) ? '$sound.wav' : null;
  }

  String _resolveDeliveryChannelId(String? androidSound) {
    if (androidSound == null || androidSound.isEmpty) {
      return _deliveryChannelId;
    }
    return '${_deliveryChannelId}_$androidSound';
  }

  String _resolveDeliveryChannelName(String? androidSound) {
    if (androidSound == null || androidSound.isEmpty) {
      return _deliveryChannelName;
    }
    return '$_deliveryChannelName $androidSound';
  }
}
