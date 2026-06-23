import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteService {
  static const _key = 'favoriteBuses';

  /// 즐겨찾기 상태를 실시간으로 구독할 수 있는 노티파이어
  static final ValueNotifier<Set<String>> favoritesNotifier = ValueNotifier({});

  static Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    favoritesNotifier.value = (prefs.getStringList(_key) ?? []).toSet();
  }

  static Future<Set<String>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).toSet();
  }

  static Future<void> add(String busNumber) async {
    final set = await _load();
    set.add(busNumber);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, set.toList());
    favoritesNotifier.value = Set.from(set);
  }

  static Future<void> remove(String busNumber) async {
    final set = await _load();
    set.remove(busNumber);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, set.toList());
    favoritesNotifier.value = Set.from(set);
  }

  static bool isFavoriteSync(String busNumber) {
    return favoritesNotifier.value.contains(busNumber);
  }

  static Future<bool> isFavorite(String busNumber) async {
    return favoritesNotifier.value.contains(busNumber);
  }

  static Future<Set<String>> getAll() async => favoritesNotifier.value;
}
