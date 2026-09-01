import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.musicplayer.channel.audio',
    androidNotificationChannelName: 'Music Player',
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
  List<PlaylistModel> _playlists = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    if (await Permission.audio.request().isGranted) {
      _loadData();
    } else {
      setState(() { _error = "Немає доступу до файлів"; _loading = false; });
    }
  }

  Future<void> _loadData() async {
    final songs = await _audioQuery.querySongs();
    final playlists = await _audioQuery.queryPlaylists();
    setState(() {
      _songs = songs;
      _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _play(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await _audioPlayer.setFilePath(path);
        _audioPlayer.play();
      } else {
        await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(path)));
        _audioPlayer.play();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Music Player"),
          bottom: const TabBar(tabs: [Tab(text: "Треки"), Tab(text: "Плейлисти")]),
        ),
        body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(
          children: [
            ListView.builder(
              itemCount: _songs.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(_songs[i].title),
                onTap: () => _play(_songs[i].data),
              ),
            ),
            ListView.builder(
              itemCount: _playlists.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(_playlists[i].playlist),
                onTap: () => _showPlaylistSongs(_playlists[i].id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistSongs(int id) async {
    final songs = await _audioQuery.queryAudiosFrom(AudiosFromType.PLAYLIST, id);
    Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(title: const Text("Плейлист")),
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(songs[i].title),
          onTap: () => _play(songs[i].data),
        ),
      ),
    )));
  }
}
