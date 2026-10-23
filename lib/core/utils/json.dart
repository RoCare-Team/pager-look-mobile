/// Null-safe readers for the API's loosely-shaped JSON.
///
/// The backend returns plain JSON maps (as the web consumes them), and several
/// endpoints vary their shape slightly (`{ items: [...] }` vs a bare list,
/// `_id` vs `id`). These helpers keep screens free of casts and null checks.
library;

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

List<dynamic> asList(Object? value) => value is List ? value : const [];

List<Map<String, dynamic>> asMapList(Object? value) => asList(value).whereType<Map>().map(asMap).toList();

/// First list found at [keys] on a map response, or the value itself when the
/// response is already a list.
List<Map<String, dynamic>> listFrom(
  Object? data, [
  List<String> keys = const ['items', 'data', 'results', 'records'],
]) {
  if (data is List) return asMapList(data);
  final map = asMap(data);
  for (final key in keys) {
    if (map[key] is List) return asMapList(map[key]);
  }
  return const [];
}

String str(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  final s = value.toString();
  return s.isEmpty ? fallback : s;
}

String? strOrNull(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

bool asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true' || value == '1';
  return false;
}

num? asNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

int asInt(Object? value, [int fallback = 0]) => asNum(value)?.toInt() ?? fallback;

double asDouble(Object? value, [double fallback = 0]) => asNum(value)?.toDouble() ?? fallback;

DateTime? asDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value)?.toLocal();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// Read a dotted path: `pick(profile, 'education.class10.board')`.
dynamic pick(Object? root, String path) {
  dynamic current = root;
  for (final segment in path.split('.')) {
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

/// Mongo documents come back with `_id`, some DTOs with `id`.
String idOf(Object? item) {
  final map = asMap(item);
  return str(map['_id'] ?? map['id']);
}
