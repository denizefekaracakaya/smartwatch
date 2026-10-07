import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/messages.dart';
import '../../api/models.dart';
import '../../state/auth_state.dart';
import '../widgets/common.dart';
import '../widgets/track_tile.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Keşfet'),
          bottom: const TabBar(tabs: [Tab(text: 'Şarkılar'), Tab(text: 'Podcastler')]),
        ),
        body: const TabBarView(children: [
          _CatalogList(kind: TrackKind.song),
          _CatalogList(kind: TrackKind.podcast),
        ]),
      ),
    );
  }
}

/// Infinite-scrolling catalog list for one [TrackKind].
class _CatalogList extends StatefulWidget {
  const _CatalogList({required this.kind});

  final TrackKind kind;

  @override
  State<_CatalogList> createState() => _CatalogListState();
}

class _CatalogListState extends State<_CatalogList> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;
  final _tracks = <Track>[];
  int _total = 0;
  bool _loading = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await context
          .read<AuthState>()
          .api
          .tracks(kind: widget.kind, limit: _pageSize, offset: reset ? 0 : _tracks.length);
      if (!mounted) return;
      setState(() {
        if (reset) _tracks.clear();
        _tracks.addAll(page.items);
        _total = page.total;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _tracks.isEmpty) {
      return ErrorRetry(message: errorMessage(_error!), onRetry: () => _load(reset: true));
    }
    if (_tracks.isEmpty) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : const EmptyState(icon: Icons.music_off, message: 'Katalog henüz boş.');
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400 && _tracks.length < _total && !_loading) _load();
          return false;
        },
        child: ListView.builder(
          itemCount: _tracks.length + (_tracks.length < _total ? 1 : 0),
          itemBuilder: (context, i) => i == _tracks.length
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              : TrackTile(tracks: _tracks, index: i),
        ),
      ),
    );
  }
}
