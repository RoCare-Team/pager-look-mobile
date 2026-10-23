import 'package:intl/intl.dart';

import '../config/env.dart';
import 'json.dart';

/// Ports of `src/utils/formatters.js` plus small display helpers.

String initials(String? name) {
  if (name == null || name.trim().isEmpty) return '??';
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letters = parts.map((p) => p[0]).join();
  return (letters.length > 2 ? letters.substring(0, 2) : letters).toUpperCase();
}

/// `12 Mar 2026` (web: `formatDate`, en-IN).
String formatDate(Object? value) {
  final d = asDate(value);
  if (d == null) return '—';
  return DateFormat('d MMM yyyy').format(d);
}

/// `Mar 12, 2026` (web: `formatAccessDate`).
String formatAccessDate(Object? value) {
  final d = asDate(value);
  if (d == null) return '—';
  return DateFormat('MMM d, yyyy').format(d);
}

/// `12 Mar 2026, 4:05 PM`.
String formatDateTime(Object? value) {
  final d = asDate(value);
  if (d == null) return '—';
  return DateFormat('d MMM yyyy, h:mm a').format(d);
}

/// `Mar 2024` — for job start/end dates stored as `YYYY-MM` or ISO strings.
String formatMonthYear(Object? value) {
  if (value is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) {
    final d = DateTime.tryParse('$value-01');
    return d == null ? value : DateFormat('MMM yyyy').format(d);
  }
  final d = asDate(value);
  return d == null ? '—' : DateFormat('MMM yyyy').format(d);
}

/// Web: `formatChartMonth`.
String formatChartMonth(Object? value) {
  if (value == null) return '';
  final s = value.toString();
  if (RegExp(r'^[A-Za-z]{3}\s\d{4}$').hasMatch(s)) return s;
  final d = DateTime.tryParse(s.length == 7 ? '$s-01' : s);
  return d == null ? s : DateFormat('MMM yyyy').format(d);
}

/// `just now`, `5m ago`, `3h ago`, `2d ago`, then a date.
String timeAgo(Object? value) {
  final d = asDate(value);
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(d);
}

/// Web: `formatRelativeInviteDate`.
String formatRelativeInviteDate(Object? value) {
  final d = asDate(value);
  if (d == null) return 'Recently';
  final days = DateTime.now().difference(d).inDays;
  if (days <= 0) return 'Invited today';
  if (days == 1) return 'Invited 1 day ago';
  if (days < 7) return 'Invited $days days ago';
  if (days < 30) {
    final weeks = days ~/ 7;
    return weeks == 1 ? 'Invited 1 week ago' : 'Invited $weeks weeks ago';
  }
  return 'Invited ${formatAccessDate(d)}';
}

/// `in_progress` / `inProgress` / `in-progress` → `In progress`.
String humanize(Object? value) {
  final s = str(value);
  if (s.isEmpty) return '';
  final spaced = s
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim()
      .toLowerCase();
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// `hello world` → `Hello World`.
String titleCase(Object? value) => str(value)
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

String formatNumber(Object? value) {
  final n = asNum(value);
  if (n == null) return '0';
  return NumberFormat.decimalPattern('en_IN').format(n);
}

/// Absolute URL for a backend media path (web: `mediaUrl`).
String? mediaUrl(Object? path) {
  final p = strOrNull(path);
  if (p == null) return null;
  if (p.startsWith('http') || p.startsWith('data:')) return p;
  return '${Env.mediaBase}${p.startsWith('/') ? p : '/$p'}';
}

/// Masks all but the last four digits: `XXXX XXXX 1234`.
String maskAadhaar(Object? value) {
  final digits = str(value).replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return digits;
  return 'XXXX XXXX ${digits.substring(digits.length - 4)}';
}
