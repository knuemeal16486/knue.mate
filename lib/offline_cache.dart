import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'bus_model.dart';

class OfflineCache {
  static const _key = 'busCache';

  static Future<void> save(List<BusSummary> summaries) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = summaries.map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
    await prefs.setInt('${_key}_ts', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<BusSummary>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('${_key}_ts');
    if (ts == null) return null;
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts))
        .inMinutes;
    if (diff > 5) return null; // 오래된 캐시 무시

    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final List<dynamic> list = jsonDecode(raw);
    return list.map((e) => BusSummary.fromJson(e)).toList();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove('${_key}_ts');
  }
}
