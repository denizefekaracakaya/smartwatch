import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/messages.dart';
import '../../api/models.dart';
import '../../state/auth_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/track_tile.dart';
import 'artist_screen.dart';

/// As-you-type search (typo tolerant on the server). With an empty field it lists all artists.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  Object? _error;
  List<Track> _results = const [];
  List<Artist>? _artists;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadArtists() async {
    try {
      final artists = await context.read<AuthState>().api.artists();
      if (mounted) setState(() => _artists = artists);
    } catch (_) {
      if (mounted) setState(() => _artists = const []);
    }
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
    setState(() {}); // update the clear button
  }

  Future<void> _run() async {
    final query = _controller.text.trim();
    final id = ++_requestId;
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await context.read<AuthState>().api.tracks(query: query, limit: 50);
      if (id == _requestId && mounted) setState(() => _results = page.items);
    } catch (e) {
      if (id == _requestId && mounted) setState(() => _error = e);
    } finally {
      if (id == _requestId && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ara')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('search-field'),
            controller: _controller,
            onChanged: _onChanged,
            onSubmitted: (_) => _run(),
            textInputAction: TextInputAction.search,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Şarkı, sanatçı veya albüm',
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Temizle',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
              counterText: '',
            ),
          ),
        ),
        SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_error != null) return ErrorRetry(message: errorMessage(_error!), onRetry: _run);
    if (_controller.text.trim().length < 2) return _artistList();
    if (_results.isEmpty && !_loading) {
      return const EmptyState(icon: Icons.search_off, message: 'Bu aramayla eşleşen bir şey yok.');
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, i) => TrackTile(tracks: _results, index: i),
    );
  }

  Widget _artistList() {
    final artists = _artists;
    if (artists == null) return const SizedBox.shrink();
    if (artists.isEmpty) {
      return const EmptyState(icon: Icons.search, message: 'Aramak için yazmaya başla.');
    }
    return ListView(children: [
      const SectionHeader('Sanatçılar'),
      for (final artist in artists)
        ListTile(
          leading: CoverArt(seed: artist.name, label: artist.name, size: 44, circle: true),
          title: Text(artist.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${artist.trackCount} şarkı', style: const TextStyle(color: AppColors.textMuted)),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ArtistScreen(artist: artist.name)),
          ),
        ),
    ]);
  }
}
