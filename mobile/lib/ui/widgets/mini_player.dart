import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/playback_controller.dart';
import '../screens/player_screen.dart';
import '../theme.dart';

/// Compact player shown above the bottom navigation while something is queued.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlaybackController>();
    if (player.error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || player.error == null) return;
        showSnack(context, player.error!);
        player.clearError();
      });
    }
    final track = player.current;
    if (track == null && !player.loading) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: track == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen())),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          StreamBuilder<Duration>(
            stream: player.player.positionStream,
            builder: (context, snap) {
              final total = player.player.duration ?? track?.duration ?? Duration.zero;
              final pos = snap.data ?? Duration.zero;
              final value = total.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / total.inMilliseconds;
              return LinearProgressIndicator(value: player.loading ? null : value.clamp(0.0, 1.0), minHeight: 2);
            },
          ),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(track?.title ?? 'Yükleniyor…', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(track?.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: player.playing ? 'Duraklat' : 'Çal',
                icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
                onPressed: track == null ? null : player.togglePlay,
              ),
              IconButton(
                tooltip: 'Sonraki',
                icon: const Icon(Icons.skip_next),
                onPressed: player.player.hasNext ? player.next : null,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
