import '../contracts/notification_router.dart';
import '../contracts/topic_resolver.dart';
import 'android_notification_config.dart';
import 'ios_notification_config.dart';
import 'mqtt_config.dart';

typedef UnifiedNotificationCallback =
    Future<void> Function(Map<String, dynamic> event);

class HiddenNotificationCondition {
  const HiddenNotificationCondition({
    required this.paths,
    required this.values,
    this.ignoreCase = true,
  });

  final List<String> paths;
  final List<String> values;
  final bool ignoreCase;

  Map<String, dynamic> toJson() {
    return {'paths': paths, 'values': values, 'ignoreCase': ignoreCase};
  }

  factory HiddenNotificationCondition.fromJson(Map<String, dynamic> json) {
    return HiddenNotificationCondition(
      paths:
          (json['paths'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
      values:
          (json['values'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
      ignoreCase: json['ignoreCase'] != false,
    );
  }
}

class HiddenNotificationRule {
  const HiddenNotificationRule({required this.conditions});

  final List<HiddenNotificationCondition> conditions;

  Map<String, dynamic> toJson() {
    return {'conditions': conditions.map((item) => item.toJson()).toList()};
  }

  factory HiddenNotificationRule.fromJson(Map<String, dynamic> json) {
    return HiddenNotificationRule(
      conditions:
          (json['conditions'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => HiddenNotificationCondition.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false) ??
          const <HiddenNotificationCondition>[],
    );
  }
}

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
    this.hiddenNotificationTypes = const <String>[],
    this.hiddenNotificationEvents = const <String>[],
    this.hiddenNotificationRules = const <HiddenNotificationRule>[],
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
  final List<String> hiddenNotificationTypes;
  final List<String> hiddenNotificationEvents;
  final List<HiddenNotificationRule> hiddenNotificationRules;

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
      'hiddenNotificationTypes': hiddenNotificationTypes,
      'hiddenNotificationEvents': hiddenNotificationEvents,
      'hiddenNotificationRules': hiddenNotificationRules
          .map((item) => item.toJson())
          .toList(),
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
      hiddenNotificationTypes:
          (json['hiddenNotificationTypes'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
      hiddenNotificationEvents:
          (json['hiddenNotificationEvents'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
      hiddenNotificationRules:
          (json['hiddenNotificationRules'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => HiddenNotificationRule.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false) ??
          const <HiddenNotificationRule>[],
    );
  }
}
