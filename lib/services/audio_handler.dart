import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:rxdart/rxdart.dart';

enum RepeatMode { off, all, one }

class AudioPlayerHandler extends BaseAudioHandler {
  static AudioPlayerHandler? instance;
  final AudioPlayer _player = AudioPlayer();

  List<SongModel> _songs = [];
  int _currentIndex = -1;
  RepeatMode _repeat = RepeatMode.off;
  bool _shuffle = false;
  List<int> _shuffleOrder = [];
  int _shuffleCursor = -1;

  final BehaviorSubject<RepeatMode> _repeatController = BehaviorSubject.seeded(RepeatMode.off);
  final BehaviorSubject<bool> _shuffleController = BehaviorSubject.seeded(false);
  final BehaviorSubject<List<SongModel>> _songsController = BehaviorSubject.seeded(const <SongModel>[]);
  final BehaviorSubject<int> _currentIndexController = BehaviorSubject.seeded(-1);

  Stream<RepeatMode> get repeatStream => _repeatController.stream;
  Stream<bool> get shuffleStream => _shuffleController.stream;
  Stream<List<SongModel>> get songsStream => _songsController.stream;
  Stream<int> get currentIndexStream => _currentIndexController.stream;

  AudioPlayerHandler({List<SongModel>? songs}) {
    instance = this;
    handlerNotifier.value = this;
    if (songs != null) {
      _songs = songs;
      _songsController.add(_songs);
    }
    _listen();
  }

  void _listen() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onTrackComplete();
      }
    });
  }

  void setSongs(List<SongModel> songs) {
    _songs = songs;
    _songsController.add(songs);
    _resetShuffle();
  }

  void _resetShuffle() {
    _shuffleOrder = List.generate(_songs.length, (i) => i)..shuffle();
    _shuffleCursor = -1;
  }

  // -------- Queue logic --------

  int _resolveOrderIndex() {
    if (_shuffle) {
      if (_shuffleCursor >= 0) return _shuffleOrder[_shuffleCursor];
      return _songs.isEmpty ? -1 : _shuffleOrder.firstWhere((_) => true, orElse: () => -1);
    }
    return _currentIndex;
  }

  Future<void> _playAt(int index) async {
    if (_songs.isEmpty) return;
    if (index < 0 || index >= _songs.length) return;

    final prevIndex = _currentIndex;
    _currentIndex = index;
    _currentIndexController.add(index);

    final song = _songs[index];
    try {
      await _player.setFilePath(song.data);
      await _setCurrentMediaItem(song);
      _player.play();
    } catch (e) {
      _currentIndex = prevIndex;
    }
  }

  Future<void> _setCurrentMediaItem(SongModel song) async {
    mediaItem.add(MediaItem(
      id: _songs.indexOf(song).toString(),
      title: song.title,
      artist: song.artist ?? 'Неизвестный исполнитель',
      duration: song.duration != null
          ? Duration(milliseconds: song.duration!)
          : null,
    ));
  }

  void _onTrackComplete() {
    if (_repeat == RepeatMode.one && _currentIndex >= 0) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    final next = _computeNext();
    if (next == null) {
      // End of queue; stop unless repeat all.
      if (_repeat == RepeatMode.all) {
        _playAt(0);
      } else {
        _player.pause();
      }
      return;
    }
    _playAt(next);
  }

  int? _computeNext() {
    if (_songs.isEmpty) return null;
    if (_shuffle) {
      if (_shuffleCursor < _shuffleOrder.length - 1) {
        _shuffleCursor++;
        return _shuffleOrder[_shuffleCursor];
      }
      if (_repeat == RepeatMode.all) {
        _resetShuffle();
        _shuffleCursor = 0;
        return _shuffleOrder[0];
      }
      return null;
    }
    final next = _currentIndex + 1;
    if (next < _songs.length) return next;
    if (_repeat == RepeatMode.all) return 0;
    return null;
  }

  int? _computePrev() {
    if (_songs.isEmpty) return null;
    if (_shuffle) {
      if (_shuffleCursor > 0) {
        _shuffleCursor--;
        return _shuffleOrder[_shuffleCursor];
      }
      return null;
    }
    final prev = _currentIndex - 1;
    return prev >= 0 ? prev : null;
  }

  // -------- Public playback API --------

  Future<void> playSong(int index) async {
    if (_shuffle) {
      _shuffleCursor = _shuffleOrder.indexOf(index);
    }
    await _playAt(index);
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
  Future<void> skipToNext() async {
    final next = _computeNext();
    if (next != null) await _playAt(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final prev = _computePrev();
    if (prev != null) await _playAt(prev);
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final index = int.tryParse(mediaId);
    if (index != null) await playSong(index);
  }

  void toggleRepeat() {
    _repeat = RepeatMode.values[(_repeat.index + 1) % RepeatMode.values.length];
    _repeatController.add(_repeat);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle && _songs.isNotEmpty && _currentIndex >= 0) {
      _resetShuffle();
      _shuffleCursor = _shuffleOrder.indexOf(_currentIndex);
    }
    _shuffleController.add(_shuffle);
  }

  RepeatMode get repeatMode => _repeat;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  bool get isPlaying => _player.playing;

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
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'playAtIndex':
        if (extras != null && extras.containsKey('index')) {
          await playSong(extras['index'] as int);
        }
        break;
      case 'repeat':
        toggleRepeat();
        break;
      case 'shuffle':
        toggleShuffle();
        break;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await _player.dispose();
  }
}

final ValueNotifier<AudioPlayerHandler?> handlerNotifier =
    ValueNotifier<AudioPlayerHandler?>(null);