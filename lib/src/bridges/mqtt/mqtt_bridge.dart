import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../config/mqtt_config.dart';
import '../../contracts/realtime_bridge.dart';
import '../../core/notification_normalizer.dart';
import '../../models/notification_source.dart';
import '../../models/unified_notification_event.dart';

class MqttBridge implements RealtimeBridge {
  MqttBridge({required this.config});

  final MqttConfig config;
  final _messageController =
      StreamController<UnifiedNotificationEvent>.broadcast();
  final _connectedController = StreamController<void>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();
  final _normalizer = const NotificationNormalizer();

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>?
      _updatesSub;
  bool _intentionalDisconnect = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  String? _currentUserId;
  String? _currentTopic;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Future<void> connect({
    required String userId,
    required String topic,
  }) async {
    _currentUserId = userId;
    _currentTopic = topic;
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    final userId = _currentUserId;
    final topic = _currentTopic;
    if (userId == null || topic == null) return;

    if (_client != null &&
        _client?.connectionStatus?.state == MqttConnectionState.connected) {
      debugPrint('[MQTT] Ya conectado para usr_id=$userId');
      return;
    }

    await disconnect();

    final clientId =
        '${config.clientIdPrefix}_${userId}_${DateTime.now().millisecondsSinceEpoch}';
    final client = MqttServerClient.withPort(
      config.broker,
      clientId,
      config.port,
    );
    client.logging(on: false);
    client.keepAlivePeriod = config.keepAliveSeconds;
    client.onConnected = () {
      debugPrint('[MQTT] Conectado | usr_id=$userId');
      _connectedController.add(null);
    };
    client.onDisconnected = () {
      debugPrint('[MQTT] Desconectado | usr_id=$userId');
      _updatesSub?.cancel();
      _updatesSub = null;
      if (identical(_client, client)) {
        _client = null;
      }
      _disconnectedController.add(null);
      if (!_intentionalDisconnect) {
        _scheduleReconnect();
      }
    };
    client.onSubscribed =
        (t) => debugPrint('[MQTT] Suscrito a $t | usr_id=$userId');
    client.pongCallback = () =>
        debugPrint('[MQTT] Pong recibido | usr_id=$userId');

    if (config.username?.trim().isNotEmpty == true) {
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(config.username, config.password)
          .startClean();
    } else {
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean();
    }

    try {
      debugPrint('[MQTT] Conectando a ${config.broker}:${config.port} | usr_id=$userId');
      await client.connect();
    } catch (e) {
      debugPrint('[MQTT] Error de conexión: $e | usr_id=$userId');
      try {
        client.disconnect();
      } catch (_) {}
      if (identical(_client, client)) {
        _client = null;
      }
      _scheduleReconnect();
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      debugPrint(
        '[MQTT] Conexión fallida | estado=${client.connectionStatus?.state} | usr_id=$userId',
      );
      try {
        client.disconnect();
      } catch (_) {}
      if (identical(_client, client)) {
        _client = null;
      }
      _scheduleReconnect();
      return;
    }

    _client = client;
    _reconnectAttempts = 0;
    await subscribeToTopic(topic);
    _updatesSub?.cancel();
    _updatesSub = _client?.updates?.listen(_handleMessages);

    debugPrint('[MQTT] Conectado exitosamente | usr_id=$userId | topic=$topic');
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnectAttempts >= config.maxReconnectAttempts) {
      debugPrint('[MQTT] Reintentos agotados');
      return;
    }

    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: config.reconnectDelaySeconds),
      _doConnect,
    );
    debugPrint(
      '[MQTT] Reintento $_reconnectAttempts/${config.maxReconnectAttempts} en ${config.reconnectDelaySeconds}s',
    );
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _updatesSub?.cancel();
    _updatesSub = null;
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
  }

  void _handleMessages(
    List<MqttReceivedMessage<MqttMessage?>>? messages,
  ) async {
    if (messages == null || messages.isEmpty) return;
    final message = messages.first.payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(
      message.payload.message,
    );

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;

      debugPrint('[MQTT] Mensaje recibido | payload=$decoded');
      final event = _normalizer.normalize(decoded, source: NotificationSource.mqtt);
      _messageController.add(event);
    } catch (e) {
      debugPrint('[MQTT] Error parseando payload: $e');
    }
  }

  @override
  Stream<void> get onConnected => _connectedController.stream;

  @override
  Stream<void> get onDisconnected => _disconnectedController.stream;

  @override
  Stream<UnifiedNotificationEvent> get onMessage =>
      _messageController.stream;

  @override
  Future<void> subscribeToTopic(String topic) async {
    _client?.subscribe(topic, MqttQos.atLeastOnce);
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    _client?.unsubscribe(topic);
  }
}
