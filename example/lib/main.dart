import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:unified_notifications/unified_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(
    unifiedNotificationsFirebaseBackgroundHandler,
  );

  await UnifiedNotifications.instance.init(
    config: UnifiedNotificationConfig(
      appName: 'Unified Notifications Example',
      enableFcm: true,
      enableApns: true,
      enableMqtt: true,
      enableSystemNotifications: true,
      mqtt: const MqttConfig(
        broker: '134.122.119.215',
        port: 1883,
        topicBase: 'usuarioSistemaTareaEMQX',
        clientIdPrefix: 'example',
      ),
      android: const AndroidNotificationConfig(
        defaultChannelId: 'spark_delivery',
        defaultChannelName: 'Spark Notificaciones',
      ),
      ios: const IosNotificationConfig(),
    ),
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Unified Notifications')),
        body: Center(
          child: FilledButton(
            onPressed: () async {
              await UnifiedNotifications.instance.login(userId: '30');
            },
            child: const Text('Login user 30'),
          ),
        ),
      ),
    );
  }
}
