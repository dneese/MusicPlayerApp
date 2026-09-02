import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists a set of favorited song identifiers via shared_preferences.
class FavoritesRepository {
  static const String _key = 'favorites_v1';

  Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = (jsonDecode(raw) as List<dynamic>).cast<String>();
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Set<String> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(favorites.toList()));
  }
}