import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/playback_controller.dart';
import '../theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/cover_art.dart';
import 'artist_screen.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlaybackController>();
    final track = state.current;
    if (track == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Şu anda çalan bir şey yok.')));
    }
    final player = state.player;
    final queue = state.queue;
    final position = queue.indexWhere((t) => t.id == track.id);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kapat',
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          queue.length > 1 ? '${position + 1} / ${queue.length}' : '',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w500),
        ),
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
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size = box.biggest.shortestSide;
                    return CoverArt.track(track, size: size);
                  },
                ),
              ),
            ),
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ArtistScreen(artist: track.artist)),
                ),
                child: Text(
                  [track.artist, if (track.album != null && track.album != track.artist) track.album].join(' · '),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snap) {
                final total = player.duration ?? track.duration;
                final position = snap.data ?? Duration.zero;
                final max = total.inMilliseconds.toDouble();
                return Column(children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      // Full-width track, aligned with the text above.
                      trackShape: const RectangularSliderTrackShape(),
                    ),
                    child: Slider(
                      padding: EdgeInsets.zero,
                      value: max <= 0 ? 0 : position.inMilliseconds.clamp(0, max).toDouble(),
                      max: max <= 0 ? 1 : max,
                      onChanged: max <= 0 ? null : (v) => state.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(formatDuration(position), style: _timeStyle),
                    Text(formatDuration(total), style: _timeStyle),
                  ]),
                ]);
              },
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              StreamBuilder<bool>(
                stream: player.shuffleModeEnabledStream,
                builder: (_, snap) => IconButton(
                  tooltip: 'Karıştır',
                  icon: Icon(Icons.shuffle, color: (snap.data ?? false) ? AppColors.accent : AppColors.textMuted),
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
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: state.previous,
              ),
              SizedBox(
                width: 72,
                height: 72,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.text,
                    foregroundColor: AppColors.background,
                  ),
                  tooltip: state.playing ? 'Duraklat' : 'Çal',
                  iconSize: 40,
                  icon: Icon(state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  onPressed: state.togglePlay,
                ),
              ),
              IconButton(
                tooltip: 'Sonraki',
                iconSize: 40,
                icon: const Icon(Icons.skip_next_rounded),
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
                      color: mode == LoopMode.off ? AppColors.textMuted : AppColors.accent,
                    ),
                    onPressed: () => player.setLoopMode(
                      LoopMode.values[(mode.index + 1) % LoopMode.values.length],
                    ),
                  );
                },
              ),
            ]),
            if (track.kind == TrackKind.podcast && track.description != null) ...[
              const SizedBox(height: 12),
              Text(
                track.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

const _timeStyle = TextStyle(
  fontSize: 12,
  color: AppColors.textMuted,
  fontFeatures: [FontFeature.tabularFigures()],
);
