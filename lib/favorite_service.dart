import 'package:shared_preferences/shared_preferences.dart';

class FavoriteService {
  static const _key = 'favoriteBuses';

  // add/remove의 읽기→수정→쓰기가 겹치면 먼저 끝난 쪽 변경이 유실될 수 있어
  // 하나의 Future 체인으로 직렬화한다.
  static Future<void> _mutex = Future.value();

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _mutex.then((_) => action());
    _mutex = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<Set<String>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).toSet();
  }

  static Future<void> add(String busNumber) {
    return _synchronized(() async {
      final set = await _load();
      set.add(busNumber);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, set.toList());
    });
  }

  static Future<void> remove(String busNumber) {
    return _synchronized(() async {
      final set = await _load();
      set.remove(busNumber);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, set.toList());
    });
  }

  static Future<bool> isFavorite(String busNumber) async {
    final set = await _load();
    return set.contains(busNumber);
  }

  static Future<Set<String>> getAll() async => await _load();
}
