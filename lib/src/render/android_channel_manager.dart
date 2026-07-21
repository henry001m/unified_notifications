import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AndroidChannelManager {
  AndroidChannelManager(this.plugin);

  final FlutterLocalNotificationsPlugin plugin;

  Future<void> ensureChannel({
    required String channelId,
    required String channelName,
    required String description,
    String? sound,
    Importance importance = Importance.max,
  }) async {
    final android =
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        channelName,
        description: description,
        importance: importance,
        playSound: true,
        sound: sound != null
            ? RawResourceAndroidNotificationSound(sound)
            : null,
      ),
    );
  }
}
