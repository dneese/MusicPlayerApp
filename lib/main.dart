import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool bgOk = true;
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.musicplayer.channel.audio',
      androidNotificationChannelName: 'Music Player',
      androidNotificationOngoing: true,
    );
  } catch (e) {
    debugPrint('JustAudioBackground init failed: $e');
    bgOk = false;
  }
  runApp(MaterialApp(home: MusicPlayer(bgOk: bgOk)));
}

class MusicPlayer extends StatefulWidget {
  final bool bgOk;
  const MusicPlayer({super.key, required this.bgOk});
  @override
  State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<SongModel> _songs = [];
  bool _hasPermission = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _audioPlayer.playerStateStream.listen((s) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _checkPermission() async {
    setState(() { _loading = true; _error = null; });
    try {
      var status = await Permission.audio.status;
      if (!status.isGranted) {
        status = await Permission.audio.request();
        if (!status.isGranted) {
          var s2 = await Permission.storage.request();
          if (s2.isGranted) status = s2;
        }
      }
      setState(() => _hasPermission = status.isGranted);
      if (status.isGranted) {
        await _loadSongs();
      } else {
        setState(() => _error = 'Дозвіл відхилено. Надай доступ до музики в налаштуваннях телефону.');
      }
    } catch (e) {
      setState(() => _error = 'Помилка дозволу: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _loadSongs() async {
    try {
      List<SongModel> songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      setState(() => _songs = songs);
      if (songs.isEmpty) {
        setState(() => _error = 'Не знайдено MP3 файлів. Перевір чи є музика в памʼяті телефону.');
      }
    } catch (e) {
      setState(() => _error = 'Помилка читання: $e');
    }
  }

  Future<void> _play(int index) async {
    final s = _songs[index];
    try {
      if (widget.bgOk) {
        // з фоновим сервісом + шторкою
        await _audioPlayer.setAudioSource(
          AudioSource.uri(
            Uri.parse(s.uri!),
            tag: MediaItem(
              id: s.id.toString(),
              title: s.title,
              artist: s.artist ?? 'Невідомий',
            ),
          ),
        );
      } else {
        // fallback без MediaItem якщо AudioService не ініціалізовано
        await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(s.uri!)));
      }
      await _audioPlayer.play();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('▶ ${s.title}')));
    } catch (e) {
      // пробуємо fallback без tag
      try {
        await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(s.uri!)));
        await _audioPlayer.play();
      } catch (e2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка програвання: $e2')));
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Мій Плеєр 🎵")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _songs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _checkPermission, child: const Text('Запросити знову')),
                        ElevatedButton(onPressed: openAppSettings, child: const Text('Відкрити налаштування')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: _songs.length,
                        itemBuilder: (context, index) {
                          final s = _songs[index];
                          return ListTile(
                            leading: const Icon(Icons.music_note),
                            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(s.artist ?? "Невідомий артист"),
                            onTap: () => _play(index),
                          );
                        },
                      ),
                    ),
                    if (_songs.isNotEmpty) _buildPlayerBar(),
                  ],
                ),
    );
  }

  Widget _buildPlayerBar() {
    return StreamBuilder<PlayerState>(
      stream: _audioPlayer.playerStateStream,
      builder: (context, snapshot) {
        final playing = _audioPlayer.playing;
        return Container(
          color: Theme.of(context).colorScheme.surfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 48),
                onPressed: () => playing ? _audioPlayer.pause() : _audioPlayer.play(),
              ),
              IconButton(icon: const Icon(Icons.stop), onPressed: () => _audioPlayer.stop()),
              const SizedBox(width: 8),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: _audioPlayer.positionStream,
                  builder: (context, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final dur = _audioPlayer.duration ?? Duration.zero;
                    return Column(
                      children: [
                        Slider(
                          min: 0,
                          max: dur.inMilliseconds.toDouble() + 1,
                          value: pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                          onChanged: (v) => _audioPlayer.seek(Duration(milliseconds: v.toInt())),
                        ),
                        Text('${_fmt(pos)} / ${_fmt(dur)}', style: const TextStyle(fontSize: 12)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
