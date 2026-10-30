import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/messages.dart';
import '../../api/models.dart';
import '../../state/auth_state.dart';
import '../theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  PlaylistDetail? _playlist;
  Object? _error;
  bool _editing = false;

  ApiClient get _api => context.read<AuthState>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _api.playlist(widget.playlistId);
      if (mounted) {
        setState(() {
          _playlist = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _guard(Future<PlaylistDetail?> Function() action) async {
    try {
      final updated = await action();
      if (updated != null && mounted) setState(() => _playlist = updated);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(e));
    }
  }

  Future<void> _rename() async {
    final p = _playlist!;
    final name = await promptText(context, title: 'Yeniden adlandır', label: 'Ad', initial: p.name);
    if (name == null || name.trim().isEmpty) return;
    await _guard(() => _api.updatePlaylist(p.id, name: name.trim(), description: p.description));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Çalma listesi silinsin mi?'),
        content: Text('"${_playlist!.name}" kalıcı olarak silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Sil')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.deletePlaylist(_playlist!.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(e));
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final tracks = [..._playlist!.tracks];
    if (newIndex > oldIndex) newIndex -= 1;
    tracks.insert(newIndex, tracks.removeAt(oldIndex));
    // optimistic update, then reconcile with the server's answer
    setState(() => _playlist = PlaylistDetail(
        id: _playlist!.id, name: _playlist!.name, description: _playlist!.description, tracks: tracks));
    await _guard(() => _api.reorderPlaylist(_playlist!.id, tracks.map((t) => t.id).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final p = _playlist;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? ErrorRetry(message: errorMessage(_error!), onRetry: _load)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final duration = p.tracks.fold(Duration.zero, (sum, t) => sum + t.duration);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          p.tracks.isEmpty
              ? CoverArt(seed: p.name, label: p.name, size: 112)
              : CoverArt.track(p.tracks.first, size: 112),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ÇALMA LİSTESİ',
                  style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(summarize(p.tracks.length, duration), style: const TextStyle(color: AppColors.textMuted)),
            ]),
          ),
        ]),
        if (p.description != null) ...[
          const SizedBox(height: 10),
          Text(p.description!, style: const TextStyle(color: AppColors.textMuted)),
        ],
        const SizedBox(height: 14),
        PlayButtons(tracks: p.tracks),
      ]),
    );
    return Scaffold(
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      appBar: AppBar(
        actions: [
          if (p.tracks.length > 1)
            IconButton(
              tooltip: _editing ? 'Bitti' : 'Sırala',
              icon: Icon(_editing ? Icons.check : Icons.swap_vert),
              onPressed: () => setState(() => _editing = !_editing),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'rename' ? _rename() : _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Yeniden adlandır')),
              PopupMenuItem(value: 'delete', child: Text('Sil')),
            ],
          ),
        ],
      ),
      body: _editing
          ? ReorderableListView.builder(
              header: header,
              itemCount: p.tracks.length,
              onReorder: _reorder,
              itemBuilder: (_, i) => ListTile(
                key: ValueKey(p.tracks[i].id),
                leading: CoverArt.track(p.tracks[i], size: 40),
                title: Text(p.tracks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(p.tracks[i].artist, style: const TextStyle(color: AppColors.textMuted)),
                trailing: const Icon(Icons.drag_handle),
              ),
            )
          : ListView(children: [
              header,
              if (p.tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Liste boş. Bir şarkının ⋮ menüsünden "Çalma listesine ekle"yi seç.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              for (var i = 0; i < p.tracks.length; i++)
                TrackTile(
                  tracks: p.tracks,
                  index: i,
                  extraActions: [
                    TrackAction('Listeden çıkar', () => _guard(() => _api.removeFromPlaylist(p.id, p.tracks[i].id))),
                  ],
                ),
            ]),
    );
  }
}
