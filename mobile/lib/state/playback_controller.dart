import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../api/api_client.dart';
import '../api/messages.dart';
import '../api/models.dart';

/// Owns the audio player and the play queue. Audio is streamed (HTTP range requests); nothing is downloaded
/// to permanent storage.
class PlaybackController extends ChangeNotifier {
  PlaybackController(this.api, {AudioPlayer? player}) : player = player ?? AudioPlayer() {
    _subscriptions.add(this.player.currentIndexStream.listen((index) {
      _currentIndex = index;
      notifyListeners();
    }));
    _subscriptions.add(this.player.playerStateStream.listen((_) => notifyListeners()));
    _subscriptions.add(this.player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace _) {
        error = 'Parça çalınamadı. Lütfen tekrar deneyin.';
        notifyListeners();
      },
    ));
  }

  /// Upper bound on how many stream URLs are requested when a long list is queued.
  static const maxQueue = 100;

  final ApiClient api;
  final AudioPlayer player;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  List<Track> _queue = const [];
  int? _currentIndex;
  bool loading = false;
  String? error;

  List<Track> get queue => _queue;
  Track? get current =>
      (_currentIndex != null && _currentIndex! < _queue.length) ? _queue[_currentIndex!] : null;
  /// just_audio keeps `playing == true` after the queue completes; for the UI that is "not playing".
  bool get playing => player.playing && player.processingState != ProcessingState.completed;

  /// Replace the queue with [tracks] and start playing at [index].
  Future<void> playList(List<Track> tracks, int index) async {
    if (tracks.isEmpty) return;
    final start = (index - maxQueue ~/ 2).clamp(0, tracks.length > maxQueue ? tracks.length - maxQueue : 0);
    final window = tracks.sublist(start, (start + maxQueue).clamp(0, tracks.length));
    loading = true;
    error = null;
    notifyListeners();
    try {
      final infos = await Future.wait(window.map((t) => api.streamInfo(t.id)));
      final sources = <AudioSource>[
        for (var i = 0; i < window.length; i++)
          AudioSource.uri(
            Uri.parse(infos[i].url),
            tag: MediaItem(
              id: '${window[i].id}',
              title: window[i].title,
              artist: window[i].artist,
              album: window[i].album,
              duration: window[i].durationSeconds > 0 ? window[i].duration : null,
            ),
          ),
      ];
      _queue = window;
      await player.setAudioSources(sources, initialIndex: index - start);
      unawaited(player.play());
    } on ApiException catch (e) {
      error = errorMessage(e);
    } on PlayerException {
      error = 'Parça yüklenemedi.';
    } catch (_) {
      error = 'Parça çalınamadı.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (player.processingState == ProcessingState.completed) {
      // Replay the queue from the start instead of doing nothing at the end.
      await player.seek(Duration.zero, index: 0);
      await player.play();
    } else if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }
  Future<void> next() => player.seekToNext();
  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> stop() async {
    await player.stop();
    _queue = const [];
    _currentIndex = null;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
