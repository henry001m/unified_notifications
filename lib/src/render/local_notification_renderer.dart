import 'dart:async';
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

class LocalNotificationRenderer implements NotificationRenderer {
  LocalNotificationRenderer({required this.config})
      : _channelManager = AndroidChannelManager(_plugin);

  static const String _pendingOpenedEventsKey =
      'unified_notifications_pending_opened_local_events';

  final UnifiedNotificationConfig config;
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AndroidChannelManager _channelManager;
  static bool _initialized = false;
  static final _openedController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  static final List<UnifiedNotificationEvent> _pendingOpened = [];

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
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _handleBackgroundNotificationResponse,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _emitTapResponse(launchResponse, persistAsPending: true);
    }

    await _consumePendingOpenedFromStorage();

    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(
      AndroidNotificationChannel(
        config.android.foregroundChannelId,
        config.android.foregroundChannelName,
        description: config.android.foregroundNotificationContent,
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    await androidImplementation?.createNotificationChannel(
      AndroidNotificationChannel(
        config.android.defaultChannelId,
        config.android.defaultChannelName,
        description: config.android.defaultChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    // Los permisos deben solicitarse desde el flujo principal de la app
    // mediante los bridges de FCM/APNs. Pedir permisos desde este renderer
    // puede fallar en isolates de background (por ejemplo, en Android con
    // firebaseMessagingBackgroundHandler) porque no siempre hay Activity
    // disponible para plugins como flutter_local_notifications.

    _initialized = true;
  }

  @override
  Stream<UnifiedNotificationEvent> get onNotificationTap =>
      _openedController.stream;

  @override
  List<UnifiedNotificationEvent> takePendingOpened() {
    final items = List<UnifiedNotificationEvent>.from(_pendingOpened);
    _pendingOpened.clear();
    return items;
  }

  Future<void> ensureForegroundChannel() async {
    await _channelManager.ensureChannel(
      channelId: config.android.foregroundChannelId,
      channelName: config.android.foregroundChannelName,
      description: config.android.foregroundNotificationContent,
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
            channelDescription: config.android.defaultChannelDescription,
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
        channelId: config.android.defaultChannelId,
        channelName: config.android.defaultChannelName,
      );

      await _plugin.show(
        notificationId,
        event.effectiveTitle,
        event.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            config.android.defaultChannelId,
            config.android.defaultChannelName,
            channelDescription: config.android.defaultChannelDescription,
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
          config.android.defaultChannelId,
          config.android.defaultChannelName,
          channelDescription: config.android.defaultChannelDescription,
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
        description: config.android.defaultChannelDescription,
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

  static void _handleNotificationResponse(NotificationResponse response) {
    _emitTapResponse(response, persistAsPending: false);
  }

  @pragma('vm:entry-point')
  static void _handleBackgroundNotificationResponse(
    NotificationResponse response,
  ) {
    _emitTapResponse(response, persistAsPending: true);
  }

  static void _emitTapResponse(
    NotificationResponse response, {
    required bool persistAsPending,
  }) {
    final event = _decodeEventFromPayload(response.payload);
    if (event == null) {
      debugPrint(
        '[Notifications] Tap de notificación local ignorado por payload vacío o inválido.',
      );
      return;
    }

    final normalized = event.copyWith(openedFromSystem: true);

    _pendingOpened.removeWhere(
      (existing) => existing.eventId == normalized.eventId,
    );
    _pendingOpened.add(normalized);
    _openedController.add(normalized);

    if (persistAsPending) {
      _persistPendingOpenedEvent(normalized);
    }
  }

  static UnifiedNotificationEvent? _decodeEventFromPayload(String? payload) {
    final normalizedPayload = payload?.trim();
    if (normalizedPayload == null || normalizedPayload.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(normalizedPayload);
      if (decoded is Map<String, dynamic>) {
        return UnifiedNotificationEvent.fromJson(decoded);
      }
      if (decoded is Map) {
        return UnifiedNotificationEvent.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (error) {
      debugPrint(
        '[Notifications] Error parseando payload de tap local: $error | payload=$payload',
      );
    }

    return null;
  }

  static Future<void> _persistPendingOpenedEvent(
    UnifiedNotificationEvent event,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_pendingOpenedEventsKey) ?? <String>[];
      final encodedEvent = jsonEncode(event.toJson());
      final next = current.where((item) {
        final existing = _decodeEventFromPayload(item);
        return existing?.eventId != event.eventId;
      }).toList(growable: true)
        ..add(encodedEvent);
      await prefs.setStringList(_pendingOpenedEventsKey, next);
    } catch (error) {
      debugPrint(
        '[Notifications] No se pudo persistir tap local pendiente: $error',
      );
    }
  }

  static Future<void> _consumePendingOpenedFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_pendingOpenedEventsKey) ?? <String>[];
      if (stored.isEmpty) {
        return;
      }

      await prefs.remove(_pendingOpenedEventsKey);

      for (final raw in stored) {
        final event = _decodeEventFromPayload(raw);
        if (event == null) continue;
        final normalized = event.copyWith(openedFromSystem: true);
        _pendingOpened.removeWhere(
          (existing) => existing.eventId == normalized.eventId,
        );
        _pendingOpened.add(normalized);
      }
    } catch (error) {
      debugPrint(
        '[Notifications] No se pudieron consumir taps locales pendientes: $error',
      );
    }
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
    return normalized.isEmpty ? null : normalized;
  }

  String? _resolveIosSoundName(String? rawSound) {
    final sound = rawSound?.trim();
    if (sound == null || sound.isEmpty) return null;
    final lower = sound.toLowerCase();
    if (lower.endsWith('.wav') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.caf') ||
        lower.endsWith('.aiff')) {
      return sound;
    }
    return '$sound.wav';
  }

  String _resolveDeliveryChannelId(String? androidSound) {
    if (androidSound == null || androidSound.isEmpty) {
      return config.android.defaultChannelId;
    }
    return '${config.android.defaultChannelId}_$androidSound';
  }

  String _resolveDeliveryChannelName(String? androidSound) {
    if (androidSound == null || androidSound.isEmpty) {
      return config.android.defaultChannelName;
    }
    return '${config.android.defaultChannelName} $androidSound';
  }
}
