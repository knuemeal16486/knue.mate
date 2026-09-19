import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'club_event_model.dart';
import 'offline_cache.dart';

/// 동아리 행사 Firestore CRUD + Storage 포스터 업로드 + 로컬 캐시.
class ClubEventService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static const String _collection = 'club_events';

  /// 행사 목록. 캐시가 있으면 즉시 반환하고 백그라운드 갱신.
  ///
  /// 끝난 행사는 기본적으로 걸러낸다. 지우는 것은 [purgeEnded]가 따로 하고,
  /// 여기서는 보여주지만 않는다 — 기기 시계가 틀어진 폰 하나가 공용 목록을
  /// 지워버리는 일은 없어야 한다.
  static Future<List<ClubEvent>> fetchAll({
    bool forceRefresh = false,
    bool includeEnded = false,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final all = await _fetchAllRaw(forceRefresh: forceRefresh, timeout: timeout);
    if (includeEnded) return all;
    final now = DateTime.now();
    return all.where((e) => !e.hasEnded(now)).toList();
  }

  static Future<List<ClubEvent>> _fetchAllRaw({
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!forceRefresh) {
      final cached = await ClubEventCache.load();
      if (cached != null && cached.isNotEmpty) {
        // throttle이 없으면 갱신→재로드→갱신으로 계속 Firestore를 두드린다.
        RefreshThrottle.deferred("clubEvents", () => _fetchAndCache(timeout));
        return cached;
      }
    }
    return _fetchAndCache(timeout);
  }

  /// 끝난 지 [grace]가 지난 행사를 Firestore에서 지운다.
  ///
  /// 관리 화면에서만 부른다. 앱을 켠 모든 기기가 지우게 두면, 시계가 앞서
  /// 있는 기기 하나가 아직 열리지도 않은 행사를 지울 수 있다. 여유를 일주일
  /// 두는 것도 같은 이유 — 어제 끝난 행사를 시간대 차이로 오늘 지우지 않게.
  static Future<int> purgeEnded({
    Duration grace = const Duration(days: 7),
  }) async {
    final cutoff = DateTime.now().subtract(grace);
    final all = await _fetchAllRaw(forceRefresh: true);
    final stale = all.where(
      (e) => e.effectiveEnd.isBefore(cutoff) && e.id.isNotEmpty,
    );
    var removed = 0;
    for (final e in stale) {
      try {
        await delete(e.id);
        removed++;
      } catch (err) {
        debugPrint('ClubEventService.purgeEnded error: $err');
      }
    }
    if (removed > 0) await _fetchAndCache(const Duration(seconds: 8));
    return removed;
  }

  static Future<List<ClubEvent>> _fetchAndCache(
    Duration timeout,
  ) async {
    // 이미 Firestore가 죽어 있다고 확인됐으면 기다리지 않고 캐시로 간다.
    if (!FirestoreHealth.isAvailable) {
      return await ClubEventCache.load() ?? const [];
    }
    try {
      // 타임아웃이 없어서, 권한 오류처럼 실패하는 경우 7초 가까이 매달렸다.
      // 홈 화면이 그만큼 로딩 상태로 남는다 — 그래서 홈 미리보기 카드는 기본값
      // (4초)을 쓴다. 반면 전용 목록 화면(ClubEventsScreen)은 사용자가 이미
      // 그 화면만 보고 기다리는 중이라 더 길게 줘도 된다 — 앱 시작 직후라
      // Firebase 초기화·다른 탭 로딩과 네트워크를 나눠 쓰는 순간엔 4초가
      // 너무 빠듯해서 캐시 없는 첫 진입이 그대로 "불러오기 실패"로 떨어졌다.
      final snapshot =
          await _db.collection(_collection).get().timeout(timeout);
      final events =
          snapshot.docs
              .map((d) => ClubEvent.fromFirestore(d.id, d.data()))
              .toList()
            ..sort((a, b) => a.startDate.compareTo(b.startDate));
      FirestoreHealth.reportSuccess();
      await ClubEventCache.save(events);
      return events;
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('ClubEventService.fetchAll error: $e');
      final cached = await ClubEventCache.load();
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// id 비었으면 신규 추가, 있으면 갱신.
  static Future<void> upsert(ClubEvent event) async {
    final col = _db.collection(_collection);
    if (event.id.isEmpty) {
      await col.add(event.toFirestore());
    } else {
      await col.doc(event.id).set(event.toFirestore(), SetOptions(merge: true));
    }
  }

  static Future<void> delete(String id) async {
    await _db.collection(_collection).doc(id).delete();
  }

  static Future<void> setFeatured(String id, bool featured) async {
    await _db.collection(_collection).doc(id).update({'isFeatured': featured});
  }

  /// 로컬 파일 경로의 포스터를 Storage에 올리고 다운로드 URL 반환. 실패 시 null.
  static Future<String?> uploadPoster(String localPath) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref('club_posters/$ts.jpg');
      await ref.putFile(File(localPath));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('ClubEventService.uploadPoster error: $e');
      return null;
    }
  }

  /// 관리자 비밀번호 (app_config/club_admin 문서의 password 필드).
  static Future<String?> fetchAdminPassword() async {
    try {
      final doc = await _db.collection('app_config').doc('club_admin').get();
      return doc.data()?['password'] as String?;
    } catch (e) {
      debugPrint('ClubEventService.fetchAdminPassword error: $e');
      return null;
    }
  }
}

/// 행사 목록 캐시 — NoticeCache와 동일 패턴 (SharedPreferences + JSON).
class ClubEventCache {
  static const _key = 'clubEventCache';

  /// save()될 때마다 값이 바뀐다. fetchAll()은 캐시를 먼저 반환하고 백그라운드로
  /// 갱신하는데(await 없이), 이 리스너가 있어야 화면이 갱신 완료를 알아채고 다시 그린다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> save(List<ClubEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(events.map((e) => e.toJson()).toList());
    // 내용이 같으면 revision을 올리지 않는다 — 올리면 화면이 다시 로드하고,
    // 그게 또 갱신을 불러 무한 루프가 된다.
    final changed = prefs.getString(_key) != encoded;
    await prefs.setString(_key, encoded);
    await prefs.setInt('${_key}_ts', DateTime.now().millisecondsSinceEpoch);
    if (changed) revision.value++;
  }

  static Future<List<ClubEvent>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list
          .map((e) => ClubEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> lastUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('${_key}_ts');
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }
}
