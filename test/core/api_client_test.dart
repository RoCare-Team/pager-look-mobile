import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veriwork_mobile/core/network/api_client.dart';
import 'package:veriwork_mobile/core/network/api_exception.dart';
import 'package:veriwork_mobile/core/storage/session_store.dart';

/// Records requests and replies from a handler — no network involved.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ({int status, Object? body}) Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final reply = handler(options);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(FakeAdapter adapter) => Dio(
      BaseOptions(baseUrl: 'https://api.test/api', validateStatus: (_) => true),
    )..httpClientAdapter = adapter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionStore store;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = SessionStore();
    await store.load();
  });

  test('unwraps the data envelope and sends the bearer token', () async {
    await store.setTokens(access: 'A1', refresh: 'R1');
    final adapter = FakeAdapter((_) => (status: 200, body: {'success': true, 'data': {'name': 'Asha'}}));
    final client = ApiClient(store, dio: _dio(adapter), refreshDio: _dio(adapter));

    final data = await client.get('/employee/profile');

    expect(data, {'name': 'Asha'});
    expect(adapter.requests.single.headers['Authorization'], 'Bearer A1');
  });

  test('omits the token for auth: false requests', () async {
    await store.setTokens(access: 'A1', refresh: 'R1');
    final adapter = FakeAdapter((_) => (status: 200, body: {'success': true, 'data': {}}));
    final client = ApiClient(store, dio: _dio(adapter), refreshDio: _dio(adapter));

    await client.post('/auth/enterprise/login', body: {'email': 'a@b.co'}, auth: false);

    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('joins validation details into the error message like the web', () async {
    final adapter = FakeAdapter(
      (_) => (
        status: 400,
        body: {
          'success': false,
          'message': 'Validation failed',
          'details': [
            {'message': 'Email is required'},
            'Password is required',
          ],
        },
      ),
    );
    final client = ApiClient(store, dio: _dio(adapter), refreshDio: _dio(adapter));

    expect(
      () => client.post('/auth/enterprise/register', body: {}),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Email is required. Password is required')
          .having((e) => e.status, 'status', 400)),
    );
  });

  test('treats success:false with HTTP 200 as an error', () async {
    final adapter = FakeAdapter((_) => (status: 200, body: {'success': false, 'message': 'Nope'}));
    final client = ApiClient(store, dio: _dio(adapter), refreshDio: _dio(adapter));

    expect(() => client.get('/x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Nope')));
  });

  test('refreshes once on 401, rotates tokens and retries the request', () async {
    await store.setTokens(access: 'OLD', refresh: 'R1');
    final api = FakeAdapter((o) {
      final auth = o.headers['Authorization'];
      return auth == 'Bearer NEW'
          ? (status: 200, body: {'success': true, 'data': 'ok'})
          : (status: 401, body: {'success': false, 'message': 'Token expired'});
    });
    final refresh = FakeAdapter(
      (_) => (status: 200, body: {'success': true, 'data': {'accessToken': 'NEW', 'refreshToken': 'R2'}}),
    );
    final client = ApiClient(store, dio: _dio(api), refreshDio: _dio(refresh));

    final results = await Future.wait([client.get('/a'), client.get('/b')]);

    expect(results, ['ok', 'ok']);
    expect(refresh.requests, hasLength(1), reason: 'parallel 401s share one refresh');
    expect(store.accessToken, 'NEW');
    expect(store.refreshToken, 'R2');
  });

  test('a rejected refresh clears the session and reports expiry', () async {
    await store.setTokens(access: 'OLD', refresh: 'BAD');
    await store.setUser({'id': 'u1', 'role': 'employee'});
    var expired = false;
    final api = FakeAdapter((_) => (status: 401, body: {'success': false, 'message': 'Token expired'}));
    final refresh = FakeAdapter((_) => (status: 401, body: {'success': false, 'message': 'Invalid refresh token'}));
    final client = ApiClient(store, dio: _dio(api), refreshDio: _dio(refresh))..onSessionExpired = () => expired = true;

    await expectLater(client.get('/a'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    expect(expired, isTrue);
    expect(store.accessToken, isNull);
    expect(store.user, isNull);
  });

  test('does not try to refresh unauthenticated requests', () async {
    final api = FakeAdapter((_) => (status: 401, body: {'success': false, 'message': 'Invalid email or password'}));
    final refresh = FakeAdapter((_) => (status: 200, body: {'success': true, 'data': {}}));
    final client = ApiClient(store, dio: _dio(api), refreshDio: _dio(refresh));

    await expectLater(
      client.post('/auth/enterprise/login', body: {}, auth: false),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid email or password')),
    );
    expect(refresh.requests, isEmpty);
  });

  test('drops empty query parameters', () async {
    final adapter = FakeAdapter((_) => (status: 200, body: {'success': true, 'data': []}));
    final client = ApiClient(store, dio: _dio(adapter), refreshDio: _dio(adapter));

    await client.get('/admin/employees', query: {'status': 'active', 'q': ''});

    expect(adapter.requests.single.queryParameters, {'status': 'active'});
  });
}
