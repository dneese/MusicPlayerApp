import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:rxdart/rxdart.dart';

final ValueNotifier<AudioPlayerHandler?> handlerNotifier =
    ValueNotifier<AudioPlayerHandler?>(null);

class AudioPlayerHandler extends BaseAudioHandler {
  static AudioPlayerHandler? instance;

  final AudioPlayer _player = AudioPlayer();
  final OnAudioQuery _audioQuery = OnAudioQuery();

  List<SongModel> _songs = [];
  int _currentIndex = 0;

  final BehaviorSubject<List<SongModel>> _songsController = BehaviorSubject();
  Stream<List<SongModel>> get songsStream => _songsController.stream;
  final BehaviorSubject<int> _currentIndexController = BehaviorSubject();
  Stream<int> get currentIndexStream => _currentIndexController.stream;

  AudioPlayerHandler() {
    instance = this;
    handlerNotifier.value = this;
    _init();
    _listenToPlayerChanges();
  }

  Future<void> _init() async {
    await _loadSongs();
    if (_songs.isNotEmpty) {
      await _setCurrentMediaItem(_songs[0]);
    }
  }

  Future<void> _loadSongs() async {
    try {
      _songs = await _audioQuery.querySongs();
      _songsController.add(_songs);
    } catch (e) {
      print('Ошибка загрузки: $e');
    }
  }

  void _listenToPlayerChanges() {
    _player.playbackEventStream.listen(_broadcastState);

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _next();
      }
    });
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final index = int.tryParse(mediaId);
    if (index != null && index < _songs.length) {
      await _playAtIndex(index);
    }
  }

  Future<void> _playAtIndex(int index) async {
    if (index < 0 || index >= _songs.length) return;

    _currentIndex = index;
    _currentIndexController.add(index);

    final song = _songs[index];
    await _player.setFilePath(song.data);
    await _setCurrentMediaItem(song);
    await _player.play();
  }

  Future<void> _setCurrentMediaItem(SongModel song) async {
    final item = MediaItem(
      id: _songs.indexOf(song).toString(),
      title: song.title,
      artist: song.artist ?? 'Неизвестный исполнитель',
      duration: Duration(milliseconds: song.duration ?? 0),
    );
    mediaItem.add(item);
  }

  void _next() {
    if (_currentIndex < _songs.length - 1) {
      _playAtIndex(_currentIndex + 1);
    } else {
      _playAtIndex(0);
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      _playAtIndex(_currentIndex - 1);
    } else {
      _playAtIndex(_songs.length - 1);
    }
  }

  @override
  Future<void> skipToNext() async {
    _next();
  }

  @override
  Future<void> skipToPrevious() async {
    _previous();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'playAtIndex':
        if (extras != null && extras.containsKey('index')) {
          await _playAtIndex(extras['index'] as int);
        }
        break;
      case 'loadSongs':
        await _loadSongs();
        break;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await _player.dispose();
  }
}
