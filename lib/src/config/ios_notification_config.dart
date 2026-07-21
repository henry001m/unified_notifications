class IosNotificationConfig {
  const IosNotificationConfig({
    this.requestAlertPermission = true,
    this.requestBadgePermission = true,
    this.requestSoundPermission = true,
    this.presentAlert = true,
    this.presentBanner = true,
    this.presentList = true,
    this.presentBadge = true,
    this.presentSound = true,
  });

  final bool requestAlertPermission;
  final bool requestBadgePermission;
  final bool requestSoundPermission;
  final bool presentAlert;
  final bool presentBanner;
  final bool presentList;
  final bool presentBadge;
  final bool presentSound;

  Map<String, dynamic> toJson() {
    return {
      'requestAlertPermission': requestAlertPermission,
      'requestBadgePermission': requestBadgePermission,
      'requestSoundPermission': requestSoundPermission,
      'presentAlert': presentAlert,
      'presentBanner': presentBanner,
      'presentList': presentList,
      'presentBadge': presentBadge,
      'presentSound': presentSound,
    };
  }

  factory IosNotificationConfig.fromJson(Map<String, dynamic> json) {
    return IosNotificationConfig(
      requestAlertPermission: json['requestAlertPermission'] == true,
      requestBadgePermission: json['requestBadgePermission'] != false,
      requestSoundPermission: json['requestSoundPermission'] != false,
      presentAlert: json['presentAlert'] != false,
      presentBanner: json['presentBanner'] != false,
      presentList: json['presentList'] != false,
      presentBadge: json['presentBadge'] != false,
      presentSound: json['presentSound'] != false,
    );
  }
}
