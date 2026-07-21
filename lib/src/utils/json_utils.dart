import 'dart:convert';

Map<String, dynamic> decodeNestedData(Map<String, dynamic> data) {
  final rawData = data['data'];
  if (rawData is Map) {
    return Map<String, dynamic>.from(rawData);
  }
  if (rawData is String) {
    final value = rawData.trim();
    if (value.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }
  return const <String, dynamic>{};
}
