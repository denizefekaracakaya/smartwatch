import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Error returned by the API (`{"detail": ..., "code": ...}`) or a network failure (`code == 'network'`).
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.detail);

  final int statusCode;
  final String code;
  final String detail;

  @override
  String toString() => 'ApiException($statusCode, $code, $detail)';
}

/// Persists the refresh token and the chosen server address. Access tokens only live in memory.
abstract class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String? token);
  Future<String?> readServerUrl();
  Future<void> writeServerUrl(String? url);
}

class SecureTokenStore implements TokenStore {
  static const _refreshKey = 'refresh_token';
  static const _serverKey = 'server_url';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> writeRefreshToken(String? token) =>
      token == null ? _storage.delete(key: _refreshKey) : _storage.write(key: _refreshKey, value: token);

  @override
  Future<String?> readServerUrl() => _storage.read(key: _serverKey);

  @override
  Future<void> writeServerUrl(String? url) =>
      url == null ? _storage.delete(key: _serverKey) : _storage.write(key: _serverKey, value: url);
}

class MemoryTokenStore implements TokenStore {
  String? token;
  String? serverUrl;

  @override
  Future<String?> readRefreshToken() async => token;

  @override
  Future<void> writeRefreshToken(String? value) async => token = value;

  @override
  Future<String?> readServerUrl() async => serverUrl;

  @override
  Future<void> writeServerUrl(String? value) async => serverUrl = value;
}

/// Thin typed wrapper over the REST API with transparent access-token refresh.
class ApiClient {
  ApiClient({required String baseUrl, required this.tokenStore, http.Client? httpClient})
      : _base = parseServerUrl(baseUrl)!,
        _http = httpClient ?? http.Client();

  Uri _base;

  /// The server this client talks to, without a trailing slash.
  String get baseUrl => _base.toString();

  /// Points the client at another server. Sessions belong to a server, so the stored login is dropped.
  Future<void> setBaseUrl(String url) async {
    final parsed = parseServerUrl(url);
    if (parsed == null) throw ArgumentError.value(url, 'url', 'not an http(s) URL');
    _base = parsed;
    _accessToken = null;
    await tokenStore.writeRefreshToken(null);
  }

  /// Validates and normalises a server address ("192.168.1.8:8000" -> "http://192.168.1.8:8000").
  static Uri? parseServerUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    return uri;
  }
  final http.Client _http;
  final TokenStore tokenStore;
  String? _accessToken;
  Future<bool>? _refreshing;

  /// Called when the session can no longer be refreshed (user must log in again).
  void Function()? onSessionExpired;

  static const _timeout = Duration(seconds: 20);
  static const _assistantTimeout = Duration(seconds: 90);

  // ---------------- auth ----------------
  Future<void> register(String email, String password, String displayName) async {
    await _send('POST', '/auth/register',
        body: {'email': email, 'password': password, 'display_name': displayName}, auth: false);
  }

  Future<User> login(String email, String password) async {
    final json = await _send('POST', '/auth/login', body: {'email': email, 'password': password}, auth: false);
    return _storeSession(TokenPair.fromJson(json as Map<String, dynamic>));
  }

  /// Restores a session from the stored refresh token. Returns null when there is none or it is invalid.
  Future<User?> restoreSession() async {
    if (!await _refresh()) return null;
    return me();
  }

  Future<void> logout() async {
    final refresh = await tokenStore.readRefreshToken();
    _accessToken = null;
    await tokenStore.writeRefreshToken(null);
    if (refresh != null) {
      try {
        await _send('POST', '/auth/logout', body: {'refresh_token': refresh}, auth: false);
      } on ApiException {
        // Local logout already happened; server-side revocation is best effort.
      }
    }
  }

  Future<void> resendVerification(String email) =>
      _send('POST', '/auth/resend-verification', body: {'email': email}, auth: false);

  Future<void> forgotPassword(String email) =>
      _send('POST', '/auth/forgot-password', body: {'email': email}, auth: false);

  Future<void> resetPassword(String email, String code, String newPassword) => _send(
        'POST',
        '/auth/reset-password',
        body: {'email': email, 'code': code, 'new_password': newPassword},
        auth: false,
      );

  Future<User> me() async => User.fromJson(await _send('GET', '/auth/me') as Map<String, dynamic>);

  Future<User> updateDisplayName(String name) async =>
      User.fromJson(await _send('PATCH', '/auth/me', body: {'display_name': name}) as Map<String, dynamic>);

  Future<User> changePassword(String current, String newPassword) async {
    final json = await _send('POST', '/auth/me/change-password',
        body: {'current_password': current, 'new_password': newPassword});
    return _storeSession(TokenPair.fromJson(json as Map<String, dynamic>));
  }

  Future<void> deleteAccount(String password) async {
    await _send('DELETE', '/auth/me', body: {'password': password});
    _accessToken = null;
    await tokenStore.writeRefreshToken(null);
  }

  // ---------------- catalog ----------------
  Future<TrackPage> tracks({String? query, TrackKind? kind, int limit = 50, int offset = 0}) async {
    final json = await _send('GET', '/tracks', query: {
      if (query != null && query.isNotEmpty) 'q': query,
      if (kind != null) 'kind': kind.name,
      'limit': '$limit',
      'offset': '$offset',
    });
    return TrackPage.fromJson(json as Map<String, dynamic>);
  }

  /// Returns a playable URL for [trackId].
  ///
  /// The server builds absolute URLs from its configured public address (APP_PUBLIC_BASE_URL), which may
  /// not be the address this device uses (another IP, `adb reverse`, a changed DHCP lease, …). Since the
  /// API is evidently reachable at [baseUrl], the stream is fetched from there too; only the token is
  /// taken from the server's answer.
  Future<StreamInfo> streamInfo(int trackId) async {
    final info = StreamInfo.fromJson(await _send('GET', '/tracks/$trackId/stream-url') as Map<String, dynamic>);
    final token = Uri.parse(info.url).queryParameters['token'];
    if (token == null) return info;
    final url = _base.replace(
      path: '${_base.path}/api/v1/tracks/$trackId/stream',
      queryParameters: {'token': token},
    );
    return StreamInfo(url: url.toString(), mimeType: info.mimeType);
  }

  // ---------------- playlists ----------------
  Future<List<PlaylistSummary>> playlists() async {
    final json = await _send('GET', '/playlists') as List;
    return json.map((e) => PlaylistSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PlaylistDetail> playlist(int id) async =>
      PlaylistDetail.fromJson(await _send('GET', '/playlists/$id') as Map<String, dynamic>);

  Future<PlaylistDetail> createPlaylist(String name, {String? description}) async => PlaylistDetail.fromJson(
      await _send('POST', '/playlists', body: {'name': name, 'description': description})
          as Map<String, dynamic>);

  Future<PlaylistDetail> updatePlaylist(int id, {required String name, String? description}) async =>
      PlaylistDetail.fromJson(await _send('PATCH', '/playlists/$id',
          body: {'name': name, 'description': description}) as Map<String, dynamic>);

  Future<void> deletePlaylist(int id) => _send('DELETE', '/playlists/$id');

  Future<PlaylistDetail> addToPlaylist(int playlistId, int trackId) async => PlaylistDetail.fromJson(
      await _send('POST', '/playlists/$playlistId/tracks', body: {'track_id': trackId})
          as Map<String, dynamic>);

  Future<PlaylistDetail> removeFromPlaylist(int playlistId, int trackId) async => PlaylistDetail.fromJson(
      await _send('DELETE', '/playlists/$playlistId/tracks/$trackId') as Map<String, dynamic>);

  Future<PlaylistDetail> reorderPlaylist(int playlistId, List<int> trackIds) async => PlaylistDetail.fromJson(
      await _send('PUT', '/playlists/$playlistId/tracks', body: {'track_ids': trackIds})
          as Map<String, dynamic>);

  // ---------------- assistant ----------------
  Future<AssistantResult> assistantSearch(String query, {TrackKind? kind}) async =>
      AssistantResult.fromJson(await _send('POST', '/assistant/search',
          body: {'query': query, if (kind != null) 'kind': kind.name},
          timeout: _assistantTimeout) as Map<String, dynamic>);

  // ---------------- internals ----------------
  Future<User> _storeSession(TokenPair pair) async {
    _accessToken = pair.accessToken;
    await tokenStore.writeRefreshToken(pair.refreshToken);
    return pair.user;
  }

  /// Single-flight refresh so parallel 401s trigger only one rotation (rotated tokens are single use).
  Future<bool> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refresh = await tokenStore.readRefreshToken();
    if (refresh == null) return false;
    try {
      final json = await _send('POST', '/auth/refresh', body: {'refresh_token': refresh}, auth: false);
      await _storeSession(TokenPair.fromJson(json as Map<String, dynamic>));
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await tokenStore.writeRefreshToken(null);
        _accessToken = null;
      }
      if (e.code == 'network') rethrow;
      return false;
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
    Duration timeout = _timeout,
    bool retried = false,
  }) async {
    if (auth && _accessToken == null && !retried) {
      await _refresh();
    }
    final uri = _base.replace(path: '${_base.path}/api/v1$path', queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..followRedirects = false;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (auth && _accessToken != null) request.headers['Authorization'] = 'Bearer $_accessToken';

    http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw ApiException(0, 'network', 'Sunucu yanıt vermedi');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'network', e.message);
    }

    if (response.statusCode == 401 && auth && !retried) {
      if (await _refresh()) {
        return _send(method, path, body: body, query: query, timeout: timeout, retried: true);
      }
      onSessionExpired?.call();
    }
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : _tryDecode(text);
    if (response.statusCode >= 400) {
      final map = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
      throw ApiException(
        response.statusCode,
        (map['code'] as String?) ?? 'http_${response.statusCode}',
        (map['detail'] as String?) ?? 'HTTP ${response.statusCode}',
      );
    }
    return decoded;
  }

  static dynamic _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
