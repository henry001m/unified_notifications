import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/unified_notification_config.dart';
import '../storage/notification_store_keys.dart';

class BackgroundBootstrap {
  static Future<void> saveConfig(UnifiedNotificationConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      NotificationStoreKeys.bootstrapConfig,
      jsonEncode(config.toJson()),
    );
  }

  static Future<UnifiedNotificationConfig?> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NotificationStoreKeys.bootstrapConfig);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UnifiedNotificationConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }
}
