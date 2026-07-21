import 'dart:convert';

import '../models/notification_source.dart';
import '../models/unified_notification_event.dart';
import '../utils/hashing_utils.dart';
import '../utils/json_utils.dart';
import '../utils/payload_utils.dart';

const Set<String> _reservedPayloadKeys = {
  'event_id',
  'notf_id',
  'id_notificacion',
  'notification_id',
  'message_id',
  'groupId',
  'grp',
  'group_key',
  'group_id',
  'id',
  'cabecera_mensaje',
  'contenido_mensaje',
  'titulo',
  'cuerpo',
  'title',
  'body',
  'sound',
  'route',
  'ruta',
  'data',
  'aps',
};

const Set<String> _knownEntityIdKeys = {
  'mk_id',
  'sp_id',
  'ti_id',
  'referencia_id',
  'nv_id',
  'rc_id',
  'ncj_id',
  'cb_id',
  'cp_id',
  'ctto_id',
  'atg_id',
  'grtn_id',
  'ats_id',
  'ncj_cc_id',
  'ncj_cb_id',
  'ncj_cp_id',
  'ncj_dscto_id',
};

class NotificationNormalizer {
  const NotificationNormalizer();

  UnifiedNotificationEvent normalize(
    Map<String, dynamic> payload, {
    required NotificationSource source,
  }) {
    final nestedData = decodeNestedData(payload);
    final merged = <String, dynamic>{...nestedData, ...payload};

    final title = firstNonEmptyString([
          merged['cabecera_mensaje'],
          merged['titulo'],
          merged['title'],
          merged['heading'],
        ]) ??
        'Sin titulo';
    final body = firstNonEmptyString([
          merged['contenido_mensaje'],
          merged['cuerpo'],
          merged['body'],
          merged['message'],
          merged['content'],
        ]) ??
        '';
    final route = firstNonEmptyString([
      merged['ruta'],
      merged['route'],
      merged['screen'],
    ]);

    final additionalData = _extractAdditionalData(merged, route);

    final eventId = _resolveEventId(merged, title: title, body: body, route: route, additionalData: additionalData);
    final groupKey = _resolveGroupKey(merged, additionalData, title: title);
    final sound = _extractSound(merged);
    final entityIds = _extractEntityIds(merged);

    return UnifiedNotificationEvent(
      eventId: eventId,
      groupKey: groupKey,
      title: title,
      body: body,
      route: route,
      source: source,
      receivedAt: DateTime.now(),
      sound: sound,
      channelId: firstNonEmptyString([
        merged['channel'],
        merged['channel_id'],
        merged['channelId'],
      ]),
      iconSmall: firstNonEmptyString([
        merged['icono_pequeno'],
        merged['icon_small'],
        merged['small_icon'],
        merged['ic_stat_onesignal_default'],
      ]),
      iconLarge: firstNonEmptyString([
        merged['icono_grande'],
        merged['icon_large'],
        merged['large_icon'],
        merged['image'],
      ]),
      imageUrl: firstNonEmptyString([
        merged['image_url'],
        merged['image'],
        merged['img'],
        merged['icono_grande'],
      ]),
      dynamicLink: firstNonEmptyString([
        merged['dynamic_link'],
        merged['dynamicLink'],
        merged['url'],
      ]),
      data: additionalData,
      entityIds: entityIds,
    );
  }

  String _resolveEventId(
    Map<String, dynamic> merged, {
    required String title,
    required String body,
    required String? route,
    required Map<String, dynamic> additionalData,
  }) {
    final explicitId = _extractEventKey(additionalData, merged);
    if (explicitId != null && explicitId.isNotEmpty) {
      return explicitId;
    }

    final canonical = jsonEncode({
      'title': title,
      'body': body,
      'route': route,
      'data': additionalData,
    });
    return 'evt_${deriveStableHash(canonical)}';
  }

  String? _extractEventKey(Map<String, dynamic> additionalData, Map<String, dynamic> merged) {
    final candidates = <dynamic>[
      additionalData['notf_id'],
      additionalData['event_id'],
      additionalData['id_notificacion'],
      additionalData['notification_id'],
      merged['notf_id'],
      merged['event_id'],
      merged['notification_id'],
      merged['id_notificacion'],
      merged['message_id'],
      merged['id'],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String _resolveGroupKey(
    Map<String, dynamic> merged,
    Map<String, dynamic> additionalData, {
    required String title,
  }) {
    final candidates = <dynamic>[
      merged['grp'],
      additionalData['grp'],
      merged['groupId'],
      additionalData['groupId'],
      merged['group_key'],
      merged['group_id'],
      merged['thread_id'],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    final normalizedTitle = title.trim();
    return normalizedTitle.isEmpty ? 'Sin titulo' : normalizedTitle;
  }

  Map<String, dynamic> _extractAdditionalData(
    Map<String, dynamic> merged,
    String? route,
  ) {
    final additionalData = <String, dynamic>{};

    for (final entry in merged.entries) {
      if (_reservedPayloadKeys.contains(entry.key)) continue;
      additionalData.putIfAbsent(entry.key, () => _jsonSafeValue(entry.value));
    }

    if (route != null && route.isNotEmpty) {
      additionalData['ruta'] = route;
    }

    return additionalData;
  }

  Map<String, String> _extractEntityIds(Map<String, dynamic> merged) {
    final entityIds = <String, String>{};
    for (final key in _knownEntityIdKeys) {
      final value = merged[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        entityIds[key] = value;
      }
    }
    return entityIds;
  }

  String? _extractSound(Map<String, dynamic> payload) {
    final direct = firstNonEmptyString([
      payload['sound'],
      payload['sonido'],
      payload['alert'],
    ]);
    if (direct != null) return direct;

    final aps = payload['aps'];
    if (aps is Map) {
      final apsMap = Map<String, dynamic>.from(aps);
      final apsSound = apsMap['sound'];
      if (apsSound is String) {
        final normalized = apsSound.trim();
        if (normalized.isNotEmpty) return normalized;
      }
      if (apsSound is Map) {
        final soundName = apsSound['name']?.toString().trim();
        if (soundName != null && soundName.isNotEmpty) return soundName;
      }
    }
    return null;
  }

  dynamic _jsonSafeValue(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((key, nestedValue) =>
            MapEntry(key.toString(), _jsonSafeValue(nestedValue))),
      );
    }
    if (value is List) {
      return value.map(_jsonSafeValue).toList();
    }
    return value;
  }
}
