/// Maps a scanned QR value (or a pasted link) onto an in-app route.
///
/// PagerLook QR codes and emails carry web links such as
/// `https://www.pagerlook.com/join/AB12CD` or
/// `https://www.pagerlook.com/employee/join?token=…`. The mobile routes use the
/// same paths, so the path is reused as-is. Bare paths (`/u/priya`) and links
/// without a scheme (`www.pagerlook.com/join/AB12CD`) are accepted too.
///
/// Returns null when the value is not a PagerLook link this app can open.
library;

String? routeForScannedValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  try {
    return _route(Uri.parse(value));
  } catch (_) {
    // Malformed URI or percent-encoding — not something we can open.
    return null;
  }
}

String? _route(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') return null;

  var segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  // `www.pagerlook.com/join/X` parses as a relative path whose first segment
  // is the host name.
  if (scheme.isEmpty && segments.isNotEmpty && segments.first.contains('.')) {
    segments = segments.sublist(1);
  }
  if (segments.isEmpty) return null;

  if (segments.length != 2) return null;

  final first = segments[0].toLowerCase();
  final second = segments[1].trim();
  if (second.isEmpty) return null;

  // `/join/<code>`, `/u/<slug>`, `/verify-employment/<token>`
  final encoded = Uri.encodeComponent(second);
  if (first == 'join') return '/join/$encoded';
  if (first == 'u') return '/u/$encoded';
  if (first == 'verify-employment') return '/verify-employment/$encoded';

  // `/employee/join?token=…`, `/enterprise/accept-invite?token=…`
  final secondLower = second.toLowerCase();
  final isEmployeeJoin = first == 'employee' && secondLower == 'join';
  final isAcceptInvite = first == 'enterprise' && secondLower == 'accept-invite';
  if (!isEmployeeJoin && !isAcceptInvite) return null;

  final token = (uri.queryParameters['token'] ?? '').trim();
  if (token.isEmpty) return null;
  final query = 'token=${Uri.encodeQueryComponent(token)}';
  return isEmployeeJoin ? '/employee/join?$query' : '/enterprise/accept-invite?$query';
}

/// For the "Enter code manually" field: accepts either a full link (handled by
/// [routeForScannedValue]) or just the join code printed under the QR.
String? routeForJoinCode(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  final fromLink = routeForScannedValue(value);
  if (fromLink != null) return fromLink;
  if (RegExp(r'^[A-Za-z0-9_-]{3,64}$').hasMatch(value)) {
    return '/join/${Uri.encodeComponent(value)}';
  }
  return null;
}
