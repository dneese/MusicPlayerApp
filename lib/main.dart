import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

// Тимчасово прибрали JustAudioBackground для діагностики чорного екрану

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    // Запитуємо дозволи для Android
    Map<Permission, PermissionStatus> statuses = await [
      Permission.audio,
      Permission.storage,
    ].request();

    if (statuses[Permission.audio]!.isGranted || statuses[Permission.storage]!.isGranted) {
      _loadData();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadData() async {
    try {
      final songs = await _audioQuery.querySongs();
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _play(String path) async {
    try {
      await _audioPlayer.setFilePath(path);
      _audioPlayer.play();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Music Player (Test)")),
      body: _loading 
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _songs.length,
              itemBuilder: (context, i) {
                return ListTile(
                  title: Text(_songs[i].title),
                  onTap: () => _play(_songs[i].data),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
