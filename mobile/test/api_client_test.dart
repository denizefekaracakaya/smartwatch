import 'dart:convert';

import 'package:efetufe/api/api_client.dart';
import 'package:efetufe/api/messages.dart';
import 'package:efetufe/api/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _user() =>
    {'id': 1, 'email': 'a@b.co', 'display_name': 'Ada', 'email_verified': true, 'created_at': '2026-01-01T00:00:00Z'};

Map<String, dynamic> _pair(String access, String refresh) =>
    {'access_token': access, 'refresh_token': refresh, 'token_type': 'bearer', 'expires_in': 900, 'user': _user()};

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('login stores the refresh token and sends the access token afterwards', () async {
    final store = MemoryTokenStore();
    String? seenAuth;
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/auth/login') {
        expect(jsonDecode(req.body), {'email': 'a@b.co', 'password': 'pw'});
        return _json(_pair('access-1', 'refresh-1'));
      }
      seenAuth = req.headers['Authorization'];
      return _json(_user());
    });
    final api = ApiClient(baseUrl: 'http://api.test/', tokenStore: store, httpClient: client);

    final user = await api.login('a@b.co', 'pw');
    expect(user.displayName, 'Ada');
    expect(store.token, 'refresh-1');
    await api.me();
    expect(seenAuth, 'Bearer access-1');
  });

  test('a 401 triggers one refresh (single flight) and the requests are retried', () async {
    final store = MemoryTokenStore()..token = 'refresh-old';
    var refreshCalls = 0;
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/auth/refresh') {
        refreshCalls++;
        expect(jsonDecode(req.body)['refresh_token'], 'refresh-old');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _json(_pair('access-new', 'refresh-new'));
      }
      if (req.headers['Authorization'] == 'Bearer access-new') {
        return _json({'items': [], 'total': 0, 'limit': 50, 'offset': 0});
      }
      return _json({'detail': 'expired', 'code': 'unauthorized'}, 401);
    });
    final api = ApiClient(baseUrl: 'http://api.test', tokenStore: store, httpClient: client);

    final results = await Future.wait([api.tracks(), api.tracks(query: 'x'), api.tracks(kind: TrackKind.podcast)]);
    expect(results.every((p) => p.total == 0), isTrue);
    expect(refreshCalls, 1);
    expect(store.token, 'refresh-new');
  });

  test('an invalid refresh token clears the session and reports expiry', () async {
    final store = MemoryTokenStore()..token = 'refresh-dead';
    var expired = false;
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/auth/refresh') {
        return _json({'detail': 'Invalid refresh token', 'code': 'invalid_token'}, 401);
      }
      return _json({'detail': 'Not authenticated', 'code': 'unauthorized'}, 401);
    });
    final api = ApiClient(baseUrl: 'http://api.test', tokenStore: store, httpClient: client)
      ..onSessionExpired = () => expired = true;

    expect(await api.restoreSession(), isNull);
    expect(store.token, isNull);
    await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(expired, isTrue);
  });

  test('API errors carry code and map to Turkish messages', () async {
    final client = MockClient((_) async => _json({'detail': 'Incorrect', 'code': 'invalid_credentials'}, 401));
    final api = ApiClient(baseUrl: 'http://api.test', tokenStore: MemoryTokenStore(), httpClient: client);
    try {
      await api.login('a@b.co', 'bad');
      fail('should throw');
    } on ApiException catch (e) {
      expect(e.code, 'invalid_credentials');
      expect(errorMessage(e), 'E-posta veya şifre hatalı.');
    }
  });

  test('network failures become ApiException(code: network)', () async {
    final client = MockClient((_) async => throw http.ClientException('connection refused'));
    final api = ApiClient(baseUrl: 'http://api.test', tokenStore: MemoryTokenStore(), httpClient: client);
    await expectLater(
      api.forgotPassword('a@b.co'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
    );
  });

  test('query parameters and UTF-8 payloads are encoded correctly', () async {
    late Uri seen;
    final client = MockClient((req) async {
      seen = req.url;
      return _json({
        'items': [
          {
            'id': 3, 'kind': 'podcast', 'title': 'Bölüm 3: Sabah Rutini', 'artist': 'İyi Yaşam', 'album': null,
            'genre': null, 'year': null, 'duration_seconds': 61, 'description': null,
          }
        ],
        'total': 1, 'limit': 10, 'offset': 0,
      });
    });
    final api = ApiClient(baseUrl: 'http://api.test', tokenStore: MemoryTokenStore(), httpClient: client);
    final page = await api.tracks(query: 'sabah ğüş', kind: TrackKind.podcast, limit: 10);
    expect(seen.queryParameters, {'q': 'sabah ğüş', 'kind': 'podcast', 'limit': '10', 'offset': '0'});
    expect(page.items.single.title, 'Bölüm 3: Sabah Rutini');
    expect(page.items.single.kind, TrackKind.podcast);
    expect(page.items.single.duration, const Duration(seconds: 61));
  });

  test('client-side validators mirror the server policy', () {
    expect(validatePassword('short1'), isNotNull);
    expect(validatePassword('onlyletterslong'), isNotNull);
    expect(validatePassword('CorrectHorse42'), isNull);
    expect(validateEmail('nope'), isNotNull);
    expect(validateEmail(' ada@example.com '), isNull);
  });
}
