class NotificationStoreKeys {
  static const String inbox = 'unified_notifications_inbox';
  static const String pending = 'unified_notifications_pending';
  static const String delivered = 'unified_notifications_recent_delivered';
  static const String opened = 'unified_notifications_recent_opened';
  static const String currentUserId = 'unified_notifications_current_user_id';
  static const String bootstrapConfig = 'unified_notifications_bootstrap';
  static const String fcmToken = 'fcm_device_token';
  static const String apnsToken = 'apns_device_token';

  static const String notificationUserId = 'boe_emqx_notification_user_id';
  static const String notificationTopicBase = 'boe_emqx_topic_base';
  static const String showSystemNotificationsKey =
      'boe_emqx_show_system_notifications';
  static const String pendingQueue = 'boe_emqx_notification_pending_queue';
  static const String displayedIdsByGroup =
      'boe_emqx_displayed_ids_by_group';
  static const String recentlyDeliveredEventIds =
      'boe_emqx_recently_delivered_event_ids';
}
