import 'dart:async';

import 'package:dio/dio.dart';

import '../config/env.dart';
import '../storage/session_store.dart';
import 'api_exception.dart';

/// HTTP client for the existing VeriWork REST API — a port of the web's
/// `lib/api.js`:
///
/// * every response uses the `{ success, data, message, details }` envelope;
///   callers receive `data`, failures become [ApiException];
/// * the access token is sent as a Bearer header unless `auth: false`;
/// * a 401 triggers one refresh via `POST /auth/refresh` (single-flight, so
///   parallel requests share one rotation) and the request is retried once;
/// * a failed refresh clears the session and calls [onSessionExpired].
class ApiClient {
  ApiClient(this._session, {Dio? dio, Dio? refreshDio})
      : _dio = dio ?? _buildDio(),
        _refreshDio = refreshDio ?? _buildDio();

  final SessionStore _session;
  final Dio _dio;
  final Dio _refreshDio;

  /// Set by the auth controller so an expired session logs the user out.
  void Function()? onSessionExpired;

  Future<String>? _refreshing;

  static const _refreshPath = '/auth/refresh';

  static Dio _buildDio() => Dio(
        BaseOptions(
          baseUrl: Env.apiUrl,
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 60),
          responseType: ResponseType.json,
          // Status handling is ours — see [_unwrap].
          validateStatus: (_) => true,
          headers: {'Accept': 'application/json'},
        ),
      );

  Future<dynamic> get(String path, {Map<String, dynamic>? query, bool auth = true}) =>
      request('GET', path, query: query, auth: auth);

  Future<dynamic> post(String path, {Object? body, bool auth = true}) => request('POST', path, body: body, auth: auth);

  Future<dynamic> patch(String path, {Object? body, bool auth = true}) =>
      request('PATCH', path, body: body, auth: auth);

  Future<dynamic> put(String path, {Object? body, bool auth = true}) => request('PUT', path, body: body, auth: auth);

  Future<dynamic> delete(String path, {Object? body, bool auth = true}) =>
      request('DELETE', path, body: body, auth: auth);

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
    bool retried = false,
  }) async {
    final headers = <String, dynamic>{};
    final token = _session.accessToken;
    if (auth && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final cleanQuery = query == null
        ? null
        : (Map<String, dynamic>.from(query)..removeWhere((_, v) => v == null || (v is String && v.isEmpty)));

    Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: cleanQuery,
        options: Options(
          method: method,
          headers: headers,
          contentType: body is FormData ? null : Headers.jsonContentType,
        ),
      );
    } on DioException catch (e) {
      throw _networkError(e);
    }

    if (res.statusCode == 401 && auth && !retried && path != _refreshPath) {
      // Throws (and ends the session) when the refresh token is no longer valid.
      await _refreshAccessToken();
      return request(
        method,
        path,
        // A multipart body is single-use; send a fresh copy on retry.
        body: body is FormData ? body.clone() : body,
        query: query,
        auth: auth,
        retried: true,
      );
    }

    return _unwrap(res);
  }

  Future<String> _refreshAccessToken() {
    final existing = _refreshing;
    if (existing != null) return existing;

    final future = _doRefresh();
    _refreshing = future;
    future.whenComplete(() => _refreshing = null).ignore();
    return future;
  }

  Future<String> _doRefresh() async {
    final refreshToken = _session.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _expire();
      throw ApiException('Session expired. Please sign in again.', status: 401);
    }

    Response<dynamic> res;
    try {
      res = await _refreshDio.post<dynamic>(
        _refreshPath,
        data: {'refreshToken': refreshToken},
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      // Offline is not an expired session — keep the tokens.
      throw _networkError(e);
    }

    final body = res.data;
    final ok = (res.statusCode ?? 500) < 400 && body is Map && body['success'] != false;
    if (!ok) {
      await _expire();
      final message = body is Map ? body['message']?.toString() : null;
      throw ApiException(message ?? 'Session expired. Please sign in again.', status: 401);
    }

    final data = body['data'] as Map? ?? const {};
    final access = data['accessToken']?.toString();
    await _session.setTokens(access: access, refresh: data['refreshToken']?.toString());
    return access ?? '';
  }

  Future<void> _expire() async {
    await _session.clear();
    onSessionExpired?.call();
  }

  dynamic _unwrap(Response<dynamic> res) {
    final status = res.statusCode ?? 500;
    final body = res.data;
    if (status >= 400 || (body is Map && body['success'] == false)) {
      throw ApiException.fromResponse(status, body);
    }
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }

  ApiException _networkError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('The server took too long to respond. Please try again.');
      case DioExceptionType.connectionError:
        return ApiException('Unable to reach the server. Check your internet connection.');
      default:
        return ApiException(e.message ?? 'Network error. Please try again.');
    }
  }
}
