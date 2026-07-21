# unified_notifications

Flutter package to unify FCM, APNs and MQTT/EMQX as a single notification SDK.

## Features

- Unified push and realtime notification API
- FCM + APNs token access
- MQTT foreground realtime support
- Local notification rendering
- Deduplication by `eventId`
- Grouping by `groupKey`
- Local inbox persistence
- Background FCM data-only handler

## Quick start

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:unified_notifications/unified_notifications.dart';

Future<void> main() async {
  FirebaseMessaging.onBackgroundMessage(
    unifiedNotificationsFirebaseBackgroundHandler,
  );

  await UnifiedNotifications.instance.init(
    config: UnifiedNotificationConfig(
      appName: 'Spark',
      enableFcm: true,
      enableApns: true,
      enableMqtt: true,
      enableSystemNotifications: true,
      mqtt: const MqttConfig(
        broker: '134.122.119.215',
        port: 1883,
        topicBase: 'usuarioSistemaTareaEMQX',
      ),
      android: const AndroidNotificationConfig(
        defaultChannelId: 'spark_delivery',
        defaultChannelName: 'Spark Notificaciones',
      ),
      ios: const IosNotificationConfig(),
    ),
  );

  await UnifiedNotifications.instance.login(userId: '30');
}
```

## Notes

- MQTT is intended for foreground realtime notifications.
- FCM/APNs are the main source for background and terminated states.
- Backend should send Android notifications as FCM `data-only`.
