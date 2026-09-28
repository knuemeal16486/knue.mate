import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'notice_model.dart';
import 'offline_cache.dart';
import 'school_http.dart';

// ── 학사일정 ─────────────────────────────────────────────────────────────
//
// 학교 학사일정 페이지(selectSchdleWebList.do?key=542)는 **학년도 단위**다.
// searchY=2026이면 2026년 3월 ~ 2027년 2월이 한 표("2026년 전체 일정표")에
// 실리고, searchM은 무시된다 — 무엇을 넣든 1년치가 통째로 온다(약 386KB,
// 2026-09-28 확인).
//
// 예전엔 기기마다 달마다 이 페이지를 따로 받아, 9/28 하루 학교 서버에 약
// 1,200건이 갔다(정보전산원 메일). 이제 학년도 하나를 Firestore 문서 하나
// (academic_calendar/{학년도})에 두고 모든 기기가 나눠 쓴다. 학교 페이지는
// 문서가 [kCalendarSharedFresh]보다 묵었을 때 **기기 한 대만** 받는다.
//
// 학사일정도 학기 중에 드물게 바뀐다(일정 추가·변경). 그래서 한 번 저장하고
// 끝이 아니라 유효기간을 둔다 — 식단 공용 캐시가 유효기간 없이 한 번 쓰이고
// 굳어서 2주 전 메뉴가 계속 나간 적이 있다.

/// 기기에 저장한 학사일정을 그대로 믿는 기간. 이 안에서는 Firestore도 안 읽는다.
const Duration kCalendarLocalFresh = Duration(hours: 12);

/// 공용 문서를 그대로 믿는 기간. 이보다 묵으면 기기 한 대가 학교에서 다시 받는다.
const Duration kCalendarSharedFresh = Duration(hours: 24);

/// 한 기기가 "내가 받는 중"이라고 잡아 두는 시간. 받다가 죽어도 이만큼 지나면
/// 다른 기기가 이어받는다.
const Duration kCalendarRefreshLease = Duration(minutes: 10);

/// 한 기기가 같은 학년도를 학교에서 다시 받는 최소 간격(기기에 저장).
/// 공용 캐시가 막혔을 때(규칙 미배포·오프라인)도 기기당 하루 2건을 넘지 않게 한다.
const Duration kCalendarSchoolGap = Duration(hours: 12);

/// [year]년 [month]월이 속한 학년도. 3월에 시작한다. 순수 함수 — 테스트 대상.
int academicYearOf(int year, int month) => month >= 3 ? year : year - 1;

/// 학년도 표의 "월.일"을 실제 날짜로. 1~2월은 이듬해다. 순수 함수 — 테스트 대상.
///
/// 예전 파서는 1~2월 행도 searchY 해로 읽어서 1~2월 일정이 1년씩 어긋났다
/// (2026학년도 표의 "02.18 전기 학위수여식"은 2027년 2월 18일이다).
DateTime academicDate(int academicYear, int month, int day) =>
    DateTime(month >= 3 ? academicYear : academicYear + 1, month, day);

/// 학교 페이지가 searchM을 무시하고 1년치를 한 번에 돌려주므로, 달력에는
/// 그 달과 겹치는 일정만 남긴다. 월 경계에 걸친 일정(예: 8.31~9.4)은 양쪽
/// 달 모두에 걸리는 게 맞으므로 날짜 범위가 그 달과 겹치는지로 판단한다.
/// 순수 함수 — 테스트 대상.
List<CalendarEvent> scopeEventsToMonth(
  List<CalendarEvent> events,
  int year,
  int month,
) {
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 1);
  return events
      .where(
        (e) => e.startDate.isBefore(monthEnd) && !e.endDate.isBefore(monthStart),
      )
      .toList();
}

/// 같은 일정이 여러 번 실려 오는 걸 하나로 합친다.
///
/// 학교 페이지가 기간 일정을 행마다 반복해 싣거나, 기간이 겹치는 같은
/// 일정이 따로 등록돼 있어서 같은 제목이 두세 번씩 잡힌다. 학사일정 화면은
/// 목록이 길어 중복이 눈에만 거슬리는 정도지만, **홈 카드는 앞의 3개만
/// 보여주므로 중복 하나가 자리를 통째로 먹는다** — 같은 일정만 세 줄 뜨고
/// 정작 다음 일정은 안 보이는 일이 생긴다.
///
/// 제목만이 아니라 기간까지 같아야 같은 일정으로 본다. 제목만 보면
/// "중간고사" 같은 이름이 학기마다 반복될 때 뒤쪽을 잘못 지운다.
/// 순수 함수 — 테스트 대상.
List<CalendarEvent> dedupeCalendarEvents(List<CalendarEvent> events) {
  final seen = <String>{};
  return events
      .where((e) => seen.add('${e.title.trim()}|${e.startDate}|${e.endDate}'))
      .toList();
}

/// 홈 카드의 "다가오는 학사일정" 고르기.
///
/// 오늘 아직 안 끝난 일정만 남겨 시작이 이른 순으로 [take]개.
/// 여러 달치를 받아 넘기는 걸 전제로 한다 — 이번 달만 넘기면 월말에
/// 빈 카드가 된다. 순수 함수 — 테스트 대상.
List<CalendarEvent> upcomingAcademicEvents(
  List<CalendarEvent> events,
  DateTime now, {
  int take = 3,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final upcoming = dedupeCalendarEvents(events).where((e) {
    final end = DateTime(e.endDate.year, e.endDate.month, e.endDate.day);
    return !end.isBefore(today);
  }).toList()..sort((a, b) => a.startDate.compareTo(b.startDate));
  return upcoming.take(take).toList();
}

/// 학사일정 페이지에서 학년도 전체 일정을 읽는다. 순수 함수 — 테스트 대상.
///
/// 페이지에는 "이번 달 표"와 "1년치 표"가 같이 있다. 1년치 표(캡션에
/// "전체 일정표"와 "학기"가 있는 것)만 읽는다 — 둘 다 읽으면 이번 달 일정이
/// 두 번씩 잡힌다. 그 표를 못 찾으면(학교가 화면을 바꾸면) 모든 행을 읽고
/// 중복은 걷어낸다.
List<CalendarEvent> parseAcademicYearHtml(String html, int academicYear) {
  final doc = parser.parse(html);
  List<dom.Element> rows = const [];
  for (final table in doc.querySelectorAll('table')) {
    final caption = table.querySelector('caption')?.text ?? '';
    if (caption.contains('전체 일정표') && caption.contains('학기')) {
      rows = table.querySelectorAll('tbody tr');
      break;
    }
  }
  if (rows.isEmpty) rows = doc.querySelectorAll('tbody tr');

  DateTime? dateIn(dom.Element? span) {
    if (span == null) return null;
    final m = int.tryParse(span.querySelector('.month')?.text.trim() ?? '');
    final d = int.tryParse(span.querySelector('.days')?.text.trim() ?? '');
    if (m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) {
      return null;
    }
    return academicDate(academicYear, m, d);
  }

  final events = <CalendarEvent>[];
  for (final tr in rows) {
    final title = tr.querySelector('.more_link')?.text.trim() ?? '';
    if (title.isEmpty) continue;
    final start = dateIn(tr.querySelector('.start'));
    if (start == null) continue;
    var end = dateIn(tr.querySelector('.end')) ?? start;
    if (end.isBefore(start)) end = start;
    events.add(CalendarEvent(startDate: start, endDate: end, title: title));
  }
  return dedupeCalendarEvents(events);
}

/// 공용 문서를 새로 받아야 하는지. 순수 함수 — 테스트 대상.
///
/// - 문서가 [kCalendarSharedFresh] 안에 갱신됐으면 받지 않는다.
/// - 다른 기기가 받는 중(잡아 둔 시간이 안 지남)이면 받지 않는다.
/// - 기록이 미래로 적혀 있으면(시계가 틀린 기기가 썼으면) 없는 것으로 본다.
bool shouldClaimCalendarRefresh({
  required DateTime? fetchedAt,
  required DateTime? refreshingUntil,
  required DateTime now,
}) {
  if (fetchedAt != null &&
      !fetchedAt.isAfter(now) &&
      now.difference(fetchedAt) < kCalendarSharedFresh) {
    return false;
  }
  if (refreshingUntil != null &&
      refreshingUntil.isAfter(now) &&
      refreshingUntil.difference(now) <= kCalendarRefreshLease) {
    return false;
  }
  return true;
}

List<Map<String, String>> _encodeEvents(List<CalendarEvent> events) => [
  for (final e in events)
    {
      'start': e.startDate.toIso8601String(),
      'end': e.endDate.toIso8601String(),
      'title': e.title,
    },
];

List<CalendarEvent>? _decodeEvents(Object? raw) {
  if (raw is! List) return null;
  try {
    return [
      for (final e in raw)
        CalendarEvent(
          startDate: DateTime.parse(e['start'] as String),
          endDate: DateTime.parse(e['end'] as String),
          title: e['title'] as String,
        ),
    ];
  } catch (_) {
    return null;
  }
}

/// 학사일정 기기 캐시. 학년도 단위로 저장한다.
class CalendarCache {
  /// 백그라운드 갱신이 끝나면 값이 바뀐다. 화면은 이걸 구독해 다시 그린다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // v3: 달 단위(v2)에서 학년도 단위로 바꿨다. v2는 1~2월을 1년 어긋나게 읽었다.
  static String _key(int academicYear) => 'calendarYear_v3_$academicYear';

  /// 저장해 둔 일정과 저장한 시각. 오래됐어도 돌려준다 — 빈 카드보다 낫고,
  /// 신선한지는 호출부가 [savedAt]으로 판단한다.
  static Future<({List<CalendarEvent> events, DateTime savedAt})?> load(
    int academicYear,
  ) async {
    final key = _key(academicYear);
    final events = _decodeEvents(
      await JsonCache.load(key, maxAge: const Duration(days: 400)),
    );
    final savedAt = await JsonCache.savedAt(key);
    if (events == null || savedAt == null) return null;
    return (events: events, savedAt: savedAt);
  }

  static Future<void> save(int academicYear, List<CalendarEvent> events) async {
    // 내용이 같으면 revision을 올리지 않는다 — 올리면 화면이 다시 로드하고,
    // 그게 또 갱신을 불러 무한 루프가 된다.
    if (await JsonCache.save(_key(academicYear), _encodeEvents(events))) {
      revision.value++;
    }
  }
}

/// 학사일정 공용 캐시. 위 설명 참고.
class AcademicCalendarStore {
  static final Map<int, Future<List<CalendarEvent>>> _inflight = {};

  static DocumentReference<Map<String, dynamic>> _doc(int academicYear) =>
      FirebaseFirestore.instance
          .collection('academic_calendar')
          .doc('$academicYear');

  /// [academicYear] 학년도 일정. 기기 캐시가 있으면 즉시 돌려주고,
  /// [kCalendarLocalFresh]보다 묵었으면 뒤에서 갱신한다.
  static Future<List<CalendarEvent>> load(int academicYear) async {
    final local = await CalendarCache.load(academicYear);
    if (local != null) {
      if (DateTime.now().difference(local.savedAt) > kCalendarLocalFresh) {
        RefreshThrottle.deferred(
          'academic_calendar_$academicYear',
          () => _refreshOnce(academicYear),
        );
      }
      return local.events;
    }
    return _refreshOnce(academicYear);
  }

  /// 홈 카드가 이번 달·다음 달을 동시에 부르므로, 같은 학년도는 한 번만 받는다.
  static Future<List<CalendarEvent>> _refreshOnce(int academicYear) =>
      _inflight[academicYear] ??= _refresh(academicYear)
          .whenComplete(() => _inflight.remove(academicYear));

  static Future<List<CalendarEvent>> _refresh(int academicYear) async {
    final shared = await _readShared(academicYear);
    final now = DateTime.now();
    if (shared != null &&
        !shouldClaimCalendarRefresh(
          fetchedAt: shared.fetchedAt,
          refreshingUntil: null,
          now: now,
        )) {
      await CalendarCache.save(academicYear, shared.events);
      return shared.events;
    }

    Future<List<CalendarEvent>> fallback() async {
      if (shared != null && shared.events.isNotEmpty) {
        await CalendarCache.save(academicYear, shared.events);
        return shared.events;
      }
      return (await CalendarCache.load(academicYear))?.events ?? const [];
    }

    // 공용 문서가 없거나 묵었다 — 기기 한 대만 학교에서 받는다.
    final claimed = await _claimRefresh(academicYear);
    if (claimed == false) return fallback(); // 다른 기기가 받는 중

    // claimed == null: 공용 캐시를 못 쓴다(규칙 미배포·오프라인). 이때도
    // 기기당 간격 제한은 지킨다.
    final allowed = await PersistentThrottle.tryAcquire(
      'calendar_school',
      '$academicYear',
      kCalendarSchoolGap,
    );
    if (!allowed) return fallback();

    final scraped = await _scrape(academicYear);
    if (scraped == null) return fallback(); // 실패 — 잡아 둔 시간이 지나면 다른 기기가 이어받는다

    // 다음 학년도 표가 아직 안 올라왔으면 빈 결과다. 그것도 "받았음"으로
    // 적어야 다른 기기들이 하루 동안 다시 받지 않는다. 다만 있던 일정을
    // 빈 값으로 덮지는 않는다(학교가 화면을 바꿔 파싱이 깨졌을 수도 있다).
    final events = scraped.isNotEmpty ? scraped : (shared?.events ?? const []);
    if (claimed == true) await _writeShared(academicYear, events);
    await CalendarCache.save(academicYear, events);
    return events;
  }

  static Future<({List<CalendarEvent> events, DateTime? fetchedAt})?>
  _readShared(int academicYear) async {
    if (Firebase.apps.isEmpty || !FirestoreHealth.isAvailable) return null;
    try {
      final snap = await _doc(academicYear).get().timeout(
        const Duration(seconds: 3),
      );
      FirestoreHealth.reportSuccess();
      final data = snap.data();
      if (data == null) return null;
      final events = _decodeEvents(data['events']);
      if (events == null) return null;
      final ts = data['fetchedAt'];
      return (events: events, fetchedAt: ts is Timestamp ? ts.toDate() : null);
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('학사일정 공용 캐시 읽기 실패: $e');
      return null;
    }
  }

  /// 갱신할 권한을 잡는다. true: 내가 받는다, false: 받을 필요 없음/다른
  /// 기기가 받는 중, null: 공용 캐시를 쓸 수 없음.
  static Future<bool?> _claimRefresh(int academicYear) async {
    if (Firebase.apps.isEmpty || !FirestoreHealth.isAvailable) return null;
    try {
      final ref = _doc(academicYear);
      return await FirebaseFirestore.instance
          .runTransaction<bool>((tx) async {
            final data = (await tx.get(ref)).data();
            final fetchedAt = data?['fetchedAt'];
            final until = data?['refreshingUntil'];
            final now = DateTime.now();
            final claim = shouldClaimCalendarRefresh(
              fetchedAt: fetchedAt is Timestamp ? fetchedAt.toDate() : null,
              refreshingUntil: until is Timestamp ? until.toDate() : null,
              now: now,
            );
            if (claim) {
              tx.set(ref, {
                'refreshingUntil': Timestamp.fromDate(
                  now.add(kCalendarRefreshLease),
                ),
              }, SetOptions(merge: true));
            }
            return claim;
          })
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('학사일정 갱신 권한 잡기 실패: $e');
      return null;
    }
  }

  static Future<void> _writeShared(
    int academicYear,
    List<CalendarEvent> events,
  ) async {
    try {
      // merge 없이 통째로 쓴다 — refreshingUntil도 같이 지워진다.
      await _doc(academicYear).set({
        'academicYear': academicYear,
        'events': _encodeEvents(events),
        'fetchedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('학사일정 공용 캐시 쓰기 실패: $e');
    }
  }

  /// 학교 페이지에서 학년도 전체를 받는다. 실패하면 null.
  static Future<List<CalendarEvent>?> _scrape(int academicYear) async {
    final url = Uri.parse(
      'https://www.knue.ac.kr/www/selectSchdleWebList.do'
      '?key=542&searchY=$academicYear&searchM=03',
    );
    try {
      final res = await http
          .get(url, headers: await SchoolHttp.headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return parseAcademicYearHtml(res.body, academicYear);
    } catch (e) {
      debugPrint('학사일정 받기 실패: $e');
      return null;
    }
  }
}
