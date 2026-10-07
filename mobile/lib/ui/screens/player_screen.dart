import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/playback_controller.dart';
import '../theme.dart';
import '../widgets/add_to_playlist_sheet.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlaybackController>();
    final track = state.current;
    final scheme = Theme.of(context).colorScheme;
    if (track == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Şu anda çalan bir şey yok.')));
    }
    final player = state.player;
    return Scaffold(
      appBar: AppBar(
        title: Text(track.kind == TrackKind.podcast ? 'Podcast' : 'Şimdi çalıyor'),
        actions: [
          IconButton(
            tooltip: 'Çalma listesine ekle',
            icon: const Icon(Icons.playlist_add),
            onPressed: () => showAddToPlaylistSheet(context, track),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      track.kind == TrackKind.podcast ? Icons.podcasts : Icons.album,
                      size: 120,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(track.title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              [track.artist, if (track.album != null && track.album != track.artist) track.album].join(' • '),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snap) {
                final total = player.duration ?? track.duration;
                final position = snap.data ?? Duration.zero;
                final max = total.inMilliseconds.toDouble();
                return Column(children: [
                  Slider(
                    value: max <= 0 ? 0 : position.inMilliseconds.clamp(0, max).toDouble(),
                    max: max <= 0 ? 1 : max,
                    onChanged: max <= 0 ? null : (v) => state.seek(Duration(milliseconds: v.round())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(formatDuration(position)),
                      Text(formatDuration(total)),
                    ]),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              StreamBuilder<bool>(
                stream: player.shuffleModeEnabledStream,
                builder: (_, snap) => IconButton(
                  tooltip: 'Karıştır',
                  icon: Icon(Icons.shuffle, color: (snap.data ?? false) ? scheme.primary : null),
                  onPressed: () async {
                    final enable = !(snap.data ?? false);
                    if (enable) await player.shuffle();
                    await player.setShuffleModeEnabled(enable);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Önceki',
                iconSize: 40,
                icon: const Icon(Icons.skip_previous),
                onPressed: state.previous,
              ),
              IconButton.filled(
                tooltip: state.playing ? 'Duraklat' : 'Çal',
                iconSize: 48,
                icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
                onPressed: state.togglePlay,
              ),
              IconButton(
                tooltip: 'Sonraki',
                iconSize: 40,
                icon: const Icon(Icons.skip_next),
                onPressed: player.hasNext ? state.next : null,
              ),
              StreamBuilder<LoopMode>(
                stream: player.loopModeStream,
                builder: (_, snap) {
                  final mode = snap.data ?? LoopMode.off;
                  return IconButton(
                    tooltip: 'Tekrarla',
                    icon: Icon(
                      mode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                      color: mode == LoopMode.off ? null : scheme.primary,
                    ),
                    onPressed: () => player.setLoopMode(
                      LoopMode.values[(mode.index + 1) % LoopMode.values.length],
                    ),
                  );
                },
              ),
            ]),
            if (track.description != null) ...[
              const SizedBox(height: 16),
              Text(
                track.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
