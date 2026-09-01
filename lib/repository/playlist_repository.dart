import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/playlist.dart';

class PlaylistRepository {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'music_player.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE playlists(id INTEGER PRIMARY KEY, name TEXT)');
      },
    );
  }

  Future<void> addPlaylist(Playlist playlist) async {
    final db = await database;
    await db.insert('playlists', playlist.toMap());
  }

  Future<List<Playlist>> getPlaylists() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('playlists');
    return List.generate(maps.length, (i) => Playlist.fromMap(maps[i]));
  }
}
