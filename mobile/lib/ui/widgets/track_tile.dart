import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/playback_controller.dart';
import '../screens/artist_screen.dart';
import '../theme.dart';
import 'add_to_playlist_sheet.dart';
import 'cover_art.dart';

/// A catalog row. Tapping plays [tracks] starting at [index]; the menu offers "add to playlist", "go to
/// artist" plus any [extraActions] (e.g. "remove from this playlist").
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.tracks,
    required this.index,
    this.subtitle,
    this.extraActions = const [],
    this.showArtistAction = true,
  });

  final List<Track> tracks;
  final int index;
  final String? subtitle;
  final List<TrackAction> extraActions;
  final bool showArtistAction;

  Track get track => tracks[index];

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlaybackController>();
    final isCurrent = player.current?.id == track.id;
    return InkWell(
      onTap: () => context.read<PlaybackController>().playList(tracks, index),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(children: [
          Stack(alignment: Alignment.center, children: [
            CoverArt.track(track, size: 48),
            if (isCurrent)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  player.playing ? Icons.graphic_eq : Icons.pause,
                  color: AppColors.accent,
                  size: 22,
                ),
              ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isCurrent ? AppColors.accent : AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle ?? track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ]),
          ),
          Text(
            formatDuration(track.duration),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Seçenekler',
            icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textMuted),
            onSelected: (value) {
              switch (value) {
                case '_add':
                  showAddToPlaylistSheet(context, track);
                case '_artist':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ArtistScreen(artist: track.artist)),
                  );
                default:
                  extraActions.firstWhere((a) => a.label == value).onSelected();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: '_add', child: Text('Çalma listesine ekle')),
              if (showArtistAction) const PopupMenuItem(value: '_artist', child: Text('Sanatçıya git')),
              for (final action in extraActions) PopupMenuItem(value: action.label, child: Text(action.label)),
            ],
          ),
        ]),
      ),
    );
  }
}

class TrackAction {
  const TrackAction(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}

/// Section title with an optional trailing action, used on list screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// "Çal" + "Karıştır" pair for artist and playlist headers.
class PlayButtons extends StatelessWidget {
  const PlayButtons({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlaybackController>();
    final disabled = tracks.isEmpty;
    return Row(children: [
      FilledButton.icon(
        onPressed: disabled ? null : () => player.playList(tracks, 0),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Çal'),
      ),
      const SizedBox(width: 10),
      OutlinedButton.icon(
        onPressed: disabled ? null : () => player.playShuffled(tracks),
        icon: const Icon(Icons.shuffle, size: 18),
        label: const Text('Karıştır'),
      ),
    ]);
  }
}
