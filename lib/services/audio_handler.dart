import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:rxdart/rxdart.dart';

enum RepeatMode { off, all, one }

/// A self-contained playback controller built directly on just_audio.
///
/// Deliberately does NOT extend audio_service's BaseAudioHandler: that class
/// requires AudioService.init() to have completed, and if the background
/// service fails to start it throws LateInitializationError on every control
/// call. A plain just_audio player always works in-process, which is what
/// actually gets music to play.
class AudioPlayerHandler {
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
  final BehaviorSubject<SongModel?> _currentSongController = BehaviorSubject.seeded(null);

  /// Surfaces playback errors to the UI for a helpful message instead of a
  /// silent dead tap.
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);

  Stream<RepeatMode> get repeatStream => _repeatController.stream;
  Stream<bool> get shuffleStream => _shuffleController.stream;
  Stream<List<SongModel>> get songsStream => _songsController.stream;
  Stream<int> get currentIndexStream => _currentIndexController.stream;
  Stream<SongModel?> get currentSongStream => _currentSongController.stream;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  bool get isPlaying => _player.playing;

  AudioPlayerHandler() {
    instance = this;
    handlerNotifier.value = this;
    _listen();
  }

  void _listen() {
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

  Future<void> _playAt(int index) async {
    if (_songs.isEmpty) {
      errorNotifier.value = 'Библиотека ещё не загружена';
      return;
    }
    if (index < 0 || index >= _songs.length) {
      errorNotifier.value = 'Трек не найден';
      return;
    }

    final prevIndex = _currentIndex;
    _currentIndex = index;
    _currentIndexController.add(index);

    final song = _songs[index];
    try {
      await _player.setFilePath(song.data);
      _currentSongController.add(song);
      _player.play();
      errorNotifier.value = null;
    } catch (e) {
      _currentIndex = prevIndex;
      errorNotifier.value = 'Не удалось воспроизвести «${song.title}» ($e)';
    }
  }

  void _onTrackComplete() {
    if (_repeat == RepeatMode.one && _currentIndex >= 0) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    final next = _computeNext();
    if (next == null) {
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
    if (index < 0 || index >= _songs.length) {
      errorNotifier.value = 'Трек не найден';
      return;
    }
    await playBySong(_songs[index]);
  }

  /// Plays the given song, resolving it against the handler's loaded library
  /// by file path. This keeps the index/order independent of any UI-side
  /// sorting/filtering.
  Future<void> playBySong(SongModel target) async {
    if (_songs.isEmpty) {
      errorNotifier.value = 'Библиотека ещё не загружена';
      return;
    }
    final resolved = _songs.indexWhere(
        (s) => s.data == target.data || s.id == target.id);
    if (resolved < 0) {
      errorNotifier.value = 'Трек не найден в библиотеке';
      return;
    }
    if (_shuffle) {
      _shuffleCursor = _shuffleOrder.indexOf(resolved);
    }
    await _playAt(resolved);
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> stop() => _player.stop();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> skipToNext() async {
    final next = _computeNext();
    if (next != null) await _playAt(next);
  }

  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final prev = _computePrev();
    if (prev != null) await _playAt(prev);
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
  bool get shuffleEnabled => _shuffle;

  Future<void> dispose() async {
    await _player.dispose();
  }
}

final ValueNotifier<AudioPlayerHandler?> handlerNotifier =
    ValueNotifier<AudioPlayerHandler?>(null);