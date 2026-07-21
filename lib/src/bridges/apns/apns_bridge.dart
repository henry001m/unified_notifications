import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../contracts/push_bridge.dart';
import '../../core/notification_normalizer.dart';
import '../../models/notification_source.dart';
import '../../models/notification_token_bundle.dart';
import '../../models/unified_notification_event.dart';

class ApnsBridge implements PushBridge {
  ApnsBridge();

  static const MethodChannel _channel =
      MethodChannel('app.notificaciones/apns');
  static const int _maxRetryAttempts = 3;

  final _normalizer = const NotificationNormalizer();
  final _foregroundController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  final _openedController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  final _tokenController =
      StreamController<NotificationTokenBundle>.broadcast();
  final List<UnifiedNotificationEvent> _pendingReceived = [];
  final List<UnifiedNotificationEvent> _pendingOpened = [];

  bool _initialized = false;
  int _retryCount = 0;
  bool _retryScheduled = false;
  bool _observerRegistered = false;

  @override
  Stream<UnifiedNotificationEvent> get onForegroundMessage =>
      _foregroundController.stream;

  @override
  Stream<UnifiedNotificationEvent> get onOpenedMessage =>
      _openedController.stream;

  @override
  Stream<NotificationTokenBundle> get onTokenRefresh =>
      _tokenController.stream;

  @override
  Future<String?> getApnsToken() async {
    if (!Platform.isIOS) return null;
    try {
      return await _channel.invokeMethod<String>('getApnsToken');
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getFcmToken() async => null;

  Future<String?> obtenerEntornoApns() async {
    if (!Platform.isIOS) return null;
    try {
      return await _channel.invokeMethod<String>('getApnsEnvironment');
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool?> esEntornoProduccion() async {
    final environment = await obtenerEntornoApns();
    if (environment == null) return null;
    final normalized = environment.toLowerCase();
    if (normalized == 'production') return true;
    if (normalized == 'development') return false;
    return null;
  }

  @override
  Future<void> initialize() async {
    if (_initialized || !Platform.isIOS) return;

    _channel.setMethodCallHandler(_handleMethodCall);
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(_lifecycleObserver);
      _observerRegistered = true;
    }
    _initialized = true;

    await _markFlutterReady();
    await _consumePendingApnsEvents();
    await _requestRemoteNotifications();
    await _refreshToken();
  }

  late final WidgetsBindingObserver _lifecycleObserver =
      _ApnsLifecycleObserver(this);

  Future<void> _markFlutterReady() async {
    try {
      await _channel.invokeMethod<void>('setFlutterReady');
    } catch (_) {}
  }

  Future<void> _requestRemoteNotifications() async {
    try {
      await _channel.invokeMethod<void>('requestRemoteNotifications');
      _resetRetryState();
    } on MissingPluginException {
      _scheduleRetry('requestRemoteNotifications');
    } catch (_) {
      _scheduleRetry('requestRemoteNotifications');
    }
  }

  Future<void> _refreshToken() async {
    try {
      final token = await _channel.invokeMethod<String>('getApnsToken');
      final normalized = token?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        _resetRetryState();
        _tokenController.add(
          NotificationTokenBundle(apnsToken: normalized),
        );
      }
    } on MissingPluginException {
      _scheduleRetry('getApnsToken');
    } catch (_) {
      _scheduleRetry('getApnsToken');
    }
  }

  Future<void> _consumePendingApnsEvents() async {
    try {
      final pendingEvents =
          await _channel.invokeMethod<List<dynamic>>(
            'consumePendingApnsEvents',
          );
      if (pendingEvents == null || pendingEvents.isEmpty) return;
      for (final rawEvent in pendingEvents) {
        if (rawEvent is! Map) continue;
        final event = Map<String, dynamic>.from(rawEvent);
        final method = event['method']?.toString();
        final payload = event['payload'];
        if (payload is! Map) continue;
        if (method == 'onApnsNotificationReceived') {
          _emitReceived(Map<String, dynamic>.from(payload));
        } else if (method == 'onApnsNotificationOpened') {
          _emitOpened(Map<String, dynamic>.from(payload));
        }
      }
    } catch (_) {}
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onApnsToken':
        final token = call.arguments?.toString().trim();
        if (token != null && token.isNotEmpty) {
          _resetRetryState();
          _tokenController.add(
            NotificationTokenBundle(apnsToken: token),
          );
        }
        break;
      case 'onApnsNotificationReceived':
        if (call.arguments is Map) {
          _emitReceived(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        }
        break;
      case 'onApnsNotificationOpened':
        if (call.arguments is Map) {
          _emitOpened(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        }
        break;
      case 'onApnsRegistrationFailed':
        debugPrint('[APNS] Error de registro: ${call.arguments}');
        break;
    }
  }

  void _emitReceived(Map<String, dynamic> payload) {
    final event = _normalizer.normalize(
      payload,
      source: NotificationSource.apnsForeground,
    );
    _pendingReceived.add(event);
    _foregroundController.add(event);
  }

  void _emitOpened(Map<String, dynamic> payload) {
    final event = _normalizer.normalize(
      payload,
      source: NotificationSource.apnsOpened,
    );
    _pendingOpened.add(event);
    _openedController.add(event);
  }

  void _scheduleRetry(String source) {
    if (_retryScheduled || _retryCount >= _maxRetryAttempts) return;
    _retryScheduled = true;
    _retryCount += 1;
    Future<void>.delayed(const Duration(seconds: 2), () async {
      _retryScheduled = false;
      await _requestRemoteNotifications();
      await _refreshToken();
    });
  }

  void _resetRetryState() {
    _retryCount = 0;
    _retryScheduled = false;
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
}

class _ApnsLifecycleObserver with WidgetsBindingObserver {
  _ApnsLifecycleObserver(this._bridge);

  final ApnsBridge _bridge;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_bridge._consumePendingApnsEvents());
    }
  }
}
