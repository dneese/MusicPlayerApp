import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores read/write display overrides for track tags (title / artist / album)
/// keyed by file path. Embedded tag editing is limited under Android scoped
/// storage, so we persist display-level overrides used by the UI.
class TagsRepository {
  static const String _key = 'tag_overrides_v1';

  Future<Map<String, Map<String, String>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((path, v) => MapEntry(
          path,
          ((v as Map<String, dynamic>))
              .map((k, val) => MapEntry(k, val as String))));
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, Map<String, String>> overrides) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(overrides));
  }
}