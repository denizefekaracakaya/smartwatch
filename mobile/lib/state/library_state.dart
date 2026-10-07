import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// The signed-in user's playlists, shared by the library tab and the "add to playlist" sheet.
class LibraryState extends ChangeNotifier {
  LibraryState(this.api);

  final ApiClient api;
  List<PlaylistSummary> playlists = const [];
  bool loading = false;
  Object? error;

  Future<void> reload() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      playlists = await api.playlists();
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<PlaylistDetail> create(String name, {String? description}) async {
    final created = await api.createPlaylist(name.trim(), description: description);
    await reload();
    return created;
  }

  Future<void> addTrack(int playlistId, int trackId) async {
    await api.addToPlaylist(playlistId, trackId);
    await reload();
  }

  Future<void> delete(int playlistId) async {
    await api.deletePlaylist(playlistId);
    await reload();
  }

  void clear() {
    playlists = const [];
    notifyListeners();
  }
}
