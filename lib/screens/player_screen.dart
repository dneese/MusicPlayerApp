import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_service/audio_service.dart';
import 'package:palette_generator/palette_generator.dart';
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
  AudioPlayerHandler? _handler;
  bool _isLoading = true;
  List<SongModel> _songs = [];
  PaletteGenerator? _palette;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _initAudioService();
  }

  Future<void> _initAudioService() async {
    _handler = AudioPlayerHandler.instance;

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
    // Simplified for now
  }

  Color get _dominantColor => Colors.purple; // Simplified
  Color get _vibrantColor => Colors.pink; // Simplified

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
