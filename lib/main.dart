import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.app.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
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

  @override
  void initState() {
    super.initState();
    requestPermission();
  }

  Future<void> requestPermission() async {
    var status = await Permission.audio.request();
    if (status.isGranted) {
      _loadSongs();
    }
  }

  Future<void> _loadSongs() async {
    List<SongModel> songs = await _audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    setState(() => _songs = songs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Мій Плеєр")),
      body: ListView.builder(
        itemCount: _songs.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(_songs[index].title),
          subtitle: Text(_songs[index].artist ?? "Невідомо"),
          onTap: () async {
            await _audioPlayer.setAudioSource(
              AudioSource.uri(
                Uri.parse(_songs[index].uri!),
                tag: MediaItem(
                  id: _songs[index].id.toString(),
                  title: _songs[index].title,
                  artist: _songs[index].artist,
                ),
              ),
            );
            _audioPlayer.play();
          },
        ),
      ),
    );
  }
}
