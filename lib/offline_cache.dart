import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'bus_model.dart';

/// 키 하나에 JSON을 담아두는 범용 캐시.
///
/// 화면이 네트워크를 기다리며 스피너를 띄우는 대신, 지난번 값을 즉시 그리고
/// 뒤에서 조용히 갱신하기 위한 것이다. 공지·동아리가 이미 같은 방식을 쓰고
/// 있어서(NoticeCache/ClubEventCache) 식단·학사일정도 여기에 맞춘다.
class JsonCache {
  /// 저장하고, **내용이 실제로 달라졌는지**를 돌려준다.
  ///
  /// 호출부는 이 값이 true일 때만 revision을 올린다. 안 그러면
  /// revision → 화면 재로드 → 캐시 히트 → 백그라운드 갱신 → 저장 → revision
  /// 으로 무한히 도는 갱신 루프가 생긴다.
  static Future<bool> save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(value);
    final changed = prefs.getString(key) != encoded;
    await prefs.setString(key, encoded);
    await prefs.setInt('${key}_ts', DateTime.now().millisecondsSinceEpoch);
    return changed;
  }

  /// [maxAge]보다 오래된 값은 없는 것으로 친다.
  /// 오래됐더라도 "아무것도 없음"보다는 나으므로 기본값은 넉넉하게 잡는다.
  static Future<dynamic> load(String key, {required Duration maxAge}) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('${key}_ts');
    if (ts == null) return null;
    final age =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (age > maxAge) return null;
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}

/// Firestore가 지금 쓸 만한 상태인지 기억하는 회로 차단기.
///
/// 보안 규칙이 배포돼 있지 않으면 모든 읽기가 permission-denied로 끝나는데,
/// 그 응답이 오기까지 매번 몇 초씩 걸린다. 한 번 실패하면 잠시 건너뛰어
/// 화면이 헛되이 기다리지 않게 한다. 앱이 켜져 있는 동안만 유지한다.
class FirestoreHealth {
  static DateTime? _failedAt;
  static const Duration _cooldown = Duration(minutes: 5);

  static bool get isAvailable {
    final failed = _failedAt;
    if (failed == null) return true;
    if (DateTime.now().difference(failed) > _cooldown) {
      _failedAt = null; // 쿨다운이 지났으면 다시 시도해 본다.
      return true;
    }
    return false;
  }

  static void reportFailure() => _failedAt = DateTime.now();
  static void reportSuccess() => _failedAt = null;
}

/// 같은 대상에 대한 백그라운드 갱신이 너무 잦게 돌지 않도록 막는 문지기.
///
/// "캐시를 먼저 주고 갱신은 뒤에서" 방식은 화면이 갱신 완료를 구독하기 때문에,
/// 아무 제약이 없으면 갱신 → 재로드 → 또 갱신으로 계속 네트워크를 두드린다.
/// 앱이 켜져 있는 동안만 유지하면 충분하므로 메모리에만 둔다.
class RefreshThrottle {
  static final Map<String, DateTime> _last = {};

  /// 마지막 갱신 후 [minGap]이 지났으면 true를 주고 시각을 갱신한다.
  static bool shouldRefresh(
    String key, {
    Duration minGap = const Duration(minutes: 2),
  }) {
    final now = DateTime.now();
    final prev = _last[key];
    if (prev != null && now.difference(prev) < minGap) return false;
    _last[key] = now;
    return true;
  }

  /// 사용자가 직접 당겨서 새로고침할 때처럼, 제한을 무시해야 할 때.
  static void reset() => _last.clear();

  /// 첫 화면이 그려질 때까지 백그라운드 갱신을 미루는 시간.
  ///
  /// 갱신 자체는 await하지 않지만, 200KB짜리 공지·식단 HTML 파싱은 UI와 같은
  /// 스레드에서 돈다. 캐시로 즉시 그려놓고 곧바로 갱신을 시작하면 그 파싱이
  /// 첫 프레임을 밀어내 오히려 더 버벅인다. 화면이 자리를 잡은 뒤에 시작한다.
  static const Duration warmupDelay = Duration(seconds: 2);

  /// [shouldRefresh]를 통과했을 때, 첫 페인트 이후로 미뤄 실행한다.
  /// 백그라운드 갱신을 예약한다. 결과는 아무도 기다리지 않는다.
  ///
  /// 그래서 **여기서 반드시 오류를 삼켜야 한다.** [refresh]가 Future를
  /// 돌려주는데 그걸 버리면, 실패했을 때 처리되지 않은 비동기 오류가 되어
  /// 앱 밖으로 새어 나간다 — 캐시도 서버도 없는 첫 실행·오프라인이 딱 그렇다.
  /// 캐시를 못 채운 건 화면이 이미 다루므로 여기서는 조용히 넘긴다.
  static void deferred(String key, FutureOr<void> Function() refresh,
      {Duration minGap = const Duration(minutes: 2)}) {
    if (!shouldRefresh(key, minGap: minGap)) return;
    Future.delayed(warmupDelay, () async {
      try {
        await refresh();
      } catch (e) {
        debugPrint('배경 갱신 실패($key): $e');
      }
    });
  }
}

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
