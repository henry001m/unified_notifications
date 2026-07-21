import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/notification_store_keys.dart';

class FcmTokenService {
  FcmTokenService._();

  static final FcmTokenService instance = FcmTokenService._();

  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;

  Stream<String> get tokenStream => _tokenController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
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

      _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
        _persistirToken,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[FCM] Error en onTokenRefresh: $error');
        },
      );

      await obtenerTokenActual();
      debugPrint('[FCM] Servicio FCM inicializado.');
    } catch (error) {
      debugPrint('[FCM] No se pudo inicializar FCM: $error');
    }
  }

  Future<String?> obtenerTokenActual() async {
    final tokenPersistido = await _leerTokenPersistido();
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final token = await FirebaseMessaging.instance.getToken();
      final normalizado = token?.trim();
      if (normalizado != null && normalizado.isNotEmpty) {
        await _persistirToken(normalizado);
        return normalizado;
      }
    } catch (error) {
      debugPrint('[FCM] Error obteniendo token FCM: $error');
    }
    return tokenPersistido;
  }

  Future<void> _persistirToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NotificationStoreKeys.fcmToken, token);
    _tokenController.add(token);
    debugPrint('[FCM] Token listo para sincronizar: $token');
  }

  Future<String?> _leerTokenPersistido() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationStoreKeys.fcmToken);
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenController.close();
  }
}
