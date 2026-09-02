import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:palette_generator/palette_generator.dart';
import '../services/audio_handler.dart';
import '../widgets/glass_panel.dart';
import '../widgets/waveform_progress.dart';
import '../widgets/visualizer_widget.dart';
import '../utils/theme_manager.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  AudioPlayerHandler? _handler;
  bool _isLoading = true;
  bool _hasPermission = false;
  List<SongModel> _songs = [];
  PaletteGenerator? _palette;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    final audioStatus = await Permission.audio.request();
    final storageStatus = await Permission.storage.request();

    if (audioStatus.isGranted || storageStatus.isGranted) {
      setState(() => _hasPermission = true);
      await _initAudioService();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _initAudioService() async {
    _handler = AudioService.current as AudioPlayerHandler?;
    
    if (_handler == null) {
      _handler = await AudioService.getHandler() as AudioPlayerHandler?;
    }

    if (_handler != null) {
      await _handler!.customAction('loadSongs');
      
      _handler!.songsStream.listen((songs) {
        if(mounted) setState(() {
          _songs = songs;
          _isLoading = false;
        });
      });

      _handler!.currentIndexStream.listen((index) {
        if(mounted) setState(() {
          _currentIndex = index;
          if (index >= 0 && index < _songs.length) {
            _extractAlbumColor(_songs[index]);
          }
        });
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _extractAlbumColor(SongModel song) async {
    try {
      final artwork = await OnAudioQuery().queryArtwork(song.id, ArtworkType.AUDIO);
      if (artwork != null) {
        final provider = Image.memory(artwork).image;
        final palette = await PaletteGenerator.fromImageProvider(provider);
        if (mounted) {
          setState(() {
            _palette = palette;
          });
        }
      }
    } catch (e) {
      // Игнорируем ошибки извлечения цвета
    }
  }

  Color get _dominantColor => _palette?.dominantColor?.color ?? Colors.purple;
  Color get _vibrantColor => _palette?.vibrantColor?.color ?? Colors.pink;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.black : Colors.white;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Музыка', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
      actions: [
        IconButton(icon: const Icon(Icons.palette), onPressed: () => ThemeManager.toggleTheme()),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (!_hasPermission) return Center(child: ElevatedButton(onPressed: _checkPermissionAndLoad, child: const Text('Разрешить')));
    if (_songs.isEmpty) return const Center(child: Text('Нет песен'));

    return Column(
      children: [
        Expanded(flex: 2, child: _buildPlayerView()),
        Expanded(flex: 3, child: _buildSongList()),
      ],
    );
  }

  Widget _buildPlayerView() {
    final isPlaying = _handler?.playbackState.value.playing ?? false;
    final position = _handler?.playbackState.value.position ?? Duration.zero;
    final duration = _handler?.playbackState.value.duration ?? Duration.zero;
    final progress = duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0.0;

    return StreamBuilder<MediaItem?>(
      stream: _handler?.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(colors: [_dominantColor.withOpacity(0.3), _vibrantColor.withOpacity(0.1), Colors.transparent]),
          ),
          child: GlassPanel(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(mediaItem?.title ?? 'Не выбрано', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1),
                  Text(mediaItem?.artist ?? '---', style: TextStyle(fontSize: 14, color: Colors.grey[400]), maxLines: 1),
                  const SizedBox(height: 8),
                  WaveformProgress(progress: progress, color: _vibrantColor, height: 20),
                  const SizedBox(height: 4),
                  VisualizerWidget(isPlaying: isPlaying, color: _vibrantColor),
                  const SizedBox(height: 12),
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
        IconButton(icon: const Icon(Icons.skip_previous, size: 32), onPressed: () => _handler?.rewind()),
        GestureDetector(
          onTap: () => isPlaying ? _handler?.pause() : _handler?.play(),
          child: Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [_dominantColor, _vibrantColor]), shape: BoxShape.circle),
            padding: const EdgeInsets.all(16),
            child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ),
        IconButton(icon: const Icon(Icons.skip_next, size: 32), onPressed: () => _handler?.fastForward()),
      ],
    );
  }

  Widget _buildSongList() {
    return ListView.builder(
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        final isCurrent = index == _currentIndex;
        return Card(
          color: isCurrent ? _dominantColor.withOpacity(0.2) : null,
          child: ListTile(
            title: Text(song.title, style: TextStyle(color: isCurrent ? _vibrantColor : null)),
            onTap: () => _handler?.customAction('playAtIndex', {'index': index}),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

