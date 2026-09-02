import 'dart:io';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_service/audio_service.dart';
import '../services/audio_handler.dart';
import '../widgets/glass_panel.dart';
import '../widgets/visualizer_widget.dart';
import '../utils/theme_manager.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  AudioPlayerHandler? _handler;
  bool _isLoading = true;
  bool _permissionDenied = false;
  String? _loadError;
  List<SongModel> _songs = [];
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    handlerNotifier.addListener(_onHandlerChanged);
    _onHandlerChanged();
  }

  @override
  void dispose() {
    handlerNotifier.removeListener(_onHandlerChanged);
    super.dispose();
  }

  void _onHandlerChanged() {
    final handler = handlerNotifier.value;
    if (_handler == handler) return;
    _handler = handler;
    if (handler != null) {
      _listenToHandler(handler);
      _loadLibrary();
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _listenToHandler(AudioPlayerHandler handler) {
    handler.songsStream.listen((songs) {
      if (mounted) setState(() {
        _songs = songs;
        _isLoading = false;
      });
    });

    handler.currentIndexStream.listen((index) {
      if (mounted) setState(() {
        _currentIndex = index;
      });
    });
  }

  static const Duration _loadTimeout = Duration(seconds: 15);

  Future<void> _loadLibrary({bool retry = false}) async {
    if (mounted) setState(() {
      _isLoading = true;
      _permissionDenied = false;
      _loadError = null;
    });

    try {
      final hasPermission = await _audioQuery
          .checkAndRequest(retryRequest: retry)
          .timeout(_loadTimeout);
      if (!hasPermission) {
        if (mounted) setState(() {
          _isLoading = false;
          _permissionDenied = true;
        });
        return;
      }

      final songs = await _audioQuery.querySongs().timeout(_loadTimeout);

      final result = songs.isNotEmpty
          ? songs
          : await _scanFileSystem().timeout(const Duration(seconds: 45));

      _handler?.setSongs(result);
      if (mounted) setState(() {
        _songs = result;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  static const Set<String> _audioExtensions = {
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma', 'amr', 'mid',
  };

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Музыка'),
        actions: [
          IconButton(icon: const Icon(Icons.palette), onPressed: () => ThemeManager.toggleTheme()),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_permissionDenied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Нет доступа к музыкальной библиотеке'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadLibrary(retry: true),
              child: const Text('Разрешить доступ'),
            ),
          ],
        ),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить песни'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadLibrary(retry: true),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Нет песен'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadLibrary(retry: true),
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(flex: 2, child: _buildPlayerView()),
        Expanded(flex: 3, child: _buildSongList()),
      ],
    );
  }

  Widget _buildPlayerView() {
    final isPlaying = _handler?.playbackState.value.playing ?? false;
    
    return StreamBuilder<MediaItem?>(
      stream: _handler?.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        
        return Container(
          margin: const EdgeInsets.all(16),
          child: GlassPanel(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(mediaItem?.title ?? 'Не выбрано'),
                  VisualizerWidget(isPlaying: isPlaying, color: Colors.pink),
                  _buildControls(isPlaying),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls(bool isPlaying) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.skip_previous), onPressed: () => _handler?.skipToPrevious()),
        IconButton(icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow), 
                   onPressed: () => isPlaying ? _handler?.pause() : _handler?.play()),
        IconButton(icon: const Icon(Icons.skip_next), onPressed: () => _handler?.skipToNext()),
      ],
    );
  }

  Widget _buildSongList() {
    return ListView.builder(
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        return Card(
          child: ListTile(
            title: Text(song.title),
            onTap: () => _handler?.customAction('playAtIndex', {'index': index}),
          ),
        );
      },
    );
  }
}
