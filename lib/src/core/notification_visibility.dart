import 'dart:convert';

import '../config/unified_notification_config.dart';
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

String? extractNotificationEvent(Map<String, dynamic>? payload) {
  if (payload == null) {
    return null;
  }

  final direct = payload['evento']?.toString().trim();
  if (direct != null && direct.isNotEmpty) {
    return direct;
  }

  final nestedKeys = ['data', 'additionalData', 'payload_original'];
  for (final key in nestedKeys) {
    final nested = payload[key];
    if (nested is Map) {
      final value = extractNotificationEvent(Map<String, dynamic>.from(nested));
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
          final value = extractNotificationEvent(
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

String? _readPayloadPath(Map<String, dynamic>? payload, String path) {
  if (payload == null) {
    return null;
  }

  final segments = path
      .split('.')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    return null;
  }

  dynamic current = payload;
  for (final segment in segments) {
    if (current is Map) {
      current = current[segment];
      continue;
    }

    if (current is String) {
      final normalized = current.trim();
      if (normalized.isEmpty) {
        return null;
      }
      try {
        final decoded = jsonDecode(normalized);
        if (decoded is Map) {
          current = decoded[segment];
          continue;
        }
      } catch (_) {}
    }

    return null;
  }

  final value = current?.toString().trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

bool _matchesHiddenRule(
  Map<String, dynamic>? payload,
  HiddenNotificationRule rule,
) {
  if (payload == null || rule.conditions.isEmpty) {
    return false;
  }

  for (final condition in rule.conditions) {
    if (condition.paths.isEmpty || condition.values.isEmpty) {
      return false;
    }

    final expectedValues = condition.values
        .map((item) => condition.ignoreCase ? item.toLowerCase() : item)
        .toSet();

    var matched = false;
    for (final path in condition.paths) {
      final rawValue = _readPayloadPath(payload, path);
      if (rawValue == null) {
        continue;
      }

      final comparable = condition.ignoreCase
          ? rawValue.toLowerCase()
          : rawValue;
      if (expectedValues.contains(comparable)) {
        matched = true;
        break;
      }
    }

    if (!matched) {
      return false;
    }
  }

  return true;
}

bool isHiddenOwnNotificationPayload(
  Map<String, dynamic>? payload, {
  UnifiedNotificationConfig? config,
}) {
  final hiddenRules = config?.hiddenNotificationRules ?? const [];
  for (final rule in hiddenRules) {
    if (_matchesHiddenRule(payload, rule)) {
      return true;
    }
  }

  final hiddenTypes =
      config?.hiddenNotificationTypes
          .map((item) => item.trim().toUpperCase())
          .where((item) => item.isNotEmpty)
          .toSet() ??
      const <String>{};
  final hiddenEvents =
      config?.hiddenNotificationEvents
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet() ??
      const <String>{};

  final type = extractNotificationType(payload)?.trim().toUpperCase();
  if (type != null && hiddenTypes.contains(type)) {
    return true;
  }

  final event = extractNotificationEvent(payload)?.trim().toLowerCase();
  if (event != null && hiddenEvents.contains(event)) {
    return true;
  }

  return false;
}

bool isHiddenOwnNotificationEvent(
  UnifiedNotificationEvent event, {
  UnifiedNotificationConfig? config,
}) {
  return isHiddenOwnNotificationPayload(event.data, config: config);
}
