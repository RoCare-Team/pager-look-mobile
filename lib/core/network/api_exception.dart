/// Error raised for any failed API call — mirrors the `{ message, details, status }`
/// object the web client throws, so screens can show the backend's own message.
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.details});

  final String message;

  /// HTTP status, or null for network/timeout failures.
  final int? status;

  /// The backend's `details` payload (validation errors, `retryAfterSeconds`, …).
  final dynamic details;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;
  bool get isNetwork => status == null;

  /// `details.retryAfterSeconds` on 429 responses (OTP cooldowns).
  int? get retryAfterSeconds {
    final d = details;
    if (d is Map && d['retryAfterSeconds'] is num) {
      return (d['retryAfterSeconds'] as num).toInt();
    }
    return null;
  }

  /// Builds the same message the web's `parseResponse` shows: joined
  /// validation details first, then `message`, then a generic fallback.
  factory ApiException.fromResponse(int status, dynamic body) {
    String? message;
    dynamic details;
    if (body is Map) {
      details = body['details'];
      if (details is List) {
        final joined = details
            .map((d) => d is String ? d : (d is Map ? d['message']?.toString() : null))
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join('. ');
        if (joined.isNotEmpty) message = joined;
      }
      message ??= body['message']?.toString();
    }
    return ApiException(
      (message == null || message.isEmpty) ? 'Request failed ($status)' : message,
      status: status,
      details: details,
    );
  }

  @override
  String toString() => message;
}

/// Human-readable message for any error thrown in the app.
String errorMessage(Object? error, [String fallback = 'Something went wrong']) {
  if (error == null) return fallback;
  if (error is ApiException) return error.message;
  final text = error.toString().replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
  return text.isEmpty ? fallback : text;
}
