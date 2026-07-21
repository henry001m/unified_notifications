class AndroidNotificationConfig {
  const AndroidNotificationConfig({
    required this.defaultChannelId,
    required this.defaultChannelName,
    this.defaultChannelDescription = 'Unified notifications',
    this.foregroundChannelId = 'unified_notifications_foreground',
    this.foregroundChannelName = 'Notification service',
    this.foregroundNotificationTitle = 'Notifications',
    this.foregroundNotificationContent = 'Notification service active',
    this.iconResource = '@mipmap/ic_launcher',
  });

  final String defaultChannelId;
  final String defaultChannelName;
  final String defaultChannelDescription;
  final String foregroundChannelId;
  final String foregroundChannelName;
  final String foregroundNotificationTitle;
  final String foregroundNotificationContent;
  final String iconResource;

  Map<String, dynamic> toJson() {
    return {
      'defaultChannelId': defaultChannelId,
      'defaultChannelName': defaultChannelName,
      'defaultChannelDescription': defaultChannelDescription,
      'foregroundChannelId': foregroundChannelId,
      'foregroundChannelName': foregroundChannelName,
      'foregroundNotificationTitle': foregroundNotificationTitle,
      'foregroundNotificationContent': foregroundNotificationContent,
      'iconResource': iconResource,
    };
  }

  factory AndroidNotificationConfig.fromJson(Map<String, dynamic> json) {
    return AndroidNotificationConfig(
      defaultChannelId: json['defaultChannelId']?.toString() ?? 'default',
      defaultChannelName:
          json['defaultChannelName']?.toString() ?? 'Notifications',
      defaultChannelDescription:
          json['defaultChannelDescription']?.toString() ??
              'Unified notifications',
      foregroundChannelId:
          json['foregroundChannelId']?.toString() ??
              'unified_notifications_foreground',
      foregroundChannelName:
          json['foregroundChannelName']?.toString() ??
              'Notification service',
      foregroundNotificationTitle:
          json['foregroundNotificationTitle']?.toString() ?? 'Notifications',
      foregroundNotificationContent:
          json['foregroundNotificationContent']?.toString() ??
              'Notification service active',
      iconResource: json['iconResource']?.toString() ?? '@mipmap/ic_launcher',
    );
  }
}
