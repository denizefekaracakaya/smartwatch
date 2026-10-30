import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/messages.dart';
import '../../api/models.dart';
import '../../state/auth_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.artist});

  final String artist;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  List<Track>? _tracks;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await context.read<AuthState>().api.tracks(artist: widget.artist, limit: 100);
      if (mounted) setState(() => _tracks = page.items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    return Scaffold(
      appBar: AppBar(),
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      body: _error != null
          ? ErrorRetry(message: errorMessage(_error!), onRetry: _load)
          : tracks == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(children: [
                      CoverArt(seed: widget.artist, label: widget.artist, size: 96, circle: true),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.artist, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 4),
                          Text(
                            summarize(tracks.length, tracks.fold(Duration.zero, (sum, t) => sum + t.duration)),
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: PlayButtons(tracks: tracks),
                  ),
                  for (var i = 0; i < tracks.length; i++)
                    TrackTile(tracks: tracks, index: i, showArtistAction: false, subtitle: tracks[i].album ?? tracks[i].genre),
                ]),
    );
  }
}
