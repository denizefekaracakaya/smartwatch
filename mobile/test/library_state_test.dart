import 'dart:convert';

import 'package:efetufe/api/api_client.dart';
import 'package:efetufe/state/library_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _track(int id) => {
      'id': id, 'kind': 'song', 'title': 'T$id', 'artist': 'A', 'album': null, 'genre': null,
      'year': null, 'duration_seconds': 30, 'description': null,
    };

/// Tiny in-memory fake of the playlist endpoints.
class _FakeServer {
  final playlists = <int, Map<String, dynamic>>{};
  var nextId = 1;

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path.replaceFirst('/api/v1', '');
    if (path == '/auth/refresh') return _json({'detail': 'no', 'code': 'invalid_token'}, 401);
    if (req.method == 'GET' && path == '/playlists') {
      return _json([
        for (final p in playlists.values)
          {'id': p['id'], 'name': p['name'], 'description': null, 'track_count': (p['tracks'] as List).length,
           'updated_at': '2026-01-01T00:00:00Z'},
      ]);
    }
    if (req.method == 'POST' && path == '/playlists') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final p = {'id': nextId++, 'name': body['name'], 'description': null, 'tracks': <Map<String, dynamic>>[]};
      playlists[p['id'] as int] = p;
      return _json({...p, 'track_count': 0, 'updated_at': '2026-01-01T00:00:00Z'}, 201);
    }
    final add = RegExp(r'^/playlists/(\d+)/tracks$').firstMatch(path);
    if (req.method == 'POST' && add != null) {
      final p = playlists[int.parse(add.group(1)!)];
      if (p == null) return _json({'detail': 'nf', 'code': 'not_found'}, 404);
      final id = (jsonDecode(req.body) as Map<String, dynamic>)['track_id'] as int;
      final tracks = p['tracks'] as List<Map<String, dynamic>>;
      if (tracks.any((t) => t['id'] == id)) return _json({'detail': 'dup', 'code': 'already_in_playlist'}, 409);
      tracks.add(_track(id));
      return _json({...p, 'track_count': tracks.length, 'updated_at': '2026-01-01T00:00:00Z'}, 201);
    }
    final del = RegExp(r'^/playlists/(\d+)$').firstMatch(path);
    if (req.method == 'DELETE' && del != null) {
      playlists.remove(int.parse(del.group(1)!));
      return http.Response('', 204);
    }
    return _json({'detail': 'nf', 'code': 'not_found'}, 404);
  }
}

void main() {
  late _FakeServer server;
  late LibraryState library;

  setUp(() {
    server = _FakeServer();
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient(server.handle),
    );
    library = LibraryState(api);
  });

  test('create, add tracks and delete keep the summary list in sync', () async {
    var notifications = 0;
    library.addListener(() => notifications++);

    final created = await library.create('  Yolculuk ');
    expect(created.name, 'Yolculuk');
    expect(library.playlists.single.trackCount, 0);

    await library.addTrack(created.id, 7);
    await library.addTrack(created.id, 8);
    expect(library.playlists.single.trackCount, 2);

    await expectLater(
      library.addTrack(created.id, 7),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'already_in_playlist')),
    );

    await library.delete(created.id);
    expect(library.playlists, isEmpty);
    expect(library.loading, isFalse);
    expect(notifications, greaterThan(0));
  });

  test('reload errors are captured instead of thrown', () async {
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((_) async => throw http.ClientException('offline')),
    );
    final offline = LibraryState(api);
    await offline.reload();
    expect(offline.error, isA<ApiException>());
    expect(offline.loading, isFalse);
  });

  test('clear() forgets the previous user\'s playlists', () async {
    await library.create('Mine');
    library.clear();
    expect(library.playlists, isEmpty);
  });
}
