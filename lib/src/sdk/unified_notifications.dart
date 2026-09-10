import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../bridges/apns/apns_bridge.dart';
import '../bridges/fcm/fcm_bridge.dart';
import '../bridges/mqtt/mqtt_bridge.dart';
import '../config/unified_notification_config.dart';
import '../contracts/notification_store.dart';
import '../models/notification_group.dart';
import '../models/notification_token_bundle.dart';
import '../models/unified_notification_event.dart';
import '../render/local_notification_renderer.dart';
import '../storage/hive_notification_store.dart';
import '../storage/notification_store_keys.dart';
import '../storage/shared_prefs_notification_store.dart';
import 'notification_runtime.dart';
import 'unified_notification_sdk.dart';

class UnifiedNotifications implements UnifiedNotificationSdk {
  UnifiedNotifications._();

  static final UnifiedNotifications instance = UnifiedNotifications._();

  static Future<void> resetPersistedState({
    bool clearBootstrapConfig = false,
    bool clearDeviceTokens = false,
    bool preserveInbox = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = <String>{
      NotificationStoreKeys.delivered,
      NotificationStoreKeys.opened,
      NotificationStoreKeys.currentUserId,
      NotificationStoreKeys.pendingQueue,
      NotificationStoreKeys.displayedIdsByGroup,
      NotificationStoreKeys.recentlyDeliveredEventIds,
      NotificationStoreKeys.pendingOpenedLocalEvents,
    };

    if (!preserveInbox) {
      keys
        ..add(NotificationStoreKeys.inbox)
        ..add(NotificationStoreKeys.pending);
    } else {
      keys.add(NotificationStoreKeys.pending);
    }

    if (clearBootstrapConfig) {
      keys.add(NotificationStoreKeys.bootstrapConfig);
    }

    if (clearDeviceTokens) {
      keys
        ..add(NotificationStoreKeys.fcmToken)
        ..add(NotificationStoreKeys.apnsToken);
    }

    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  NotificationRuntime? _runtime;
  late final StreamController<void> _mqttConnectedController =
      StreamController<void>.broadcast();
  late final StreamController<void> _mqttDisconnectedController =
      StreamController<void>.broadcast();
  late final StreamController<UnifiedNotificationEvent> _mqttMessageController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  late final StreamController<UnifiedNotificationEvent> _allEventsController =
      StreamController<UnifiedNotificationEvent>.broadcast();

  StreamSubscription<UnifiedNotificationEvent>? _mqttMessageSub;
  StreamSubscription<UnifiedNotificationEvent>? _allEventsSub;
  StreamSubscription<void>? _mqttConnectedSub;
  StreamSubscription<void>? _mqttDisconnectedSub;

  @override
  Future<void> init({required UnifiedNotificationConfig config}) async {
    final store = config.hiveInboxEnabled
        ? HiveNotificationStore(boxName: 'notificaciones_box')
        : SharedPrefsNotificationStore(window: config.deduplicationWindow)
              as NotificationStore;

    final mqttBridge = MqttBridge(config: config.mqtt);
    final fcmBridge = config.enableFcm ? FcmBridge() : null;
    final apnsBridge = config.enableApns ? ApnsBridge() : null;

    final runtime = NotificationRuntime(
      config: config,
      store: store,
      renderer: LocalNotificationRenderer(config: config),
      fcmBridge: fcmBridge,
      apnsBridge: apnsBridge,
      realtimeBridge: mqttBridge,
      router: config.router,
    );
    _runtime = runtime;
    await runtime.initialize();

    _mqttMessageSub?.cancel();
    _mqttConnectedSub?.cancel();
    _mqttDisconnectedSub?.cancel();
    _allEventsSub?.cancel();

    _mqttMessageSub = mqttBridge.onMessage.listen(_mqttMessageController.add);
    _mqttConnectedSub = mqttBridge.onConnected.listen(
      (_) => _mqttConnectedController.add(null),
    );
    _mqttDisconnectedSub = mqttBridge.onDisconnected.listen(
      (_) => _mqttDisconnectedController.add(null),
    );
    _allEventsSub = runtime.onAllEvents.listen(_allEventsController.add);
  }

  NotificationRuntime get _safeRuntime {
    final runtime = _runtime;
    if (runtime == null) {
      throw StateError('UnifiedNotifications.init must be called first.');
    }
    return runtime;
  }

  @override
  Future<void> clearNotificationGroup(String groupKey) {
    return _safeRuntime.clearNotificationGroup(groupKey);
  }

  @override
  Future<void> clearNotifications() {
    return _safeRuntime.clearNotifications();
  }

  @override
  Future<void> clearNotification(String eventId) {
    return _safeRuntime.clearNotification(eventId);
  }

  @override
  Future<void> disableNotifications() async {}

  @override
  Future<void> enableNotifications() async {}

  @override
  Future<String?> getApnsToken() => _safeRuntime.getApnsToken();

  @override
  Future<String?> getCurrentUserId() async => _safeRuntime.currentUserId;

  @override
  Future<String?> getFcmToken() => _safeRuntime.getFcmToken();

  @override
  Future<List<NotificationGroup>> getGroupedInbox() {
    return _safeRuntime.getGroupedInbox();
  }

  @override
  Future<List<UnifiedNotificationEvent>> getInbox() {
    return _safeRuntime.getInbox();
  }

  @override
  Future<int> getUnreadCount() {
    return _safeRuntime.getUnreadCount();
  }

  @override
  Future<void> markAllAsRead() {
    return _safeRuntime.markAllAsRead();
  }

  @override
  Future<NotificationTokenBundle> getTokenBundle() async {
    return NotificationTokenBundle(
      fcmToken: await getFcmToken(),
      apnsToken: await getApnsToken(),
      providerToken: await getFcmToken(),
      currentUserId: await getCurrentUserId(),
    );
  }

  @override
  Future<void> login({required String userId}) {
    return _safeRuntime.login(userId);
  }

  @override
  Future<void> logout() {
    return _safeRuntime.logout();
  }

  @override
  Future<void> markNotificationAsOpened(String eventId) {
    return _safeRuntime.markNotificationAsOpened(eventId);
  }

  @override
  Stream<UnifiedNotificationEvent> get onNotificationOpened =>
      _safeRuntime.onOpened;

  @override
  Stream<UnifiedNotificationEvent> get onNotificationReceived =>
      _safeRuntime.onReceived;

  @override
  Stream<NotificationTokenBundle> get onTokenUpdated =>
      _safeRuntime.onTokenUpdated;

  @override
  Stream<void> get onMqttConnected => _mqttConnectedController.stream;

  @override
  Stream<void> get onMqttDisconnected => _mqttDisconnectedController.stream;

  @override
  Stream<UnifiedNotificationEvent> get onMqttMessage =>
      _mqttMessageController.stream;

  @override
  Stream<UnifiedNotificationEvent> get onAllEvents =>
      _allEventsController.stream;

  List<UnifiedNotificationEvent> consumePendingReceivedForSubscribers() {
    return _safeRuntime.takePendingReceivedForSubscribers();
  }

  List<UnifiedNotificationEvent> consumePendingOpenedForSubscribers() {
    return _safeRuntime.takePendingOpenedForSubscribers();
  }

  @override
  void requeuePendingOpenedForSubscribers(UnifiedNotificationEvent event) {
    _safeRuntime.requeuePendingOpenedForSubscribers(event);
  }

  @override
  Future<void> subscribeToTopic(String topic) {
    return _safeRuntime.subscribeToTopic(topic);
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) {
    return _safeRuntime.unsubscribeFromTopic(topic);
  }
}
