import 'dart:convert';

Map<String, dynamic> decodeNestedData(Map<String, dynamic> data) {
  final nested = <String, dynamic>{};

  void mergeMap(dynamic raw) {
    if (raw is Map) {
      nested.addAll(Map<String, dynamic>.from(raw));
      return;
    }
    if (raw is String) {
      final value = raw.trim();
      if (value.isEmpty) {
        return;
      }
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          nested.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
  }

  mergeMap(data['data']);
  mergeMap(data['additionalData']);
  mergeMap(data['a']);

  final custom = data['custom'];
  if (custom is Map) {
    final customMap = Map<String, dynamic>.from(custom);
    mergeMap(customMap['a']);

    final customId = customMap['i']?.toString().trim();
    if (customId != null && customId.isNotEmpty) {
      nested.putIfAbsent('notf_id', () => customId);
      nested.putIfAbsent('event_id', () => customId);
    }

    final collapseId = customMap['collapse_id']?.toString().trim();
    if (collapseId != null && collapseId.isNotEmpty) {
      nested.putIfAbsent('grp', () => collapseId);
      nested.putIfAbsent('groupId', () => collapseId);
    }
  }

  final aps = data['aps'];
  if (aps is Map) {
    final apsMap = Map<String, dynamic>.from(aps);
    final threadId = apsMap['thread-id']?.toString().trim();
    if (threadId != null && threadId.isNotEmpty) {
      nested.putIfAbsent('grp', () => threadId);
      nested.putIfAbsent('groupId', () => threadId);
      nested.putIfAbsent('thread_id', () => threadId);
    }
  }

  return nested;
}
