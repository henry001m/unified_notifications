import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../contracts/notification_store.dart';
import '../../core/notification_normalizer.dart';
import '../../core/notification_visibility.dart';
import '../../models/notification_source.dart';
import '../../render/local_notification_renderer.dart';
import '../../sdk/background_bootstrap.dart';
import '../../storage/shared_prefs_notification_store.dart';
import '../../utils/json_utils.dart';

@pragma('vm:entry-point')
Future<void> unifiedNotificationsFirebaseBackgroundHandler(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  final config = await BackgroundBootstrap.loadConfig();
  if (config == null) return;

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

  final event = const NotificationNormalizer().normalize(
    payload,
    source: NotificationSource.fcmBackground,
  );
  final hiddenOwn = isHiddenOwnNotificationEvent(event, config: config);

  final NotificationStore store = SharedPrefsNotificationStore(
    window: config.deduplicationWindow,
  );

  try {
    await store.enqueuePendingEvent(event);
  } catch (_) {}
  if (!hiddenOwn) {
    try {
      await store.saveInboxEvent(event);
    } catch (_) {}
  }

  if (!hiddenOwn &&
      config.enableSystemNotifications &&
      (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS)) {
    try {
      final renderer = LocalNotificationRenderer(config: config);
      await renderer.initialize();
      await renderer.show(event);
    } catch (error) {
      debugPrint(
        '[FCM BG] No se pudo mostrar la notificación local en background: $error',
      );
    }
  } else if (!hiddenOwn &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS) {
    debugPrint(
      '[FCM BG] Render local omitido en iOS para evitar duplicado con la push remota del sistema | '
      'event_id=${event.eventId} | group_key=${event.groupKey}',
    );
  }
}
