import 'dart:convert';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contracts/notification_store.dart';
import '../../core/notification_normalizer.dart';
import '../../models/notification_source.dart';
import '../../render/local_notification_renderer.dart';
import '../../sdk/background_bootstrap.dart';
import '../../storage/hive_notification_store.dart';
import '../../storage/notification_store_keys.dart';
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

  if (config.hiveInboxEnabled) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
      await Hive.openBox('notificaciones_box');
    } catch (_) {}
  }

  final NotificationStore store = config.hiveInboxEnabled
      ? HiveNotificationStore(boxName: 'notificaciones_box')
      : SharedPrefsNotificationStore(window: config.deduplicationWindow);

  try {
    await store.enqueuePendingEvent(event);
  } catch (_) {}
  try {
    await store.saveInboxEvent(event);
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  final recentDeliveredRaw =
      prefs.getString(NotificationStoreKeys.recentlyDeliveredEventIds);
  final recentDelivered = <String, int>{};
  if (recentDeliveredRaw != null && recentDeliveredRaw.isNotEmpty) {
    try {
      final decoded = jsonDecode(recentDeliveredRaw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          recentDelivered[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    } catch (_) {}
  }

  final now = DateTime.now();
  recentDelivered.removeWhere(
    (_, timestamp) =>
        now.difference(DateTime.fromMillisecondsSinceEpoch(timestamp)) >
        const Duration(minutes: 10),
  );

  final shouldSkip = recentDelivered.containsKey(event.eventId);
  recentDelivered[event.eventId] = now.millisecondsSinceEpoch;
  await prefs.setString(
    NotificationStoreKeys.recentlyDeliveredEventIds,
    jsonEncode(recentDelivered),
  );

  if (!shouldSkip && config.enableSystemNotifications) {
    final renderer = LocalNotificationRenderer(config: config);
    await renderer.initialize();
    await renderer.show(event);
  }
}
