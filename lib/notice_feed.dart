import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notice_collector.dart';
import 'notice_model.dart';
import 'notice_service.dart';
import 'offline_cache.dart';

// ── 공지 수집 파일 받기 ────────────────────────────────────────────────
//
// 공지는 학교 서버가 아니라 중앙 수집기가 만든 파일(GitHub Pages)에서 받는다
// (lib/notice_collector.dart, .github/workflows/collect-notices.yml). 학교로
// 가는 요청이 이용자 수와 상관없어지고, 파일이 작아(목록 7KB + 바뀐 게시판만)
// 전체 게시판을 다 받아도 부담이 없다.
//
// 수집 파일이 오래돼도 **기기가 학교를 직접 긁지 않는다**(정보전산원 요청,
// 2026-10-02). 마지막 데이터를 보여 주고 늦어졌다고만 알린다. 수집기가 아예
// 멈췄을 때만 관리자가 `app_settings/notice_feed`의 `direct`를 켜서, 보고 있는
// 게시판만 학교에서 받던 예전 방식(KnueScraper)으로 돌린다.

/// 수집 파일 주소. `app_settings/notice_feed`의 `base`로 바꿀 수 있다
/// (호스팅을 옮겨도 앱을 다시 배포하지 않게).
const String kNoticeFeedBase = 'https://knuemeal16486.github.io/knue.mate/feed';

/// 게시판의 마지막 수집이 이보다 오래면 "늦어지고 있다"고 알린다.
/// 수집기는 30분마다 돈다.
const Duration kNoticeFeedStaleAfter = Duration(hours: 3);

/// 화면을 열거나 탭을 넘길 때의 자동 확인 간격. 학교가 아니라 GitHub Pages로
/// 가는 요청이라 짧게 잡는다(수집 주기 30분보다 훨씬 짧게). 당겨서 새로 고침은
/// 이 간격과 상관없이 매번 받는다.
const Duration kNoticeFeedAutoGap = Duration(minutes: 5);

/// 수집 파일을 받는 동시 요청 수.
const int _kFeedMaxConcurrent = 6;

/// `app_settings/notice_feed` 문서를 읽는다. 순수 함수 — 테스트 대상.
///
/// 문서가 없거나 값이 이상하면 기본값(수집 파일, 기본 주소)이다. 직접 모드는
/// 명시적으로 `true`일 때만 켠다 — 잘못된 값 하나로 모든 기기가 학교를
/// 두드리기 시작하면 안 된다.
({String base, bool direct}) parseNoticeFeedSettings(
  Map<String, dynamic>? data,
) {
  final base = data?['base'];
  final validBase = base is String && base.startsWith('https://');
  return (
    base: validBase ? base.replaceAll(RegExp(r'/+$'), '') : kNoticeFeedBase,
    direct: data?['direct'] == true,
  );
}

/// 이번에 다시 받을 게시판 파일. 순수 함수 — 테스트 대상.
///
/// 지문([FeedBoardEntry.hash])이 지난번과 같고 그 게시판 글이 캐시에 있으면
/// 받지 않는다. 앱이 모르는 게시판(수집기가 더 새 버전)과 아직 한 번도
/// 수집되지 않은 게시판은 건너뛴다.
List<FeedBoardEntry> feedBoardsToFetch({
  required List<FeedBoardEntry> boards,
  required Map<String, String> localHashes,
  required Set<(String, String)> cachedBoards,
  required Set<(String, String)> knownBoards,
}) => [
  for (final b in boards)
    if (knownBoards.contains((b.group, b.category)) &&
        b.fetchedAt != null &&
        b.count > 0 &&
        (localHashes[b.file] != b.hash ||
            !cachedBoards.contains((b.group, b.category))))
      b,
];

/// 백그라운드 알림이 볼 게시판. null이면 전체. 순수 함수 — 테스트 대상.
///
/// 수집 파일은 전체 게시판이 들어 있어 학교 부담과 상관이 없다. 그래서 키워드만
/// 등록한 사람은 다시 **모든 게시판**에서 찾는다(학교에서 직접 받을 땐 대표
/// 홈페이지 13개로 줄였었다 — [backgroundNoticeBoards]). 아무것도 설정하지
/// 않았으면 기본 4개만 — 48개 게시판의 새 글이 전부 알림으로 오면 안 된다.
Set<String>? feedAlertBoards(
  Iterable<String> favBoards,
  Iterable<String> keywords,
) {
  if (favBoards.isNotEmpty) return favBoards.toSet();
  if (keywords.isNotEmpty) return null;
  return kDefaultFavoriteBoards;
}

/// 보고 있는 게시판들의 수집 상태. 순수 함수 — 테스트 대상.
///
/// [oldest]: 그중 가장 오래된 마지막 수집 시각(화면 아래 "마지막 갱신").
/// [missing]: 수집 목록엔 있는데 한 번도 수집되지 않은 게시판.
({DateTime? oldest, Set<String> missing}) feedScopeStatus(
  List<FeedBoardEntry> boards,
  Set<String> categories,
) {
  DateTime? oldest;
  final missing = <String>{};
  for (final b in boards) {
    if (!categories.contains(b.category)) continue;
    final at = b.fetchedAt;
    if (at == null) {
      missing.add(b.category);
    } else if (oldest == null || at.isBefore(oldest)) {
      oldest = at;
    }
  }
  return (oldest: oldest, missing: missing);
}

/// 글 번호를 수집 파일과 같은 방식([stableNoticeId])으로 맞춘다. 순수 함수 — 테스트 대상.
///
/// 직접 받던 때의 글은 번호가 `Object.hash`라 실행마다 달라질 수 있고 수집
/// 파일 글과도 다르다. 알림이 "이미 알린 글"을 번호로 가리므로 하나로 맞춘다.
Notice withStableId(Notice n) {
  final id = stableNoticeId(n.group, n.category, n.link);
  if (n.id == id) return n;
  return Notice(
    id: id,
    category: n.category,
    group: n.group,
    title: n.title,
    date: n.date,
    author: n.author,
    link: n.link,
    isNew: n.isNew,
    isRead: n.isRead,
  );
}

/// 마지막 수집이 [kNoticeFeedStaleAfter]보다 오래됐는지. 순수 함수 — 테스트 대상.
bool isFeedStale(DateTime? oldest, DateTime now) =>
    oldest != null && now.difference(oldest) > kNoticeFeedStaleAfter;

/// 수집 파일 설정(주소·직접 모드). 앱이 켜질 때 한 번 Firestore에서 받아
/// 기기에도 적어 둔다. 백그라운드 작업은 기기에 적힌 값만 본다 — 백그라운드마다
/// Firestore를 읽으면 기기 수 × 하루 24번이 무료 읽기 한도를 먹는다.
class NoticeFeedSettings {
  static const _prefsKey = 'notice_feed_settings';

  static String base = kNoticeFeedBase;

  /// 비상 직접 모드. 켜져 있으면 보고 있는 게시판만 학교에서 직접 받는다.
  static bool direct = false;

  static bool _loaded = false;

  static Future<void> loadCached() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      _apply(raw == null ? null : jsonDecode(raw) as Map<String, dynamic>);
      _loaded = true;
    } catch (e) {
      debugPrint('NoticeFeedSettings: 캐시 읽기 실패: $e');
    }
  }

  static Future<void> refresh() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('notice_feed')
          .get();
      final data = snap.data();
      _apply(data);
      _loaded = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({'base': base, 'direct': direct}),
      );
    } catch (e) {
      debugPrint('NoticeFeedSettings: 갱신 실패: $e');
    }
  }

  /// 테스트에서 설정을 정해 둔다(기기 캐시를 읽지 않게).
  @visibleForTesting
  static void debugSet({bool direct = false, String base = kNoticeFeedBase}) {
    NoticeFeedSettings.direct = direct;
    NoticeFeedSettings.base = base;
    _loaded = true;
  }

  static void _apply(Map<String, dynamic>? data) {
    final s = parseNoticeFeedSettings(data);
    base = s.base;
    direct = s.direct;
  }
}

class NoticeFeed {
  static const _indexKey = 'notice_feed_index';
  static const _hashesKey = 'notice_feed_hashes';

  /// 마지막으로 받은 수집 목록(게시판별 마지막 수집 시각). 화면이 "늦어짐"
  /// 안내와 마지막 갱신 시각을 그리는 데 쓴다.
  static final ValueNotifier<List<FeedBoardEntry>> boards =
      ValueNotifier<List<FeedBoardEntry>>(const []);

  static bool _indexLoaded = false;
  static Future<bool>? _inFlight;

  /// 테스트마다 기기 저장소가 바뀌므로 메모리 상태를 비운다.
  @visibleForTesting
  static void debugReset() {
    _indexLoaded = false;
    _inFlight = null;
    boards.value = const [];
  }

  /// 기기에 적어 둔 수집 목록을 올린다(앱을 막 켰을 때 늦어짐 안내용).
  static Future<void> loadCachedIndex() async {
    if (_indexLoaded) return;
    _indexLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_indexKey);
      final index = raw == null ? null : parseFeedIndex(raw);
      if (index != null) boards.value = index.boards;
    } catch (_) {}
  }

  /// 공지를 새로 받는다. 받기에 성공했거나 받을 때가 아니었으면 true.
  ///
  /// 평소엔 수집 파일에서 받는다. 비상 직접 모드면 [directScope] 게시판만
  /// 학교에서 받는다(예전 방식, 게시판마다 30분 간격). [force]는 당겨서 새로
  /// 고침 — 간격과 상관없이 지금 받는다.
  static Future<bool> refresh({
    required Set<String> directScope,
    bool force = false,
  }) async {
    await NoticeFeedSettings.loadCached();
    if (NoticeFeedSettings.direct) {
      try {
        await KnueScraper().refreshBoards(
          directScope,
          gap: force ? Duration.zero : kNoticeAutoRefreshGap,
        );
        return true;
      } catch (e) {
        debugPrint('공지 직접 받기 실패: $e');
        return false;
      }
    }
    return sync(force: force);
  }

  /// 수집 파일을 받아 [NoticeCache]에 합친다. 동시에 여러 곳(홈·공지 화면)에서
  /// 불러도 한 번만 받는다.
  static Future<bool> sync({bool force = false}) =>
      _inFlight ??= _sync(force).whenComplete(() => _inFlight = null);

  static Future<bool> _sync(bool force) async {
    await loadCachedIndex();
    if (!await PersistentThrottle.tryAcquire(
      'notice_feed',
      'index',
      force ? Duration.zero : kNoticeFeedAutoGap,
    )) {
      return true;
    }
    final base = NoticeFeedSettings.base;
    try {
      final res = await http
          .get(Uri.parse('$base/index.json'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw 'index HTTP ${res.statusCode}';
      final body = utf8.decode(res.bodyBytes);
      final index = parseFeedIndex(body);
      if (index == null) throw 'index 형식을 읽을 수 없음';

      final prefs = await SharedPreferences.getInstance();
      final hashes = _loadHashes(prefs);
      final cached = await NoticeCache.load() ?? const <Notice>[];
      final known = {
        for (final g in kNoticeBoardGroups.entries)
          for (final b in g.value.entries)
            if (!b.value.startsWith('LINK:')) (g.key, b.key),
      };
      final todo = feedBoardsToFetch(
        boards: index.boards,
        localHashes: hashes,
        cachedBoards: {for (final n in cached) (n.group, n.category)},
        knownBoards: known,
      );

      final fresh = <(String, String), List<Notice>>{};
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      var next = 0;
      Future<void> worker() async {
        while (next < todo.length) {
          final b = todo[next++];
          try {
            final r = await http
                .get(Uri.parse('$base/${b.file}'))
                .timeout(const Duration(seconds: 10));
            if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
            final j = jsonDecode(utf8.decode(r.bodyBytes));
            final items = decodeFeedItems(
              j is Map ? j['items'] : null,
              group: b.group,
              category: b.category,
              today: today,
            );
            if (items.isEmpty) continue;
            fresh[(b.group, b.category)] = items;
            hashes[b.file] = b.hash;
          } catch (e) {
            // 이 게시판은 다음에 다시 받는다(지문을 안 적었으니).
            debugPrint('수집 파일 ${b.category} 받기 실패: $e');
          }
        }
      }

      await Future.wait([
        for (var i = 0; i < _kFeedMaxConcurrent && i < todo.length; i++)
          worker(),
      ]);

      if (fresh.isNotEmpty) {
        // 받는 동안 다른 곳이 캐시를 바꿨을 수 있으니 다시 읽어 합친다.
        final merged = mergeNoticeCache(
          await NoticeCache.load() ?? const [],
          fresh,
          known,
        );
        await NoticeCache.save(merged);
      }
      await prefs.setString(_hashesKey, jsonEncode(hashes));
      await prefs.setString(_indexKey, body);
      boards.value = index.boards;
      return fresh.length == todo.length;
    } catch (e) {
      debugPrint('공지 수집 파일 받기 실패: $e');
      return false;
    }
  }

  static Map<String, String> _loadHashes(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_hashesKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map(
        (k, v) => MapEntry(k as String, v as String),
      );
    } catch (_) {
      return {};
    }
  }
}
