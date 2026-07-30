import 'dart:convert';

import '../models/unified_notification_event.dart';

String? extractNotificationType(Map<String, dynamic>? payload) {
  if (payload == null) {
    return null;
  }

  final direct = payload['tipo']?.toString().trim();
  if (direct != null && direct.isNotEmpty) {
    return direct;
  }

  final nestedKeys = ['data', 'additionalData', 'payload_original'];
  for (final key in nestedKeys) {
    final nested = payload[key];
    if (nested is Map) {
      final value = extractNotificationType(Map<String, dynamic>.from(nested));
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    if (nested is String) {
      final normalized = nested.trim();
      if (normalized.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(normalized);
        if (decoded is Map) {
          final value = extractNotificationType(
            Map<String, dynamic>.from(decoded),
          );
          if (value != null && value.isNotEmpty) {
            return value;
          }
        }
      } catch (_) {}
    }
  }

  return null;
}

bool isHiddenOwnNotificationPayload(Map<String, dynamic>? payload) {
  final type = extractNotificationType(payload)?.trim().toUpperCase();
  return type == 'PROPIO';
}

bool isHiddenOwnNotificationEvent(UnifiedNotificationEvent event) {
  return isHiddenOwnNotificationPayload(event.data);
}
