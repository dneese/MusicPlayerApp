import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'repository/library_repository.dart';
import 'repository/playlist_repository.dart';

void main() {
  runApp(const MaterialApp(home: MusicPlayer()));
}

class MusicPlayer extends StatefulWidget {
  const MusicPlayer({super.key});
  @override
  State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> {
  final LibraryRepository _libraryRepository = LibraryRepository();
  final PlaylistRepository _playlistRepository = PlaylistRepository();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<SongModel> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
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
      final songs = await _libraryRepository.getSongs();
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Modern Music Player")),
      body: _loading 
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _songs.length,
              itemBuilder: (context, i) {
                return ListTile(
                  title: Text(_songs[i].title),
                  subtitle: Text(_songs[i].artist ?? "Unknown"),
                  onTap: () async {
                    await _audioPlayer.setFilePath(_songs[i].data);
                    _audioPlayer.play();
                  },
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
