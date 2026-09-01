import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.musicplayer.channel.audio',
      androidNotificationChannelName: 'Music Player',
      androidNotificationOngoing: true,
    );
  } catch (e) {
    debugPrint('JustAudioBackground init failed: $e');
  }
  runApp(const MaterialApp(home: MusicPlayer()));
}

class MusicPlayer extends StatefulWidget {
  const MusicPlayer({super.key});
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
  }

  Future<void> _checkPermission() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Android 13+ needs audio, older needs storage
      Permission perm = Permission.audio;
      // fallback for older Android
      var status = await perm.status;
      if (!status.isGranted) {
        status = await perm.request();
        if (!status.isGranted) {
          // try storage as fallback
          var s2 = await Permission.storage.request();
          if (s2.isGranted) status = s2;
        }
      }
      setState(() => _hasPermission = status.isGranted);
      if (status.isGranted) {
        await _loadSongs();
      } else {
        setState(() => _error = 'Дозвіл відхилено. Надай доступ до музики в налаштуваннях.');
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
        setState(() => _error = 'Не знайдено MP3 файлів. Перевір чи є музика на телефоні.');
      }
    } catch (e) {
      setState(() => _error = 'Помилка читання: $e');
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
              : _songs.isEmpty
                  ? const Center(child: Text('Список порожній'))
                  : ListView.builder(
                      itemCount: _songs.length,
                      itemBuilder: (context, index) {
                        final s = _songs[index];
                        return ListTile(
                          leading: const Icon(Icons.music_note),
                          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.artist ?? "Невідомий артист"),
                          onTap: () async {
                            try {
                              await _audioPlayer.setAudioSource(
                                AudioSource.uri(
                                  Uri.parse(s.uri!),
                                  tag: MediaItem(
                                    id: s.id.toString(),
                                    title: s.title,
                                    artist: s.artist,
                                  ),
                                ),
                              );
                              _audioPlayer.play();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Грає: ${s.title}')));
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
                              }
                            }
                          },
                        );
                      },
                    ),
      floatingActionButton: _audioPlayer.playing
          ? FloatingActionButton(
              onPressed: () => _audioPlayer.pause(),
              child: const Icon(Icons.pause),
            )
          : null,
    );
  }
}
