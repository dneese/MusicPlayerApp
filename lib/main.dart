import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
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
  String _status = "Запуск...";

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    setState(() => _status = "Запит дозволів...");
    if (await Permission.audio.request().isGranted || await Permission.storage.request().isGranted) {
      _loadData();
    } else {
      setState(() { _status = "Немає дозволу"; _loading = false; });
    }
  }

  Future<void> _loadData() async {
    setState(() => _status = "Сканування...");
    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      setState(() { _status = "Помилка: $e"; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Music Player (Stable)")),
      body: _loading 
          ? Center(child: Text(_status))
          : ListView.builder(
              itemCount: _songs.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(_songs[i].title),
                onTap: () async {
                  try {
                    await _audioPlayer.setFilePath(_songs[i].data);
                    _audioPlayer.play();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
                  }
                },
              ),
            ),
    );
  }
}
