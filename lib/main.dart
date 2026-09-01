import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

// 1. AudioHandler - серце плеєра
class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();

  MyAudioHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  PlaybackState _transformEvent(PlaybackEvent event) => PlaybackState(
    controls: [MediaControl.skipToPrevious, MediaControl.play, MediaControl.pause, MediaControl.skipToNext],
    systemActions: {MediaAction.seek},
    processingState: const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState]!,
    playing: _player.playing,
    updatePosition: _player.position,
    bufferedPosition: _player.bufferedPosition,
    speed: _player.speed,
  );

  Future<void> setMediaItem(MediaItem item) async {
    mediaItem.add(item);
    await _player.setAudioSource(AudioSource.uri(Uri.parse(item.id)));
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> skipToNext() => _player.seekToNext();
  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(androidNotificationChannelId: 'com.example.musicplayer.channel', androidNotificationChannelName: 'Pro Music Player'),
  );
  runApp(MaterialApp(home: MusicPlayer(handler: audioHandler)));
}

class MusicPlayer extends StatefulWidget {
  final MyAudioHandler handler;
  const MusicPlayer({super.key, required this.handler});
  @override
  State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  List<SongModel> _songs = [];

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  void _requestPermission() async {
    if (await Permission.audio.request().isGranted) {
      final songs = await _audioQuery.querySongs();
      setState(() => _songs = songs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pro Player 2026")),
      body: ListView.builder(
        itemCount: _songs.length,
        itemBuilder: (context, i) {
          final s = _songs[i];
          return ListTile(
            leading: QueryArtworkWidget(id: s.id, type: ArtworkType.AUDIO, nullArtworkWidget: const Icon(Icons.music_note)),
            title: Text(s.title, maxLines: 1),
            subtitle: Text(s.artist ?? "Невідомий"),
            onTap: () => widget.handler.setMediaItem(MediaItem(id: s.data, title: s.title, artist: s.artist)),
          );
        },
      ),
      bottomNavigationBar: _buildMiniPlayer(),
    );
  }

  Widget _buildMiniPlayer() {
    return StreamBuilder<MediaItem?>(
      stream: widget.handler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();
        return Container(
          color: Colors.grey[900],
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(child: Text(item.title, style: const TextStyle(color: Colors.white))),
              IconButton(icon: const Icon(Icons.play_arrow, color: Colors.white), onPressed: widget.handler.play),
              IconButton(icon: const Icon(Icons.pause, color: Colors.white), onPressed: widget.handler.pause),
            ],
          ),
        );
      },
    );
  }
}
