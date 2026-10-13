import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_models.dart';
import '../data/seed_articles.dart';

/// SharedPreferences (localStorage on web) backed article cache.
///
/// Keeps articles minimal: only the feed list is stored. When the API responds
/// successfully the cache is replaced entirely; when the server is down the
/// cache (or seed data) is served instead.
class LocalCache {
  LocalCache(this._prefs);

  static const _kArticles = 'cached_articles';
  static const _kSource = 'cache_source';

  final SharedPreferences _prefs;

  /// Whether the current cache comes from the real API (not seed data).
  bool get isFromServer => _prefs.getString(_kSource) == 'server';

  /// Load cached articles. Falls back to [seedArticles] when empty.
  List<Article> loadArticles() {
    final raw = _prefs.getStringList(_kArticles);
    if (raw == null || raw.isEmpty) return List.of(seedArticles);
    try {
      return raw
          .map((s) => Article.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return List.of(seedArticles);
    }
  }

  /// Replace the entire cache with fresh server data.
  Future<void> saveArticles(List<Article> articles) async {
    final encoded = articles.map((a) => jsonEncode(a.toJson())).toList();
    await _prefs.setStringList(_kArticles, encoded);
    await _prefs.setString(_kSource, 'server');
  }

  /// Clear cached articles so next load falls back to seed data.
  Future<void> clear() async {
    await _prefs.remove(_kArticles);
    await _prefs.remove(_kSource);
  }
}
