import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridges/apns/apns_bridge.dart';
import '../bridges/fcm/fcm_bridge.dart';
import '../config/unified_notification_config.dart';
import '../contracts/notification_renderer.dart';
import '../contracts/notification_router.dart';
import '../contracts/notification_store.dart';
import '../contracts/realtime_bridge.dart';
import '../core/lifecycle_coordinator.dart';
import '../core/notification_deduplicator.dart';
import '../core/notification_grouper.dart';
import '../core/notification_visibility.dart';
import '../models/notification_group.dart';
import '../models/notification_source.dart';
import '../models/notification_token_bundle.dart';
import '../models/unified_notification_event.dart';
import 'background_bootstrap.dart';

class NotificationRuntime {
  NotificationRuntime({
    required this.config,
    required this.store,
    required this.renderer,
    required this.fcmBridge,
    required this.apnsBridge,
    required this.realtimeBridge,
    required this.router,
  }) : _deduplicator = NotificationDeduplicator(store: store);

  final UnifiedNotificationConfig config;
  final NotificationStore store;
  final NotificationRenderer renderer;
  final FcmBridge? fcmBridge;
  final ApnsBridge? apnsBridge;
  final RealtimeBridge realtimeBridge;
  final NotificationRouter? router;

  late final NotificationDeduplicator _deduplicator;
  final NotificationGrouper _grouper = const NotificationGrouper();
  final _receivedController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  final _openedController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  final _allEventsController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  final _tokenController =
      StreamController<NotificationTokenBundle>.broadcast();
  final List<UnifiedNotificationEvent> _pendingReceivedForSubscribers = [];
  final List<UnifiedNotificationEvent> _pendingOpenedForSubscribers = [];

  final Map<String, DateTime> _localReceivedCache = {};
  final Map<String, DateTime> _localOpenedCache = {};

  String? _currentUserId;
  bool _initialized = false;
  StreamSubscription<UnifiedNotificationEvent>? _fcmForegroundSub;
  StreamSubscription<UnifiedNotificationEvent>? _fcmOpenedSub;
  StreamSubscription<UnifiedNotificationEvent>? _apnsForegroundSub;
  StreamSubscription<UnifiedNotificationEvent>? _apnsOpenedSub;
  StreamSubscription<UnifiedNotificationEvent>? _mqttSub;
  StreamSubscription<void>? _mqttConnectedSub;
  StreamSubscription<void>? _mqttDisconnectedSub;
  StreamSubscription<NotificationTokenBundle>? _fcmTokenSub;
  StreamSubscription<NotificationTokenBundle>? _apnsTokenSub;
  StreamSubscription<UnifiedNotificationEvent>? _rendererTapSub;
  LifecycleCoordinator? _lifecycle;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await BackgroundBootstrap.saveConfig(config);
    await renderer.initialize();
    _rendererTapSub?.cancel();
    _rendererTapSub = renderer.onNotificationTap.listen((event) async {
      await _onOpened(
        event.copyWith(
          source: NotificationSource.localTap,
          openedFromSystem: true,
        ),
        'local_renderer',
      );
    });
    for (final event in renderer.takePendingOpened()) {
      await _onOpened(
        event.copyWith(
          source: NotificationSource.localTap,
          openedFromSystem: true,
        ),
        'local_renderer_pending',
      );
    }

    if (config.enableFcm && fcmBridge != null) {
      await fcmBridge!.initialize();
      _fcmForegroundSub = fcmBridge!.onForegroundMessage.listen(
        (event) => _onReceived(event, 'fcm'),
      );
      _fcmOpenedSub = fcmBridge!.onOpenedMessage.listen(
        (event) => _onOpened(event, 'fcm'),
      );
      _fcmTokenSub = fcmBridge!.onTokenRefresh.listen(_onTokensRefreshed);
      for (final event in fcmBridge!.takePendingReceived()) {
        await _onReceived(event, 'fcm_pending_received');
      }
      for (final event in fcmBridge!.takePendingOpened()) {
        await _onOpened(event, 'fcm_pending_opened');
      }
    }

    if (config.enableApns && apnsBridge != null) {
      await apnsBridge!.initialize();
      _apnsForegroundSub = apnsBridge!.onForegroundMessage.listen(
        (event) => _onReceived(event, 'apns'),
      );
      _apnsOpenedSub = apnsBridge!.onOpenedMessage.listen(
        (event) => _onOpened(event, 'apns'),
      );
      _apnsTokenSub = apnsBridge!.onTokenRefresh.listen(_onTokensRefreshed);
      for (final event in apnsBridge!.takePendingReceived()) {
        await _onReceived(event, 'apns_pending_received');
      }
      for (final event in apnsBridge!.takePendingOpened()) {
        await _onOpened(event, 'apns_pending_opened');
      }
    }

    _mqttSub = realtimeBridge.onMessage.listen(
      (event) => _onReceived(event, 'mqtt'),
    );
    _mqttConnectedSub = realtimeBridge.onConnected.listen((_) {});
    _mqttDisconnectedSub = realtimeBridge.onDisconnected.listen((_) {});

    _lifecycle?.dispose();
    _lifecycle = LifecycleCoordinator(
      onResumed: () async {
        await _synchronizePendingSources();
        await _ensureMqttConnected();
      },
      onBackgrounded: () async {
        // MQTT solo debe vivir en foreground. En iOS el socket puede quedar
        // abierto mientras el sistema suspende la app y el keepalive termina
        // escribiendo sobre una conexión rota.
        await realtimeBridge.disconnect();
      },
      onDetached: () async {
        await realtimeBridge.disconnect();
      },
    );
    _lifecycle!.register();

    await _synchronizePendingSources();
    await _emitTokens();
  }

  Future<void> _onReceived(
    UnifiedNotificationEvent event,
    String provider,
  ) async {
    final hiddenOwn = isHiddenOwnNotificationEvent(event);

    if (!_deduplicator.shouldProcessReceivedSync(event, _localReceivedCache)) {
      return;
    }

    if (!await _deduplicator.shouldProcessReceived(event)) {
      return;
    }

    if (!hiddenOwn &&
        config.enableSystemNotifications &&
        provider != 'background_mqtt' &&
        _shouldRenderSystemNotification(event, provider)) {
      await renderer.show(event);
    }

    if (!hiddenOwn) {
      await store.saveInboxEvent(event);
    }
    _pendingReceivedForSubscribers.removeWhere(
      (existing) => existing.eventId == event.eventId,
    );
    _pendingReceivedForSubscribers.add(event);
    _receivedController.add(event);
    _allEventsController.add(event);
    await config.onRawEvent?.call(event.toJson());
  }

  bool _shouldRenderSystemNotification(
    UnifiedNotificationEvent event,
    String provider,
  ) {
    if (provider == 'background_mqtt') {
      return false;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }

    switch (event.source) {
      case NotificationSource.apnsForeground:
      case NotificationSource.apnsOpened:
      case NotificationSource.fcmForeground:
      case NotificationSource.fcmBackground:
      case NotificationSource.fcmOpened:
        return false;
      case NotificationSource.mqtt:
        return !(config.enableApns || config.enableFcm);
      default:
        return true;
    }
  }

  Future<void> _onOpened(
    UnifiedNotificationEvent event,
    String provider,
  ) async {
    final hiddenOwn = isHiddenOwnNotificationEvent(event);

    if (!_deduplicator.shouldProcessReceivedSync(event, _localOpenedCache)) {
      return;
    }

    if (!await _deduplicator.shouldProcessOpened(event)) {
      return;
    }

    if (!hiddenOwn) {
      await store.saveInboxEvent(event);
      await store.markOpened(event.eventId);
    }
    _pendingOpenedForSubscribers.removeWhere(
      (existing) => existing.eventId == event.eventId,
    );
    _pendingOpenedForSubscribers.add(event);
    _openedController.add(event);
    _allEventsController.add(event);

    if (!hiddenOwn && router != null) {
      await router!.handle(event);
    }
  }

  void _onTokensRefreshed(NotificationTokenBundle bundle) {
    _tokenController.add(bundle);
  }

  Future<void> login(String userId) async {
    _currentUserId = userId.trim();
    await _ensureMqttConnected();
    await _emitTokens();
  }

  Future<void> logout() async {
    _currentUserId = null;
    await realtimeBridge.disconnect();
  }

  Future<void> _ensureMqttConnected() async {
    if (!config.enableMqtt ||
        _currentUserId == null ||
        _currentUserId!.isEmpty) {
      return;
    }

    final topic =
        config.mqttTopicResolver?.resolveTopic(
          userId: _currentUserId!,
          topicBase: config.mqtt.topicBase,
        ) ??
        '${config.mqtt.topicBase}/${_currentUserId!}';

    await realtimeBridge.connect(userId: _currentUserId!, topic: topic);
  }

  Future<void> _drainPendingQueue() async {
    final storePending = await store.drainPendingEvents();
    for (final event in storePending) {
      if (_deduplicator.shouldProcessReceivedSync(event, _localReceivedCache)) {
        if (!isHiddenOwnNotificationEvent(event)) {
          await store.saveInboxEvent(event);
        }
        _receivedController.add(event);
        _allEventsController.add(event);
      }
    }
  }

  Future<void> _synchronizePendingSources() async {
    if (apnsBridge != null) {
      final apnsPending = await apnsBridge!
          .consumePendingNativeEventsSynchronously();
      for (final event in apnsPending.received) {
        await _onReceived(event, 'apns_pending_sync');
      }
      for (final event in apnsPending.opened) {
        await _onOpened(event, 'apns_pending_sync');
      }
    }

    await _drainPendingQueue();
  }

  Future<void> _emitTokens() async {
    _tokenController.add(
      NotificationTokenBundle(
        fcmToken: await getFcmToken(),
        apnsToken: await getApnsToken(),
        providerToken: await getFcmToken(),
        currentUserId: _currentUserId,
      ),
    );
  }

  Future<String?> getFcmToken() =>
      fcmBridge?.getFcmToken() ?? Future.value(null);

  Future<String?> getApnsToken() =>
      apnsBridge?.getApnsToken() ??
      fcmBridge?.getApnsToken() ??
      Future.value(null);

  String? get currentUserId => _currentUserId;

  Stream<UnifiedNotificationEvent> get onReceived => _receivedController.stream;
  Stream<UnifiedNotificationEvent> get onOpened => _openedController.stream;
  Stream<UnifiedNotificationEvent> get onAllEvents =>
      _allEventsController.stream;
  Stream<NotificationTokenBundle> get onTokenUpdated => _tokenController.stream;

  List<UnifiedNotificationEvent> takePendingReceivedForSubscribers() {
    final items = List<UnifiedNotificationEvent>.from(
      _pendingReceivedForSubscribers,
    );
    _pendingReceivedForSubscribers.clear();
    return items;
  }

  List<UnifiedNotificationEvent> takePendingOpenedForSubscribers() {
    final items = List<UnifiedNotificationEvent>.from(
      _pendingOpenedForSubscribers,
    );
    _pendingOpenedForSubscribers.clear();
    return items;
  }

  Future<List<UnifiedNotificationEvent>> getInbox() async {
    await _synchronizePendingSources();
    return store.getInbox();
  }

  Future<List<NotificationGroup>> getGroupedInbox() async {
    await _synchronizePendingSources();
    return _grouper.group(await store.getInbox());
  }

  Future<int> getUnreadCount() async {
    await _synchronizePendingSources();
    return store.getUnreadCount();
  }

  Future<void> markAllAsRead() => store.markAllRead();

  Future<void> clearNotifications() async {
    await store.clearAll();
    await renderer.clearAll();
  }

  Future<void> clearNotificationGroup(String groupKey) async {
    await store.clearGroup(groupKey);
    await renderer.clearGroup(groupKey);
  }

  Future<void> markNotificationAsOpened(String eventId) async {
    await store.markOpened(eventId);
  }

  Future<void> subscribeToTopic(String topic) async {
    await realtimeBridge.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await realtimeBridge.unsubscribeFromTopic(topic);
  }

  Future<void> dispose() async {
    _lifecycle?.dispose();
    await _fcmForegroundSub?.cancel();
    await _fcmOpenedSub?.cancel();
    await _apnsForegroundSub?.cancel();
    await _apnsOpenedSub?.cancel();
    await _mqttSub?.cancel();
    await _mqttConnectedSub?.cancel();
    await _mqttDisconnectedSub?.cancel();
    await _fcmTokenSub?.cancel();
    await _apnsTokenSub?.cancel();
    await _rendererTapSub?.cancel();
    await realtimeBridge.disconnect();
  }
}
