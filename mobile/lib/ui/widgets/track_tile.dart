import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/playback_controller.dart';
import '../theme.dart';
import 'add_to_playlist_sheet.dart';

/// A catalog row. Tapping plays [tracks] starting at [index]; the menu offers "add to playlist" plus any
/// [extraActions] (e.g. "remove from this playlist").
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.tracks,
    required this.index,
    this.subtitle,
    this.extraActions = const [],
    this.trailing,
  });

  final List<Track> tracks;
  final int index;
  final String? subtitle;
  final List<TrackAction> extraActions;
  final Widget? trailing;

  Track get track => tracks[index];

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlaybackController>();
    final isCurrent = player.current?.id == track.id;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCurrent ? scheme.primary : scheme.surfaceContainerHighest,
        foregroundColor: isCurrent ? scheme.onPrimary : scheme.onSurfaceVariant,
        child: Icon(isCurrent && player.playing
            ? Icons.equalizer
            : (track.kind == TrackKind.podcast ? Icons.podcasts : Icons.music_note)),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCurrent ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600) : null,
      ),
      subtitle: Text(
        subtitle ?? '${track.artist} • ${formatDuration(track.duration)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.read<PlaybackController>().playList(tracks, index),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (trailing != null) trailing!,
        PopupMenuButton<String>(
          tooltip: 'Seçenekler',
          onSelected: (value) {
            if (value == '_add') {
              showAddToPlaylistSheet(context, track);
            } else {
              extraActions.firstWhere((a) => a.label == value).onSelected();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: '_add', child: Text('Çalma listesine ekle')),
            for (final action in extraActions) PopupMenuItem(value: action.label, child: Text(action.label)),
          ],
        ),
      ]),
    );
  }
}

class TrackAction {
  const TrackAction(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}
