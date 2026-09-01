import 'package:on_audio_query/on_audio_query.dart';

class LibraryRepository {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<List<SongModel>> getSongs() async {
    return await _audioQuery.querySongs();
  }
}
