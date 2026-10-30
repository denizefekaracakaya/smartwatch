import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/playback_controller.dart';
import '../screens/player_screen.dart';
import '../theme.dart';
import 'cover_art.dart';

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
    return Material(
      color: AppColors.surfaceHigh,
      child: InkWell(
        onTap: track == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const PlayerScreen(),
                )),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
            child: Row(children: [
              if (track != null) CoverArt.track(track, size: 40) else const SizedBox(width: 40, height: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    track?.title ?? 'Yükleniyor…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    track?.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ]),
              ),
              IconButton(
                tooltip: player.playing ? 'Duraklat' : 'Çal',
                icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                onPressed: track == null ? null : player.togglePlay,
              ),
              IconButton(
                tooltip: 'Sonraki',
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: player.player.hasNext ? player.next : null,
              ),
            ]),
          ),
          StreamBuilder<Duration>(
            stream: player.player.positionStream,
            builder: (context, snap) {
              final total = player.player.duration ?? track?.duration ?? Duration.zero;
              final pos = snap.data ?? Duration.zero;
              final value = total.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / total.inMilliseconds;
              return LinearProgressIndicator(
                value: player.loading ? null : value.clamp(0.0, 1.0),
                minHeight: 2,
                color: AppColors.text,
                backgroundColor: AppColors.outline,
              );
            },
          ),
        ]),
      ),
    );
  }
}
