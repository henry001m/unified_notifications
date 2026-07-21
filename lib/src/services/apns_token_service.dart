import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/notification_store_keys.dart';

class ApnsTokenService with WidgetsBindingObserver {
  ApnsTokenService._();

  static final ApnsTokenService instance = ApnsTokenService._();

  static const MethodChannel _channel =
      MethodChannel('app.notificaciones/apns');
  static const int _maxRetryAttempts = 3;

  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationReceivedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationOpenedController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _initialized = false;
  bool _retryScheduled = false;
  int _retryCount = 0;

  Stream<String> get tokenStream => _tokenController.stream;
  Stream<Map<String, dynamic>> get notificationReceivedStream =>
      _notificationReceivedController.stream;
  Stream<Map<String, dynamic>> get notificationOpenedStream =>
      _notificationOpenedController.stream;

  Future<void> initialize() async {
    if (_initialized || !Platform.isIOS) return;

    _channel.setMethodCallHandler(_handleMethodCall);
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
    debugPrint('[APNS] Servicio APNs inicializado.');

    await _markFlutterReady();
    await _consumePendingApnsEvents();
    await solicitarRegistroRemoto();
    await obtenerTokenActual();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isIOS) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumePendingApnsEvents());
    }
  }

  Future<String?> obtenerTokenActual() async {
    if (!Platform.isIOS) return null;

    final persistedToken = await _leerTokenPersistido();
    try {
      final token = await _channel.invokeMethod<String>('getApnsToken');
      final normalized = token?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        _resetRetryState();
        await _persistirToken(normalized);
        return normalized;
      }
    } on MissingPluginException {
      _scheduleRetry('getApnsToken');
    } catch (error) {
      debugPrint('[APNS] Error obteniendo token APNs: $error');
    }
    return persistedToken;
  }

  Future<void> solicitarRegistroRemoto() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('requestRemoteNotifications');
      _resetRetryState();
    } on MissingPluginException {
      _scheduleRetry('requestRemoteNotifications');
    } catch (error) {
      debugPrint('[APNS] Error solicitando registro remoto APNs: $error');
    }
  }

  Future<bool?> esEntornoProduccion() async {
    if (!Platform.isIOS) return null;
    try {
      final environment =
          await _channel.invokeMethod<String>('getApnsEnvironment');
      final normalized = environment?.trim().toLowerCase();
      if (normalized == 'production') return true;
      if (normalized == 'development') return false;
    } catch (_) {}
    return null;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onApnsToken':
        final token = call.arguments?.toString().trim();
        if (token != null && token.isNotEmpty) {
          _resetRetryState();
          await _persistirToken(token);
        }
        break;
      case 'onApnsNotificationReceived':
        if (call.arguments is Map) {
          _notificationReceivedController.add(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        }
        break;
      case 'onApnsNotificationOpened':
        if (call.arguments is Map) {
          _notificationOpenedController.add(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        }
        break;
    }
  }

  Future<void> _consumePendingApnsEvents() async {
    if (!Platform.isIOS) return;
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
          _notificationReceivedController.add(
            Map<String, dynamic>.from(payload),
          );
        } else if (method == 'onApnsNotificationOpened') {
          _notificationOpenedController.add(
            Map<String, dynamic>.from(payload),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _markFlutterReady() async {
    try {
      await _channel.invokeMethod<void>('setFlutterReady');
    } catch (_) {}
  }

  Future<void> _persistirToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NotificationStoreKeys.apnsToken, token);
    _tokenController.add(token);
    debugPrint('[APNS] Token listo para sincronizar: $token');
  }

  Future<String?> _leerTokenPersistido() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationStoreKeys.apnsToken);
  }

  void _scheduleRetry(String source) {
    if (_retryScheduled || _retryCount >= _maxRetryAttempts) return;
    _retryScheduled = true;
    _retryCount += 1;
    Future<void>.delayed(const Duration(seconds: 2), () async {
      _retryScheduled = false;
      await solicitarRegistroRemoto();
      await obtenerTokenActual();
    });
  }

  void _resetRetryState() {
    _retryCount = 0;
    _retryScheduled = false;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenController.close();
    _notificationReceivedController.close();
    _notificationOpenedController.close();
  }
}
