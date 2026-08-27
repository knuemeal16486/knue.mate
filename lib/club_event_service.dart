import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'club_event_model.dart';

/// 동아리 행사 Firestore CRUD + Storage 포스터 업로드 + 로컬 캐시.
class ClubEventService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static const String _collection = 'club_events';

  /// 행사 목록. 캐시가 있으면 즉시 반환하고 백그라운드 갱신.
  static Future<List<ClubEvent>> fetchAll({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await ClubEventCache.load();
      if (cached != null && cached.isNotEmpty) {
        _fetchAndCache(); // await 없이 갱신
        return cached;
      }
    }
    return _fetchAndCache();
  }

  static Future<List<ClubEvent>> _fetchAndCache() async {
    try {
      final snapshot = await _db.collection(_collection).get();
      final events = snapshot.docs
          .map((d) => ClubEvent.fromFirestore(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      await ClubEventCache.save(events);
      return events;
    } catch (e) {
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
    await prefs.setString(
        _key, jsonEncode(events.map((e) => e.toJson()).toList()));
    await prefs.setInt('${_key}_ts', DateTime.now().millisecondsSinceEpoch);
    revision.value++;
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
