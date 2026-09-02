import 'dart:convert';

class Playlist {
  String id;
  String name;
  List<String> songPaths;

  Playlist({
    required this.id,
    required this.name,
    List<String>? songPaths,
  }) : songPaths = songPaths ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songPaths': songPaths,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        songPaths: (json['songPaths'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
      );

  String encodeList(List<Playlist> playlists) =>
      jsonEncode(playlists.map((p) => p.toJson()).toList());

  static List<Playlist> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
  }
}
