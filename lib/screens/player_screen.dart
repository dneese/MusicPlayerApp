import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/playlist.dart';
import '../repository/playlist_repository.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();
  final PlaylistRepository _playlistRepo = PlaylistRepository();

  List<SongModel> _songs = [];
  List<Playlist> _playlists = [];
  bool _isLoading = true;
  bool _permissionDenied = false;
  String? _loadError;
  int _currentIndex = -1;
  bool _expanded = false;
  int _navIndex = 0; // 0 = Песни, 1 = Плейлисты
  Color _accent = Colors.deepPurple;

  StreamSubscription<PlayerState>? _playerStateSub;

  static const Set<String> _audioExtensions = {
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma', 'amr', 'mid',
  };
  static const Duration _permTimeout = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _initPlayer();
    _loadPlaylists();
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _initPlayer() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _next(auto: true);
      }
    });
  }

  Future<void> _loadLibrary({bool retry = false}) async {
    if (mounted) setState(() {
      _isLoading = true;
      _permissionDenied = false;
      _loadError = null;
    });

    try {
      final hasPermission = await _audioQuery
          .checkAndRequest(retryRequest: retry)
          .timeout(_permTimeout);
      if (!hasPermission) {
        if (mounted) setState(() {
          _isLoading = false;
          _permissionDenied = true;
        });
        return;
      }

      final songs = await _audioQuery.querySongs();
      final result = songs.isNotEmpty ? songs : await _scanFileSystem();

      if (mounted) setState(() {
        _songs = result;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить библиотеку';
      });
    }
  }

  Future<void> _loadPlaylists() async {
    final playlists = await _playlistRepo.load();
    if (mounted) setState(() => _playlists = playlists);
  }

  Future<void> _savePlaylists() async {
    await _playlistRepo.save(_playlists);
  }

  // ---------- Playback ----------

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    try {
      await _player.setFilePath(song.data);
    } catch (e) {
      _showSnack('Не удалось открыть файл: ${song.title}');
      return;
    }
    if (mounted) setState(() => _currentIndex = index);
    _loadAccent(song.id);
    _player.play();
  }

  Future<void> _loadAccent(int id) async {
    try {
      final bytes = await _audioQuery.queryArtwork(id, ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG, size: 200);
      if (bytes == null || bytes.isEmpty) return;
      final decoded = await decodeImageFromList(bytes);
      final palette = await PaletteGenerator.fromImage(decoded, maximumColorCount: 6);
      decoded.dispose();
      final color = palette.dominantColor?.color;
      if (color != null && mounted) {
        setState(() => _accent = color);
      }
    } catch (_) {}
  }

  void _next({bool auto = false}) {
    if (_songs.isEmpty) return;
    final next = _currentIndex + 1;
    _playAt(next >= _songs.length ? 0 : next);
  }

  void _previous() {
    if (_songs.isEmpty) return;
    final idx = _currentIndex <= 0 ? _songs.length - 1 : _currentIndex - 1;
    _playAt(idx);
  }

  Future<void> _togglePlay() async {
    if (_currentIndex < 0) {
      if (_songs.isNotEmpty) {
        await _playAt(0);
      }
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- Playlists ----------

  Future<void> _createPlaylist() async {
    final name = await _promptText('Новый плейлист', 'Название');
    if (name == null || name.trim().isEmpty) return;
    setState(() {
      _playlists.add(Playlist(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name.trim()));
    });
    await _savePlaylists();
  }

  Future<void> _renamePlaylist(Playlist p) async {
    final name = await _promptText('Переименовать плейлист', 'Название', initial: p.name);
    if (name == null || name.trim().isEmpty) return;
    setState(() => p.name = name.trim());
    await _savePlaylists();
  }

  Future<void> _deletePlaylist(Playlist p) async {
    setState(() => _playlists.removeWhere((x) => x.id == p.id));
    await _savePlaylists();
  }

  Future<void> _addToPlaylist(SongModel song) async {
    if (_playlists.isEmpty) {
      _showSnack('Сначала создайте плейлист');
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: _playlists
              .map((p) => ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(p.name),
                    onTap: () => Navigator.pop(ctx, p.id),
                  ))
              .toList(),
        ),
      ),
    );
    if (selected == null) return;
    final p = _playlists.firstWhere((x) => x.id == selected);
    if (p.songPaths.contains(song.data)) {
      _showSnack('Уже в плейлисте');
      return;
    }
    setState(() => p.songPaths.add(song.data));
    await _savePlaylists();
    _showSnack('Добавлено в «${p.name}»');
  }

  Future<String?> _promptText(String title, String label, {String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK')),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(child: _buildBody()),
                if (_songs.isNotEmpty) _buildMiniBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withOpacity(0.35),
            scheme.primaryContainer.withOpacity(0.25),
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          _navChip(0, Icons.library_music, 'Песни'),
          const SizedBox(width: 8),
          _navChip(1, Icons.queue_music, 'Плейлисты'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить библиотеку',
            onPressed: () => _loadLibrary(),
          ),
        ],
      ),
    );
  }

  Widget _navChip(int index, IconData icon, String label) {
    final selected = _navIndex == index;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (_) => setState(() => _navIndex = index),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_permissionDenied) return _statusView(
      icon: Icons.lock,
      text: 'Нет доступа к музыкальной библиотеке',
      button: 'Разрешить доступ',
      onTap: () => _loadLibrary(retry: true),
    );
    if (_loadError != null) return _statusView(
      icon: Icons.error_outline,
      text: _loadError!,
      button: 'Повторить',
      onTap: () => _loadLibrary(retry: true),
    );

    return _navIndex == 0 ? _buildSongsView() : _buildPlaylistsView();
  }

  Widget _statusView({
    required IconData icon,
    required String text,
    required String button,
    required VoidCallback onTap,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onTap, child: Text(button)),
        ],
      ),
    );
  }

  Widget _buildSongsView() {
    if (_songs.isEmpty) {
      return const Center(child: Text('Нет песен на устройстве'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        return _SongTile(
          song: song,
          isCurrent: index == _currentIndex,
          isPlaying: index == _currentIndex && _player.playing,
          artWidget: _artwork(song.id),
          onTap: () => _playAt(index),
          onAdd: () => _addToPlaylist(song),
        );
      },
    );
  }

  Widget _artwork(int id) {
    return QueryArtworkWidget(
      controller: _audioQuery,
      id: id,
      type: ArtworkType.AUDIO,
      errorBuilder: (_, __, ___) => Container(
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: const Icon(Icons.music_note, color: Colors.grey),
      ),
      artworkHeight: 48,
      artworkWidth: 48,
      artworkBorder: BorderRadius.circular(8),
      nullArtworkWidget: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.music_note,
            color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  // ---------- Playlists ----------

  Widget _buildPlaylistsView() {
    final empty = _playlists.isEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('Мои плейлисты',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _createPlaylist,
                icon: const Icon(Icons.add),
                label: const Text('Создать'),
              ),
            ],
          ),
        ),
        Expanded(
          child: empty
              ? const Center(child: Text('Нет плейлистов. Создайте первый!'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: _playlists.map((p) {
                    final songIds =
                        _songs.where((s) => p.songPaths.contains(s.data)).length;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(Icons.queue_music,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      title: Text(p.name),
                      subtitle: Text('$songIds треков'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'rename') _renamePlaylist(p);
                          if (v == 'delete') _deletePlaylist(p);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                          PopupMenuItem(value: 'delete', child: Text('Удалить')),
                        ],
                      ),
                      onTap: () => _openPlaylist(p),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  void _openPlaylist(Playlist p) {
    final songs = _songs.where((s) => p.songPaths.contains(s.data)).toList();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistScreen(
        playlist: p,
        songs: songs,
        onPlay: (i) => _playAt(_songs.indexOf(songs[i])),
        onRemove: (songPath) {
          setState(() => p.songPaths.remove(songPath));
          _savePlaylists();
        },
      ),
    ));
  }

  // ---------- Mini bar ----------

  Widget _buildMiniBar() {
    final current = _currentIndex >= 0 && _currentIndex < _songs.length
        ? _songs[_currentIndex]
        : null;
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final total = current?.duration != null && current!.duration! > 0
            ? Duration(milliseconds: current.duration!)
            : _player.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final progress = total.inMilliseconds > 0
            ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accent.withOpacity(0.95),
                  Color.lerp(_accent, Theme.of(context).colorScheme.surface, 0.35)!,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _expanded ? _buildExpandedPlayer(current) : _buildCollapsedPlayer(current, progress),
          ),
        );
      },
    );
  }

  Widget _buildCollapsedPlayer(SongModel? current, double progress) {
    final playing = _player.playing;
    return Row(
      children: [
        if (current != null)
          _artwork(current.id)
        else
          const SizedBox(width: 48, height: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                current?.title ?? 'Выберите трек',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
                backgroundColor: Colors.white24,
                color: Colors.white,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              iconSize: 34,
              color: Colors.white,
              onPressed: _togglePlay,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              color: Colors.white,
              onPressed: _next,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              color: Colors.white,
              onPressed: () => setState(() => _expanded = true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpandedPlayer(SongModel? current) {
    final playing = _player.playing;
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final total = current?.duration != null && current!.duration! > 0
            ? Duration(milliseconds: current.duration!)
            : _player.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(current?.title ?? 'Выберите трек',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(current?.artist ?? 'Неизвестный исполнитель',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.8))),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  onPressed: () => setState(() => _expanded = false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(
                value: total.inMilliseconds > 0
                    ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 5,
                backgroundColor: Colors.white24,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                Text(_fmt(total), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, size: 36),
                  color: Colors.white,
                  onPressed: _previous,
                ),
                IconButton(
                  icon: Icon(
                    playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 60,
                  ),
                  color: Colors.white,
                  onPressed: _togglePlay,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, size: 36),
                  color: Colors.white,
                  onPressed: _next,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(1, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ---------- Filesystem fallback ----------

  Future<List<SongModel>> _scanFileSystem() async {
    final found = <SongModel>[];
    final seen = <String>{};
    final roots = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Recordings',
      '/storage',
    ];

    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      _scanDir(dir, found, seen, 0);
    }
    return found;
  }

  void _scanDir(Directory dir, List<SongModel> found, Set<String> seen, int depth) {
    if (depth > 6) return;
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final child in children) {
      if (child is Directory) {
        _scanDir(child, found, seen, depth + 1);
      } else if (child is File) {
        final ext = child.path.split('.').last.toLowerCase();
        if (!_audioExtensions.contains(ext)) continue;
        if (!seen.add(child.path)) continue;
        final fileName = child.uri.pathSegments.isNotEmpty
            ? child.uri.pathSegments.last
            : child.path.split(Platform.pathSeparator).last;
        final title = fileName.contains('.')
            ? fileName.substring(0, fileName.lastIndexOf('.'))
            : fileName;
        found.add(SongModel({
          '_id': found.length,
          'title': title,
          'artist': 'Неизвестный исполнитель',
          'data': child.path,
          'duration': 0,
          '_display_name': fileName,
        }));
      }
    }
  }
}

class _SongTile extends StatelessWidget {
  final SongModel song;
  final bool isCurrent;
  final bool isPlaying;
  final Widget artWidget;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _SongTile({
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.artWidget,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Stack(
        alignment: Alignment.center,
        children: [
          artWidget,
          if (isPlaying)
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.graphic_eq, color: Colors.white, size: 20),
            ),
        ],
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          color: isCurrent ? scheme.primary : null,
        ),
      ),
      subtitle: Text(
        song.artist ?? 'Неизвестный исполнитель',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'add') onAdd();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'add', child: Text('Добавить в плейлист')),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _PlaylistScreen extends StatelessWidget {
  final Playlist playlist;
  final List<SongModel> songs;
  final void Function(int index) onPlay;
  final void Function(String songPath) onRemove;

  const _PlaylistScreen({
    required this.playlist,
    required this.songs,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: songs.isEmpty
          ? const Center(child: Text('Плейлист пуст'))
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text((i + 1).toString()),
                  ),
                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song.artist ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => onRemove(song.data),
                  ),
                  onTap: () => onPlay(i),
                );
              },
            ),
    );
  }
}
