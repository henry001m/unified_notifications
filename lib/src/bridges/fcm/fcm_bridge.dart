import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../contracts/push_bridge.dart';
import '../../core/notification_normalizer.dart';
import '../../models/notification_source.dart';
import '../../models/notification_token_bundle.dart';
import '../../models/unified_notification_event.dart';
import '../../utils/json_utils.dart';

class FcmBridge implements PushBridge {
  FcmBridge();

  final _normalizer = const NotificationNormalizer();
  final _foregroundController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  final _openedController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  final _tokenController =
      StreamController<NotificationTokenBundle>.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;

  final List<UnifiedNotificationEvent> _pendingReceived = [];
  final List<UnifiedNotificationEvent> _pendingOpened = [];
  bool _initialized = false;

  @override
  Future<String?> getApnsToken() {
    return FirebaseMessaging.instance.getAPNSToken();
  }

  @override
  Future<String?> getFcmToken() {
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Stream<NotificationTokenBundle> get onTokenRefresh =>
      _tokenController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    final messaging = FirebaseMessaging.instance;

    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else {
      await messaging.requestPermission();
    }

    _foregroundSub?.cancel();
    _openedSub?.cancel();
    _tokenRefreshSub?.cancel();

    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedMessage);
    _tokenRefreshSub = messaging.onTokenRefresh.listen(_onTokenRefresh);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _logRemoteMessage('initial_message', initial);
      final event = _normalizer.normalize(
        _payloadFromMessage(initial),
        source: NotificationSource.fcmOpened,
      );
      _pendingOpened.add(event);
      _openedController.add(event);
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    _logRemoteMessage('foreground.received', message);
    final event = _normalizer.normalize(
      _payloadFromMessage(message),
      source: NotificationSource.fcmForeground,
    );
    _pendingReceived.add(event);
    _foregroundController.add(event);
  }

  void _onOpenedMessage(RemoteMessage message) {
    _logRemoteMessage('opened_app', message);
    final event = _normalizer.normalize(
      _payloadFromMessage(message),
      source: NotificationSource.fcmOpened,
    );
    _pendingOpened.add(event);
    _openedController.add(event);
  }

  void _onTokenRefresh(String token) {
    _tokenController.add(
      NotificationTokenBundle(
        fcmToken: token,
        providerToken: token,
      ),
    );
  }

  Map<String, dynamic> _payloadFromMessage(RemoteMessage message) {
    final payload = <String, dynamic>{
      ...message.data,
      if ((message.notification?.title ?? '').trim().isNotEmpty)
        'title': message.notification!.title!.trim(),
      if ((message.notification?.body ?? '').trim().isNotEmpty)
        'body': message.notification!.body!.trim(),
      if (message.messageId?.trim().isNotEmpty ?? false)
        'message_id': message.messageId!.trim(),
    };
    final nestedData = decodeNestedData(message.data);
    for (final entry in nestedData.entries) {
      payload.putIfAbsent(entry.key, () => entry.value);
    }
    return payload;
  }

  void _logRemoteMessage(String origin, RemoteMessage message) {
    final notification = message.notification;
    final payload = _payloadFromMessage(message);
    debugPrint(
      '[FCM] Mensaje recibido | origin=$origin | '
      'messageId=${message.messageId} | '
      'title=${notification?.title ?? message.data['title']} | '
      'body=${notification?.body ?? message.data['body']} | '
      'grp=${payload['grp']} | '
      'notf_id=${payload['notf_id']} | '
      'ruta=${payload['ruta'] ?? payload['route']}',
    );
  }

  List<UnifiedNotificationEvent> takePendingReceived() {
    final items = List<UnifiedNotificationEvent>.from(_pendingReceived);
    _pendingReceived.clear();
    return items;
  }

  List<UnifiedNotificationEvent> takePendingOpened() {
    final items = List<UnifiedNotificationEvent>.from(_pendingOpened);
    _pendingOpened.clear();
    return items;
  }

  @override
  Stream<UnifiedNotificationEvent> get onForegroundMessage =>
      _foregroundController.stream;

  @override
  Stream<UnifiedNotificationEvent> get onOpenedMessage =>
      _openedController.stream;
}
