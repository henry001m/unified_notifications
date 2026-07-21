import 'notification_source.dart';

class UnifiedNotificationEvent {
  const UnifiedNotificationEvent({
    required this.eventId,
    required this.groupKey,
    required this.title,
    required this.body,
    required this.source,
    required this.receivedAt,
    this.route,
    this.sound,
    this.channelId,
    this.iconSmall,
    this.iconLarge,
    this.imageUrl,
    this.dynamicLink,
    this.data = const <String, dynamic>{},
    this.entityIds = const <String, String>{},
    this.isRead = false,
    this.isGroupSummary = false,
    this.openedFromSystem = false,
  });

  final String eventId;
  final String groupKey;
  final String title;
  final String body;
  final String? route;
  final NotificationSource source;
  final DateTime receivedAt;
  final String? sound;
  final String? channelId;
  final String? iconSmall;
  final String? iconLarge;
  final String? imageUrl;
  final String? dynamicLink;
  final Map<String, dynamic> data;
  final Map<String, String> entityIds;
  final bool isRead;
  final bool isGroupSummary;
  final bool openedFromSystem;

  String get effectiveTitle => title.trim().isEmpty ? 'Notification' : title;

  String get displayDate {
    final diff = DateTime.now().difference(receivedAt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${receivedAt.day}/${receivedAt.month}/${receivedAt.year}';
  }

  UnifiedNotificationEvent markAsRead() => copyWith(isRead: true);

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'groupKey': groupKey,
      'title': title,
      'body': body,
      'route': route,
      'source': source.name,
      'receivedAt': receivedAt.toIso8601String(),
      'sound': sound,
      'channelId': channelId,
      'iconSmall': iconSmall,
      'iconLarge': iconLarge,
      'imageUrl': imageUrl,
      'dynamicLink': dynamicLink,
      'data': data,
      'entityIds': entityIds,
      'isRead': isRead,
      'isGroupSummary': isGroupSummary,
      'openedFromSystem': openedFromSystem,
    };
  }

  factory UnifiedNotificationEvent.fromJson(Map<String, dynamic> json) {
    return UnifiedNotificationEvent(
      eventId: json['eventId']?.toString() ?? '',
      groupKey: json['groupKey']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      route: json['route']?.toString(),
      source: NotificationSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => NotificationSource.unknown,
      ),
      receivedAt:
          DateTime.tryParse(json['receivedAt']?.toString() ?? '') ??
              DateTime.now(),
      sound: json['sound']?.toString(),
      channelId: json['channelId']?.toString(),
      iconSmall: json['iconSmall']?.toString(),
      iconLarge: json['iconLarge']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      dynamicLink: json['dynamicLink']?.toString(),
      data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      entityIds:
          (json['entityIds'] as Map? ?? const {}).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
      isRead: json['isRead'] == true,
      isGroupSummary: json['isGroupSummary'] == true,
      openedFromSystem: json['openedFromSystem'] == true,
    );
  }

  UnifiedNotificationEvent copyWith({
    String? eventId,
    String? groupKey,
    String? title,
    String? body,
    String? route,
    NotificationSource? source,
    DateTime? receivedAt,
    String? sound,
    String? channelId,
    String? iconSmall,
    String? iconLarge,
    String? imageUrl,
    String? dynamicLink,
    Map<String, dynamic>? data,
    Map<String, String>? entityIds,
    bool? isRead,
    bool? isGroupSummary,
    bool? openedFromSystem,
  }) {
    return UnifiedNotificationEvent(
      eventId: eventId ?? this.eventId,
      groupKey: groupKey ?? this.groupKey,
      title: title ?? this.title,
      body: body ?? this.body,
      route: route ?? this.route,
      source: source ?? this.source,
      receivedAt: receivedAt ?? this.receivedAt,
      sound: sound ?? this.sound,
      channelId: channelId ?? this.channelId,
      iconSmall: iconSmall ?? this.iconSmall,
      iconLarge: iconLarge ?? this.iconLarge,
      imageUrl: imageUrl ?? this.imageUrl,
      dynamicLink: dynamicLink ?? this.dynamicLink,
      data: data ?? this.data,
      entityIds: entityIds ?? this.entityIds,
      isRead: isRead ?? this.isRead,
      isGroupSummary: isGroupSummary ?? this.isGroupSummary,
      openedFromSystem: openedFromSystem ?? this.openedFromSystem,
    );
  }
}
