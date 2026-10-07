import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/messages.dart';
import '../../state/library_state.dart';
import '../theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/common.dart';
import 'playlist_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<LibraryState>().reload());
  }

  Future<void> _create() async {
    final name = await promptText(context, title: 'Yeni çalma listesi', label: 'Ad');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await context.read<LibraryState>().create(name);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryState>();
    Widget body;
    if (library.error != null && library.playlists.isEmpty) {
      body = ErrorRetry(message: errorMessage(library.error!), onRetry: library.reload);
    } else if (library.playlists.isEmpty) {
      body = library.loading
          ? const Center(child: CircularProgressIndicator())
          : const EmptyState(
              icon: Icons.queue_music,
              message: 'Henüz çalma listen yok.\nSağ alttaki + ile ilkini oluştur.',
            );
    } else {
      body = RefreshIndicator(
        onRefresh: library.reload,
        child: ListView.builder(
          itemCount: library.playlists.length,
          itemBuilder: (context, i) {
            final p = library.playlists[i];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.queue_music)),
              title: Text(p.name),
              subtitle: Text(
                [if (p.description != null) p.description!, '${p.trackCount} parça'].join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: p.id)))
                  .then((_) => library.reload()),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Kitaplık')),
      body: body,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Yeni çalma listesi',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}
