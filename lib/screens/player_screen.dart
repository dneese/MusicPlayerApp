import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/playlist.dart';
import '../repository/playlist_repository.dart';
import '../services/audio_handler.dart';

enum SortBy { title, artist, album, genre, duration, dateAdded }

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final PlaylistRepository _playlistRepo = PlaylistRepository();

  List<SongModel> _allSongs = [];
  List<SongModel> _songs = [];
  List<Playlist> _playlists = [];
  bool _isLoading = true;
  bool _permissionDenied = false;
  String? _loadError;
  int _navIndex = 0;
  int _sortIndex = 0;
  bool _showSort = false;
  AudioPlayerHandler? _handler;

  static const List<SortBy> _sortOptions = [
    SortBy.title, SortBy.artist, SortBy.album, SortBy.genre, SortBy.duration, SortBy.dateAdded,
  ];

  StreamSubscription<AudioPlayerHandler?>? _handlerSub;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _loadPlaylists();
    _handler = handlerNotifier.value;
    _handlerSub = handlerNotifier.listen((h) {
      if (mounted && h != null && _handler != h) {
        setState(() => _handler = h);
      }
    });
  }

  @override
  void dispose() {
    _handlerSub?.cancel();
    super.dispose();
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
          .timeout(const Duration(seconds: 10));
      if (!hasPermission) {
        if (mounted) setState(() {
          _isLoading = false;
          _permissionDenied = true;
        });
        return;
      }

      final songs = await _audioQuery.querySongs().timeout(const Duration(seconds: 20));
      final result = songs.isNotEmpty ? songs : await _scanFileSystem();

      _allSongs = result;
      _applySort();
      _handler?.setSongs(result);
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить библиотеку';
      });
    }
  }

  void _applySort() {
    final sorted = List<SongModel>.from(_allSongs);
    switch (_sortOptions[_sortIndex]) {
      case SortBy.title:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SortBy.artist:
        sorted.sort((a, b) => (a.artist ?? '')
            .toLowerCase()
            .compareTo((b.artist ?? '').toLowerCase()));
        break;
      case SortBy.album:
        sorted.sort((a, b) => (a.album ?? '')
            .toLowerCase()
            .compareTo((b.album ?? '').toLowerCase()));
        break;
      case SortBy.genre:
        sorted.sort((a, b) => (a.genre ?? '').toLowerCase().compareTo((b.genre ?? '').toLowerCase()));
        break;
      case SortBy.duration:
        sorted.sort((a, b) => (a.duration ?? 0).compareTo(b.duration ?? 0));
        break;
      case SortBy.dateAdded:
        sorted.sort((a, b) => (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0));
        break;
    }
    setState(() => _songs = sorted);
  }

  Future<void> _loadPlaylists() async {
    final playlists = await _playlistRepo.load();
    if (mounted) setState(() => _playlists = playlists);
  }

  // ---------- Playback via handler ----------

  Future<void> _play(SongModel song) async {
    final h = handlerNotifier.value;
    if (h == null) {
      _showSnackBase('Плеер ещё запускается, попробуйте через секунду');
      return;
    }
    h.playSong(_songs.indexOf(song));
    if (_navIndex != 0) setState(() => _navIndex = 0);
  }

  // ---------- Playlists ----------

  Future<void> _createPlaylist() async {
    final name = await _promptText('Новый плейлист', 'Название');
    if (name == null || name.trim().isEmpty) return;
    setState(() {
      _playlists.add(Playlist(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name.trim()));
    });
    await _playlistRepo.save(_playlists);
  }

  Future<void> _renamePlaylist(Playlist p) async {
    final name = await _promptText('Переименовать', 'Название', initial: p.name);
    if (name == null || name.trim().isEmpty) return;
    setState(() => p.name = name.trim());
    await _playlistRepo.save(_playlists);
  }

  Future<void> _deletePlaylist(Playlist p) async {
    setState(() => _playlists.removeWhere((x) => x.id == p.id));
    await _playlistRepo.save(_playlists);
  }

  Future<void> _addToPlaylist(SongModel song) async {
    if (_playlists.isEmpty) {
      _showSnackBase('Сначала создайте плейлист');
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
      _showSnackBase('Уже в плейлисте');
      return;
    }
    setState(() => p.songPaths.add(song.data));
    await _playlistRepo.save(_playlists);
    _showSnackBase('Добавлено в «${p.name}»');
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

  void _showSnackBase(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
          if (_songs.isNotEmpty) _buildMiniBar(),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withOpacity(0.28),
            scheme.primaryContainer.withOpacity(0.18),
            scheme.surface,
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _navChip(0, Icons.library_music, 'Песни'),
          const SizedBox(width: 8),
          _navChip(1, Icons.queue_music, 'Плейлисты'),
          const Spacer(),
          IconButton(
            tooltip: 'Сортировка',
            icon: const Icon(Icons.sort_by_alpha),
            onPressed: _showSortDialog,
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _loadLibrary,
          ),
        ],
      ),
    );
  }

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: List.generate(_sortOptions.length, (i) {
            return RadioListTile<int>(
              value: i,
              groupValue: _sortIndex,
              title: Text(_sortLabel(_sortOptions[i])),
              onChanged: (v) {
                Navigator.pop(ctx);
                if (v != null) {
                  setState(() => _sortIndex = v);
                  _applySort();
                }
              },
            );
          }),
        ),
      ),
    );
  }

  String _sortLabel(SortBy s) => switch (s) {
        SortBy.title => 'По названию',
        SortBy.artist => 'По исполнителю',
        SortBy.album => 'По альбому',
        SortBy.genre => 'По жанру',
        SortBy.duration => 'По длительности',
        SortBy.dateAdded => 'По дате добавления',
      };

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
    if (_permissionDenied) {
      return _CenterAction(
        icon: Icons.lock,
        text: 'Нет доступа к музыкальной библиотеке',
        button: 'Разрешить доступ',
        onTap: () => _loadLibrary(retry: true),
      );
    }
    if (_loadError != null) {
      return _CenterAction(
        icon: Icons.error_outline,
        text: _loadError!,
        button: 'Повторить',
        onTap: () => _loadLibrary(retry: true),
      );
    }
    return _navIndex == 0 ? _buildSongsView() : _buildPlaylistsView();
  }

  Widget _buildSongsView() {
    if (_songs.isEmpty) {
      return const Center(child: Text('Нет песен на устройстве'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
      itemCount: _songs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final song = _songs[index];
        return _SongTile(
          song: song,
          artwork: _artwork(song.id),
          onTap: () => _play(song),
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
      artworkWidth: 52,
      artworkHeight: 52,
      artworkBorder: BorderRadius.circular(10),
      nullArtworkWidget: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildPlaylistsView() {
    final empty = _playlists.isEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('Мои плейлисты', style: Theme.of(context).textTheme.titleMedium),
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
                  padding: const EdgeInsets.only(bottom: 96),
                  children: _playlists.map((p) {
                    final count = _allSongs.where((s) => p.songPaths.contains(s.data)).length;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(Icons.queue_music, color: Theme.of(context).colorScheme.primary),
                      ),
                      title: Text(p.name),
                      subtitle: Text('$count треков'),
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
    final songs = _allSongs.where((s) => p.songPaths.contains(s.data)).toList();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistScreen(
        playlist: p,
        songs: songs,
        onPlay: (i) {
          final song = songs[i];
          final realIndex = _allSongs.indexOf(song);
          if (realIndex >= 0) _play(song);
        },
        onRemove: (songPath) {
          setState(() => p.songPaths.remove(songPath));
          _playlistRepo.save(_playlists);
        },
      ),
    ));
  }

  // ---------- Mini-bar ----------

  Widget _buildMiniBar() {
    final h = handlerNotifier.value;
    if (h == null) return const SizedBox.shrink();
    return StreamBuilder<MediaItem?>(
      stream: h.mediaItem,
      builder: (context, mediaSnap) {
        final media = mediaSnap.data;
        final song = media != null
            ? _allSongs.where((s) => s.title == media.title).firstOrNull
            : null;
        final id = song?.id ?? -1;
        return StreamBuilder<bool>(
          stream: h.playingStream,
          builder: (context, playSnap) {
            final playing = playSnap.data ?? false;
            final title = media?.title;
            final artist = media?.artist;
            return _MiniBar(
              title: song?.title ?? title ?? 'Выберите трек',
              artist: song?.artist ?? artist ?? '',
              playing: playing,
              artwork: id >= 0 ? _artwork(id) : null,
              onPlayPause: () => playing ? h.pause() : h.play(),
              onNext: h.skipToNext,
              onPrev: h.skipToPrevious,
              onExpand: () => _openNowPlaying(h, id),
            );
          },
        );
      },
    );
  }

  void _openNowPlaying(AudioPlayerHandler h, int artworkId) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => _NowPlayingPage(
          handler: h,
          audioQuery: _audioQuery,
          songs: _songs,
          artworkId: artworkId,
          artwork: (bgColor) => QueryArtworkWidget(
            controller: _audioQuery,
            id: artworkId,
            type: ArtworkType.AUDIO,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: const Icon(Icons.music_note, size: 120, color: Colors.grey),
            ),
            artworkWidth: 320,
            artworkHeight: 320,
            artworkBorder: BorderRadius.circular(24),
            nullArtworkWidget: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [bgColor, bgColor.withOpacity(0.6)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.music_note, size: 120),
            ),
          ),
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ---------- Filesystem fallback ----------

  Future<List<SongModel>> _scanFileSystem() async {
    final found = <SongModel>[];
    final seen = <String>{};
    const roots = [
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
        if (!_scannedExtensions.contains(ext)) continue;
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

  static const Set<String> _scannedExtensions = {
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma', 'amr', 'mid',
  };
}

class _SongTile extends StatelessWidget {
  final SongModel song;
  final Widget artwork;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _SongTile({
    required this.song,
    required this.artwork,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Stack(
        alignment: Alignment.center,
        children: [artwork],
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [song.artist, song.album].where((s) => s != null && s.isNotEmpty).join(' · '),
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

class _CenterAction extends StatelessWidget {
  final IconData icon;
  final String text;
  final String button;
  final VoidCallback onTap;

  const _CenterAction({
    required this.icon,
    required this.text,
    required this.button,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
}

class _MiniBar extends StatelessWidget {
  final String title;
  final String artist;
  final bool playing;
  final Widget? artwork;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onExpand;

  const _MiniBar({
    required this.title,
    required this.artist,
    required this.playing,
    required this.artwork,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 8,
      child: GestureDetector(
        onTap: onExpand,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              if (artwork != null) artwork ?? const SizedBox.shrink(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        )),
                    if (artist.isNotEmpty)
                      Text(artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onInverseSurface.withOpacity(0.7),
                            fontSize: 12,
                          )),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                color: Theme.of(context).colorScheme.onInverseSurface,
                onPressed: onPlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded),
                color: Theme.of(context).colorScheme.onInverseSurface,
                onPressed: onNext,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                color: Theme.of(context).colorScheme.onInverseSurface,
                onPressed: onExpand,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingPage extends StatefulWidget {
  final AudioPlayerHandler handler;
  final OnAudioQuery audioQuery;
  final List<SongModel> songs;
  final int artworkId;
  final Widget Function(Color bgColor) artwork;

  const _NowPlayingPage({
    required this.handler,
    required this.audioQuery,
    required this.songs,
    required this.artworkId,
    required this.artwork,
  });

  @override
  State<_NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<_NowPlayingPage> {
  Color _bg = Colors.deepPurple;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.handler.isPlaying;
    widget.handler.playingStream.listen((p) {
      if (mounted) setState(() => _isPlaying = p);
    });
    _loadBackgroundColor();
  }

  Future<void> _loadBackgroundColor() async {
    try {
      final bytes = await widget.audioQuery.queryArtwork(
        widget.artworkId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 200,
      );
      if (bytes == null || bytes.isEmpty) return;
      final decoded = await decodeImageFromList(bytes);
      final palette = await PaletteGenerator.fromImage(decoded, maximumColorCount: 8);
      decoded.dispose();
      final color = palette.dominantColor?.color;
      if (color != null && mounted) setState(() => _bg = color);
    } catch (_) {}
  }

  void _openQueue() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Text('Очередь',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<int>(
                    stream: widget.handler.currentIndexStream,
                    builder: (context, idxSnap) {
                      final current = idxSnap.data ?? -1;
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: widget.songs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final song = widget.songs[i];
                          final isCurrent = i == current;
                          return ListTile(
                            selected: isCurrent,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.12),
                            leading: QueryArtworkWidget(
                              controller: widget.audioQuery,
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              artworkWidth: 40,
                              artworkHeight: 40,
                              artworkBorder: BorderRadius.circular(8),
                              errorBuilder: (_, __, ___) => Icon(
                                  Icons.music_note,
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            title: Text(song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight:
                                      isCurrent ? FontWeight.w700 : FontWeight.w500,
                                  color: isCurrent
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                )),
                            subtitle: Text(song.artist ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: isCurrent
                                ? Icon(Icons.graphic_eq,
                                    color: Theme.of(context).colorScheme.primary)
                                : const Icon(Icons.play_arrow),
                            onTap: () {
                              widget.handler.playSong(i);
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: widget.handler.mediaItem,
      builder: (context, mediaSnap) {
        final media = mediaSnap.data;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _bgLayer(),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          const Text('Сейчас играет', style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Очередь',
                            icon: const Icon(Icons.queue_music),
                            onPressed: _openQueue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      widget.artwork(_bg),
                      const SizedBox(height: 28),
                      Text(media?.title ?? 'Нет трека',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(media?.artist ?? '',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.75))),
                      const SizedBox(height: 24),
                      _SeekBar(handler: widget.handler),
                      const SizedBox(height: 12),
                      _TransportControls(handler: widget.handler, playing: _isPlaying),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bgLayer() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(_bg, Colors.black, 0.35)!,
            Color.lerp(_bg, Colors.black, 0.6)!,
          ],
        ),
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  final AudioPlayerHandler handler;

  const _SeekBar({required this.handler});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double _value = 0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.handler.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
          _value = _duration.inMilliseconds > 0 ? pos.inMilliseconds / _duration.inMilliseconds : 0;
        });
      }
    });
    widget.handler.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(1, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Slider(
          value: _value.clamp(0.0, 1.0),
          onChangeEnd: (v) => widget.handler.seek(Duration(milliseconds: (v * _duration.inMilliseconds).round())),
          activeColor: Colors.white,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_position), style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Text(_fmt(_duration), style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransportControls extends StatelessWidget {
  final AudioPlayerHandler handler;
  final bool playing;

  const _TransportControls({required this.handler, required this.playing});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RepeatMode>(
      stream: handler.repeatStream,
      builder: (context, repeatSnap) {
        final repeat = repeatSnap.data ?? RepeatMode.off;
        return StreamBuilder<bool>(
          stream: handler.shuffleStream,
          builder: (context, shufSnap) {
            final shuffle = shufSnap.data ?? false;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: shuffle ? 'Перемешать включено' : 'Перемешать',
                  icon: Icon(Icons.shuffle, color: shuffle ? const Color(0xFF90CAF9) : Colors.white70),
                  onPressed: handler.toggleShuffle,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, size: 40),
                  color: Colors.white,
                  onPressed: handler.skipToPrevious,
                ),
                IconButton(
                  iconSize: 72,
                  icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  color: Colors.white,
                  onPressed: () => playing ? handler.pause() : handler.play(),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, size: 40),
                  color: Colors.white,
                  onPressed: handler.skipToNext,
                ),
                IconButton(
                  tooltip: switch (repeat) {
                    RepeatMode.off => 'Повторять все, потом стоп',
                    RepeatMode.all => 'Повторять все',
                    RepeatMode.one => 'Повторять один',
                  },
                  icon: Icon(_repeatIcon(repeat),
                      color: repeat == RepeatMode.off ? Colors.white54 : const Color(0xFF90CAF9)),
                  onPressed: handler.toggleRepeat,
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _repeatIcon(RepeatMode r) => switch (r) {
        RepeatMode.off => Icons.repeat,
        RepeatMode.all => Icons.repeat,
        RepeatMode.one => Icons.repeat_one,
      };
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
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                return ListTile(
                  leading: CircleAvatar(child: Text((i + 1).toString())),
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