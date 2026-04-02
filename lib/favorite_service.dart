import 'package:shared_preferences/shared_preferences.dart';

class FavoriteService {
  static const _key = 'favoriteBuses';

  static Future<Set<String>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).toSet();
  }

  static Future<void> add(String busNumber) async {
    final set = await _load();
    set.add(busNumber);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, set.toList());
  }

  static Future<void> remove(String busNumber) async {
    final set = await _load();
    set.remove(busNumber);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, set.toList());
  }

  static Future<bool> isFavorite(String busNumber) async {
    final set = await _load();
    return set.contains(busNumber);
  }

  static Future<Set<String>> getAll() async => await _load();
}
