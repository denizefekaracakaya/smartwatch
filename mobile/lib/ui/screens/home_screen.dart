import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/messages.dart';
import '../../api/models.dart';
import '../../state/auth_state.dart';
import '../../state/playback_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/track_tile.dart';
import 'artist_screen.dart';

/// Start page: artists row, then the whole song list (newest first), then podcasts if there are any.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 50;
  List<Artist> _artists = const [];
  final _songs = <Track>[];
  int _songTotal = 0;
  List<Track> _podcasts = const [];
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<AuthState>().api;
    try {
      final results = await Future.wait([
        api.artists(kind: TrackKind.song),
        api.tracks(kind: TrackKind.song, alphabetical: true, limit: _pageSize),
        api.tracks(kind: TrackKind.podcast, limit: 20),
      ]);
      if (!mounted) return;
      final songs = results[1] as TrackPage;
      setState(() {
        _artists = results[0] as List<Artist>;
        _songs
          ..clear()
          ..addAll(songs.items);
        _songTotal = songs.total;
        _podcasts = (results[2] as TrackPage).items;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _songs.length >= _songTotal) return;
    _loadingMore = true;
    try {
      final page = await context
          .read<AuthState>()
          .api
          .tracks(kind: TrackKind.song, alphabetical: true, limit: _pageSize, offset: _songs.length);
      if (mounted) setState(() => _songs.addAll(page.items));
    } catch (_) {
      // The next scroll retries; a failed page is not worth an error screen.
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Widget body;
    if (_error != null && _songs.isEmpty) {
      body = ErrorRetry(message: errorMessage(_error!), onRetry: _refresh);
    } else if (_songs.isEmpty && _podcasts.isEmpty) {
      body = _loading
          ? const Center(child: CircularProgressIndicator())
          : const EmptyState(
              icon: Icons.library_music_outlined,
              message: 'Sunucuda henüz şarkı yok.\nBilgisayarındaki müzikleri add_music.ps1 ile ekleyebilirsin.',
            );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) _loadMore();
            return false;
          },
          child: CustomScrollView(slivers: [
            if (_artists.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader('Sanatçılar')),
              SliverToBoxAdapter(child: _ArtistRow(artists: _artists)),
            ],
            SliverToBoxAdapter(
              child: SectionHeader(
                'Şarkılar · $_songTotal',
                trailing: _songs.isEmpty
                    ? null
                    : TextButton.icon(
                        onPressed: () => context.read<PlaybackController>().playShuffled(_songs),
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('Karıştır'),
                      ),
              ),
            ),
            SliverList.builder(
              itemCount: _songs.length,
              itemBuilder: (_, i) => TrackTile(tracks: _songs, index: i),
            ),
            if (_podcasts.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader('Podcastler')),
              SliverList.builder(
                itemCount: _podcasts.length,
                itemBuilder: (_, i) => TrackTile(tracks: _podcasts, index: i),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Efetüfe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.8)),
      ),
      body: body,
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artists});

  final List<Artist> artists;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: artists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final artist = artists[i];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => ArtistScreen(artist: artist.name)),
            ),
            child: SizedBox(
              width: 84,
              child: Column(children: [
                CoverArt(seed: artist.name, label: artist.name, size: 84, circle: true),
                const SizedBox(height: 8),
                Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${artist.trackCount} şarkı',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
