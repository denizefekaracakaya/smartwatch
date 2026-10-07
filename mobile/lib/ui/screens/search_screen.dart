import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/messages.dart';
import '../../api/models.dart';
import '../../state/auth_state.dart';
import '../widgets/common.dart';
import '../widgets/track_tile.dart';

enum _Mode { quick, assistant }

/// Quick (fuzzy, as-you-type) search, plus the AI assistant for half-remembered songs and podcasts.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  _Mode _mode = _Mode.quick;
  bool _loading = false;
  Object? _error;
  List<Track> _results = const [];
  AssistantResult? _assistant;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_mode == _Mode.assistant) {
      // The assistant field is multi-line for readability, but Enter (e.g. a hardware keyboard) means "ask".
      if (value.contains('\n')) {
        final cleaned = value.replaceAll('\n', ' ').trim();
        _controller.value = TextEditingValue(
          text: cleaned,
          selection: TextSelection.collapsed(offset: cleaned.length),
        );
        _run();
      }
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    final query = _controller.text.trim();
    final id = ++_requestId;
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _assistant = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<AuthState>().api;
    try {
      if (_mode == _Mode.quick) {
        final page = await api.tracks(query: query, limit: 50);
        if (id == _requestId && mounted) setState(() => _results = page.items);
      } else {
        final result = await api.assistantSearch(query);
        if (id == _requestId && mounted) setState(() => _assistant = result);
      }
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
          child: SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.quick, icon: Icon(Icons.search), label: Text('Hızlı arama')),
              ButtonSegment(value: _Mode.assistant, icon: Icon(Icons.auto_awesome), label: Text('AI asistan')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              setState(() {
                _mode = s.first;
                _error = null;
              });
              if (_mode == _Mode.quick) _run();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            key: const Key('search-field'),
            controller: _controller,
            onChanged: _onChanged,
            onSubmitted: (_) => _run(),
            textInputAction: TextInputAction.search,
            maxLength: _mode == _Mode.assistant ? 500 : 200,
            minLines: 1,
            maxLines: _mode == _Mode.assistant ? 3 : 1,
            decoration: InputDecoration(
              hintText: _mode == _Mode.quick
                  ? 'Şarkı, sanatçı, albüm veya podcast'
                  : 'Örn: "nakaratında gel yanıma diyen bir yaz şarkısı"',
              prefixIcon: Icon(_mode == _Mode.quick ? Icons.search : Icons.auto_awesome),
              suffixIcon: _mode == _Mode.assistant
                  ? IconButton(tooltip: 'Sor', icon: const Icon(Icons.send), onPressed: _loading ? null : _run)
                  : null,
              counterText: '',
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_error != null) return ErrorRetry(message: errorMessage(_error!), onRetry: _run);
    if (_mode == _Mode.quick) {
      if (_results.isEmpty) {
        return EmptyState(
          icon: Icons.search,
          message: _controller.text.trim().length < 2 ? 'Aramak için yazmaya başla.' : 'Sonuç bulunamadı.',
        );
      }
      return ListView.builder(
        itemCount: _results.length,
        itemBuilder: (_, i) => TrackTile(tracks: _results, index: i),
      );
    }
    final result = _assistant;
    if (result == null) {
      return const EmptyState(
        icon: Icons.auto_awesome,
        message: 'Adını hatırlamadığın şarkıyı ya da podcasti anlat; asistan senin için bulsun.',
      );
    }
    final tracks = result.matches.map((m) => m.track).toList();
    return ListView(children: [
      Card(
        margin: const EdgeInsets.all(16),
        child: ListTile(
          leading: Icon(result.aiUsed ? Icons.auto_awesome : Icons.info_outline),
          title: Text(result.message.isEmpty ? 'Sonuçlar' : result.message),
        ),
      ),
      for (var i = 0; i < tracks.length; i++)
        TrackTile(
          tracks: tracks,
          index: i,
          subtitle: result.matches[i].reason == null
              ? null
              : '${tracks[i].artist} — ${result.matches[i].reason}',
        ),
    ]);
  }
}
