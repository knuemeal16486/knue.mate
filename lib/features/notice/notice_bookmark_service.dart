import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notice_model.dart';

/// 공지 북마크(스크랩) 로컬 저장 서비스.
///
/// 사용자가 장학금·수강신청 등 중요한 공지를 앱 안에 저장해 두고 다시 열어볼 수 있게 한다.
/// 설정 초기화(`PreferencesService.resetSettings`)가 개인 일정·D-day를 남기는 것과
/// 마찬가지로, 북마크 키는 설정 키 목록에 넣지 않아 초기화 시에도 보존된다.
class NoticeBookmarkService {
  NoticeBookmarkService._();

  static const String kStorageKey = 'bookmarked_notices_v1';

  static final ValueNotifier<List<Notice>> bookmarks = ValueNotifier(const []);

  /// 공지 한 건의 고유 식별 키. 링크가 있으면 링크, 없으면 게시판+ID+제목 조합.
  static String keyOf(Notice notice) {
    final link = notice.link.trim();
    if (link.isNotEmpty) return link;
    return '${notice.category}:${notice.id}:${notice.title}';
  }

  static bool isBookmarked(Notice notice) {
    final target = keyOf(notice);
    return bookmarks.value.any((n) => keyOf(n) == target);
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kStorageKey);
      if (raw == null || raw.isEmpty) {
        bookmarks.value = const [];
        return;
      }
      final decoded = jsonDecode(raw) as List;
      bookmarks.value = decoded
          .whereType<Map>()
          .map((m) => Notice.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('NoticeBookmarkService load error: $e');
    }
  }

  /// 북마크 추가(true 반환) 또는 해제(false 반환).
  static Future<bool> toggle(Notice notice) async {
    final target = keyOf(notice);
    final current = List<Notice>.from(bookmarks.value);
    final idx = current.indexWhere((n) => keyOf(n) == target);
    final bool added;
    if (idx >= 0) {
      current.removeAt(idx);
      added = false;
    } else {
      current.insert(0, notice);
      added = true;
    }
    await _persist(current);
    return added;
  }

  static Future<void> remove(Notice notice) async {
    final target = keyOf(notice);
    final current = List<Notice>.from(bookmarks.value)
      ..removeWhere((n) => keyOf(n) == target);
    await _persist(current);
  }

  static Future<void> _persist(List<Notice> items) async {
    bookmarks.value = List.unmodifiable(items);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kStorageKey,
        jsonEncode(items.map((n) => n.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('NoticeBookmarkService persist error: $e');
    }
  }
}
