import '../contracts/notification_router.dart';
import '../contracts/topic_resolver.dart';
import 'android_notification_config.dart';
import 'ios_notification_config.dart';
import 'mqtt_config.dart';

typedef UnifiedNotificationCallback = Future<void> Function(
  Map<String, dynamic> event,
);

class UnifiedNotificationConfig {
  const UnifiedNotificationConfig({
    required this.appName,
    required this.mqtt,
    required this.android,
    required this.ios,
    this.enableFcm = true,
    this.enableApns = true,
    this.enableMqtt = true,
    this.enableSystemNotifications = true,
    this.hiveInboxEnabled = false,
    this.mqttTopicResolver,
    this.router,
    this.deduplicationWindow = const Duration(minutes: 10),
    this.onRawEvent,
  });

  final String appName;
  final bool enableFcm;
  final bool enableApns;
  final bool enableMqtt;
  final bool enableSystemNotifications;
  final bool hiveInboxEnabled;
  final MqttConfig mqtt;
  final AndroidNotificationConfig android;
  final IosNotificationConfig ios;
  final TopicResolver? mqttTopicResolver;
  final NotificationRouter? router;
  final Duration deduplicationWindow;
  final UnifiedNotificationCallback? onRawEvent;

  Map<String, dynamic> toJson() {
    return {
      'appName': appName,
      'enableFcm': enableFcm,
      'enableApns': enableApns,
      'enableMqtt': enableMqtt,
      'enableSystemNotifications': enableSystemNotifications,
      'hiveInboxEnabled': hiveInboxEnabled,
      'mqtt': mqtt.toJson(),
      'android': android.toJson(),
      'ios': ios.toJson(),
      'deduplicationWindowMs': deduplicationWindow.inMilliseconds,
    };
  }

  factory UnifiedNotificationConfig.fromJson(Map<String, dynamic> json) {
    return UnifiedNotificationConfig(
      appName: json['appName']?.toString() ?? 'App',
      enableFcm: json['enableFcm'] != false,
      enableApns: json['enableApns'] != false,
      enableMqtt: json['enableMqtt'] != false,
      enableSystemNotifications: json['enableSystemNotifications'] != false,
      hiveInboxEnabled: json['hiveInboxEnabled'] == true,
      mqtt: MqttConfig.fromJson(
        Map<String, dynamic>.from(json['mqtt'] as Map? ?? const {}),
      ),
      android: AndroidNotificationConfig.fromJson(
        Map<String, dynamic>.from(json['android'] as Map? ?? const {}),
      ),
      ios: IosNotificationConfig.fromJson(
        Map<String, dynamic>.from(json['ios'] as Map? ?? const {}),
      ),
      deduplicationWindow: Duration(
        milliseconds:
            (json['deduplicationWindowMs'] as num?)?.toInt() ?? 600000,
      ),
    );
  }
}
