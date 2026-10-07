import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/messages.dart';
import '../../api/models.dart';
import '../../state/library_state.dart';
import '../theme.dart';

Future<void> showAddToPlaylistSheet(BuildContext context, Track track) {
  final library = context.read<LibraryState>();
  if (library.playlists.isEmpty) library.reload();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _AddToPlaylistSheet(track: track, parentContext: context),
  );
}

class _AddToPlaylistSheet extends StatelessWidget {
  const _AddToPlaylistSheet({required this.track, required this.parentContext});

  final Track track;
  final BuildContext parentContext;

  Future<void> _add(BuildContext context, int playlistId, String name) async {
    final library = context.read<LibraryState>();
    Navigator.of(context).pop();
    try {
      await library.addTrack(playlistId, track.id);
      if (parentContext.mounted) showSnack(parentContext, '"${track.title}" → $name');
    } on ApiException catch (e) {
      if (parentContext.mounted) showSnack(parentContext, errorMessage(e));
    }
  }

  Future<void> _createAndAdd(BuildContext context) async {
    final name = await promptText(context, title: 'Yeni çalma listesi', label: 'Ad');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final library = context.read<LibraryState>();
    try {
      final created = await library.create(name);
      if (context.mounted) await _add(context, created.id, created.name);
    } on ApiException catch (e) {
      if (parentContext.mounted) showSnack(parentContext, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryState>();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Çalma listesine ekle', style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Yeni çalma listesi'),
            onTap: () => _createAndAdd(context),
          ),
          if (library.loading && library.playlists.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          for (final p in library.playlists)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(p.name),
              subtitle: Text('${p.trackCount} parça'),
              onTap: () => _add(context, p.id, p.name),
            ),
        ]),
      ),
    );
  }
}

/// Simple single-field text dialog. Returns null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  int maxLength = 100,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('İptal')),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Kaydet'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
