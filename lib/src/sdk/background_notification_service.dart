import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/unified_notification_config.dart';
import '../core/notification_normalizer.dart';
import '../models/notification_source.dart';
import '../render/local_notification_renderer.dart';
import '../storage/notification_store_keys.dart';
import '../storage/shared_prefs_notification_store.dart';
import 'background_bootstrap.dart';

const String _eventConnectUser = 'unified_notif_connect_user';
const String _eventDisconnectUser = 'unified_notif_disconnect_user';
const String _eventNotificationReceived = 'unified_notif_received';
const String _eventNotificationOpened = 'unified_notif_opened';
const String _eventNotificationAck = 'unified_notif_ack';

class BackgroundNotificationService {
  BackgroundNotificationService._();

  static final BackgroundNotificationService instance =
      BackgroundNotificationService._();

  bool _initialized = false;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _openedSubscription;
  StreamSubscription? _ackSubscription;

  final StreamController<Map<String, dynamic>> _pendingEventsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _openedEventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onPendingEvent =>
      _pendingEventsController.stream;
  Stream<Map<String, dynamic>> get onOpenedEvent =>
      _openedEventsController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final config = await BackgroundBootstrap.loadConfig();
    if (config == null) return;

    await _listenServiceEvents();
  }

  Future<void> _listenServiceEvents() async {
    _messageSubscription?.cancel();
    _openedSubscription?.cancel();
    _ackSubscription?.cancel();

    final service = FlutterBackgroundService();

    _messageSubscription = service.on(_eventNotificationReceived).listen(
      (event) {
        if (event == null) return;
        _pendingEventsController.add(Map<String, dynamic>.from(event));
      },
    );

    _openedSubscription = service.on(_eventNotificationOpened).listen(
      (event) {
        if (event == null) return;
        _openedEventsController.add(Map<String, dynamic>.from(event));
      },
    );

    _ackSubscription = service.on(_eventNotificationAck).listen((event) async {
      final eventKey = event?['event_key']?.toString().trim();
      if (eventKey == null || eventKey.isEmpty) return;
      await _removePendingEvent(eventKey);
    });
  }

  Future<void> connectUser({
    required String userId,
    required String topicBase,
    required bool showSystemNotifications,
  }) async {
    FlutterBackgroundService().invoke(_eventConnectUser, {
      'user_id': userId,
      'topic_base': topicBase,
      'show_system_notifications': showSystemNotifications,
    });
  }

  Future<void> disconnectUser() async {
    FlutterBackgroundService().invoke(_eventDisconnectUser);
  }

  Future<void> ackNotification(String eventKey) async {
    FlutterBackgroundService().invoke(_eventNotificationAck, {
      'event_key': eventKey,
    });
  }

  Future<void> _removePendingEvent(String eventKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NotificationStoreKeys.pendingQueue);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final queue = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      queue.removeWhere(
        (item) =>
            item['event_id'] == eventKey || item['eventId'] == eventKey,
      );
      await prefs.setString(
        NotificationStoreKeys.pendingQueue,
        jsonEncode(queue),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> drainPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NotificationStoreKeys.pendingQueue);
    if (raw == null || raw.isEmpty) return [];

    await prefs.remove(NotificationStoreKeys.pendingQueue);

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _messageSubscription?.cancel();
    _openedSubscription?.cancel();
    _ackSubscription?.cancel();
    _pendingEventsController.close();
    _openedEventsController.close();
  }
}

@pragma('vm:entry-point')
Future<bool> _iosBackgroundHandler(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void unifiedNotificationsBackgroundEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final config = await BackgroundBootstrap.loadConfig();
  if (config == null) return;

  final renderer = LocalNotificationRenderer(config: config);
  await renderer.initialize();

  if (service is AndroidServiceInstance &&
      await service.isForegroundService()) {
    await service.setForegroundNotificationInfo(
      title: config.foregroundServiceNotificationTitle,
      content: config.foregroundServiceNotificationContent,
    );
  }

  final runtime = _BackgroundMqttRuntime(service, config);
  await runtime.initialize();
}

class _BackgroundMqttRuntime {
  _BackgroundMqttRuntime(this._service, this._config)
      : _store =
            SharedPrefsNotificationStore(window: _config.deduplicationWindow);

  final ServiceInstance _service;
  final UnifiedNotificationConfig _config;
  final SharedPrefsNotificationStore _store;
  final _normalizer = const NotificationNormalizer();

  MqttServerClient? _client;
  String? _currentUserId;
  late String _topicBase = _config.mqtt.topicBase;
  bool _showSystemNotifications = true;
  StreamSubscription? _updatesSubscription;

  Future<void> initialize() async {
    await _restorePersistedState();

    _service.on(_eventConnectUser).listen((event) async {
      final userId = event?['user_id']?.toString().trim();
      final topicBase = event?['topic_base']?.toString().trim();
      final showSystemNotifications =
          event?['show_system_notifications'] == true;

      if (userId == null || userId.isEmpty) return;

      _currentUserId = userId;
      if (topicBase != null && topicBase.isNotEmpty) {
        _topicBase = topicBase;
      }
      _showSystemNotifications = showSystemNotifications;
      await _persistState();
      await _connect();
    });

    _service.on(_eventDisconnectUser).listen((event) async {
      await _disconnect(clearPersistedState: true);
    });

    _service.on(_eventNotificationAck).listen((event) async {
      final eventKey = event?['event_key']?.toString().trim();
      if (eventKey == null || eventKey.isEmpty) return;
      await _removePendingEvent(eventKey);
    });

    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      await _connect();
    }
  }

  Future<void> _restorePersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getString(NotificationStoreKeys.notificationUserId);
    _topicBase =
        prefs.getString(NotificationStoreKeys.notificationTopicBase) ??
            _config.mqtt.topicBase;
    _showSystemNotifications =
        prefs.getBool(NotificationStoreKeys.showSystemNotificationsKey) ??
            true;
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      await prefs.setString(
        NotificationStoreKeys.notificationUserId,
        _currentUserId!,
      );
    }
    await prefs.setString(
      NotificationStoreKeys.notificationTopicBase,
      _topicBase,
    );
    await prefs.setBool(
      NotificationStoreKeys.showSystemNotificationsKey,
      _showSystemNotifications,
    );
  }

  Future<void> _connect() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;

    if (_isConnectedForUser(userId)) return;

    await _disconnect(clearPersistedState: false);

    final client = MqttServerClient.withPort(
      _config.mqtt.broker,
      userId,
      _config.mqtt.port,
    );

    client.logging(on: false);
    client.keepAlivePeriod = _config.mqtt.keepAliveSeconds;
    client.onConnected = () =>
        debugPrint('[Notifications BG] MQTT conectado | usr_id=$userId');
    client.onDisconnected = () =>
        debugPrint('[Notifications BG] MQTT desconectado | usr_id=$userId');
    client.onSubscribed = (topic) =>
        debugPrint('[Notifications BG] Suscrito a $topic');
    client.pongCallback = () =>
        debugPrint('[Notifications BG] Pong | usr_id=$userId');

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(userId)
        .startClean();

    try {
      await client.connect();
    } catch (e) {
      client.disconnect();
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      return;
    }

    _client = client;
    final topic = '$_topicBase/$userId';
    client.subscribe(topic, MqttQos.atLeastOnce);
    _updatesSubscription = client.updates?.listen(_handleMessage);

    if (_service is AndroidServiceInstance &&
        await _service.isForegroundService()) {
      await _service.setForegroundNotificationInfo(
        title: _config.foregroundServiceNotificationTitle,
        content: _config.foregroundServiceNotificationContent,
      );
    }

    debugPrint(
      '[Notifications BG] Conectado EMQX | usr_id=$userId | topic=$topic',
    );
  }

  Future<void> _disconnect({required bool clearPersistedState}) async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    _client?.disconnect();
    _client = null;

    if (clearPersistedState) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(NotificationStoreKeys.notificationUserId);
      await prefs.remove(NotificationStoreKeys.pendingQueue);
      _currentUserId = null;
    }
  }

  Future<void> _handleMessage(
    List<MqttReceivedMessage<MqttMessage?>>? messages,
  ) async {
    if (messages == null || messages.isEmpty) return;

    final publishMessage = messages.first.payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(
      publishMessage.payload.message,
    );

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;

      final event = _normalizer.normalize(
        decoded,
        source: NotificationSource.mqtt,
      );

      await _enqueuePendingEvent(event.toJson());
      await _store.saveInboxEvent(event);

      if (await _shouldSkipByRecentDelivery(event.eventId)) {
        _service.invoke(_eventNotificationReceived, event.toJson());
        return;
      }

      if (_showSystemNotifications) {
        final renderer = LocalNotificationRenderer(config: _config);
        await renderer.initialize();
        await renderer.show(event);
      }

      _service.invoke(_eventNotificationReceived, event.toJson());
    } catch (e) {
      debugPrint('[Notifications BG] Error procesando MQTT: $e');
    }
  }

  Future<void> _enqueuePendingEvent(Map<String, dynamic> eventJson) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NotificationStoreKeys.pendingQueue);
    var queue = <Map<String, dynamic>>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          queue = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } catch (_) {}
    }

    final eventId = eventJson['eventId'] ?? eventJson['event_id'];
    queue.removeWhere(
      (item) => item['event_id'] == eventId || item['eventId'] == eventId,
    );
    queue.add(eventJson);
    await prefs.setString(
      NotificationStoreKeys.pendingQueue,
      jsonEncode(queue),
    );
  }

  Future<void> _removePendingEvent(String eventKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NotificationStoreKeys.pendingQueue);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final queue = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      queue.removeWhere(
        (item) =>
            item['event_id'] == eventKey || item['eventId'] == eventKey,
      );
      await prefs.setString(
        NotificationStoreKeys.pendingQueue,
        jsonEncode(queue),
      );
    } catch (_) {}
  }

  Future<bool> _shouldSkipByRecentDelivery(String eventId) async {
    if (eventId.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(NotificationStoreKeys.recentlyDeliveredEventIds);
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

    final shouldSkip = map.containsKey(eventId);
    map[eventId] = now.millisecondsSinceEpoch;
    await prefs.setString(
      NotificationStoreKeys.recentlyDeliveredEventIds,
      jsonEncode(map),
    );
    return shouldSkip;
  }

  bool _isConnectedForUser(String userId) {
    return _client != null &&
        _currentUserId == userId &&
        _client?.connectionStatus?.state == MqttConnectionState.connected;
  }
}
