import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'school_http.dart';

// ── 학교 식단 API ───────────────────────────────────────────────────────
//
// 2026-10-02 정보전산원이 알려 준 주소다.
//   https://www.knue.ac.kr/rssDietInfoList.do?siteSe=one|cafe&stdde=YYYYMMDD
// 요청한 날짜가 속한 주(월~일) 7일치를 XML로 준다(약 5KB).
//
// 예전엔 식단 **웹 페이지**(selectDietInfoWebList.do, 약 215KB)를 받아 표를
// 뜯었고, 날짜마다 따로 캐시해서 같은 주의 다른 날을 열 때마다 같은 페이지를
// 또 받았다. 이제 식당마다 한 주에 한 번 받아 7일을 한꺼번에 채운다.
//
// 학교가 짚어 준 주의점(실제 응답으로 확인):
// - 값 앞뒤에 공백이 있다(`<stdde><![CDATA[ 20260928 ]]>`).
// - 메뉴는 "조식 : 백미밥\r\n근대된장국…"처럼 끼니 머리글이 붙어 온다.
// - CDATA 안에 `&amp;`가 그대로 남아 있다 — 파싱한 뒤 한 번 더 풀어야 한다.
// - 등록 안 된 끼니는 "정보 없음"이다. 이것도 캐시한다(반복 요청 금지).
// - 잘못된 요청의 오류 응답이 일정하지 않다. HTTP 200만으로 성공이라 보지
//   말고, 보내기 전에 값을 검사하고 응답의 날짜 범위·식당 이름을 확인한다.

const String kDietApiBase = 'https://www.knue.ac.kr/rssDietInfoList.do';

/// API가 받는 식당 값과, 응답의 식당 이름에 들어 있어야 할 글자.
const Map<String, String> kDietSiteNames = {
  'one': '사도교육원',
  'cafe': '교직원',
};

/// 날짜를 API가 쓰는 YYYYMMDD로.
String dietYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// 그 날짜가 속한 주의 월요일(시각은 0시).
DateTime dietMondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// 요청 주소. 값이 이상하면 보내지 않는다 — 학교 쪽 오류 응답이 일정하지
/// 않아서, 틀린 값을 보내 놓고 응답을 해석하려 들면 안 된다. 순수 함수 — 테스트 대상.
Uri dietApiUri(String siteSe, DateTime date) {
  if (!kDietSiteNames.containsKey(siteSe)) {
    throw ArgumentError.value(siteSe, 'siteSe', 'one 또는 cafe여야 한다');
  }
  if (date.year < 2020 || date.year > 2100) {
    throw ArgumentError.value(date, 'date', '식단을 물을 수 없는 날짜');
  }
  return Uri.parse('$kDietApiBase?siteSe=$siteSe&stdde=${dietYmd(date)}');
}

/// 한 주 식단. [days]의 키는 YYYYMMDD, 값은 앱이 쓰는 모양
/// (`{'breakfast': [...], 'lunch': [...], 'dinner': [...]}`).
@immutable
class DietWeek {
  final DateTime start;
  final DateTime end;
  final Map<String, Map<String, List<String>>> days;
  const DietWeek({required this.start, required this.end, required this.days});

  /// 그 날의 메뉴. 범위 안인데 항목이 없으면 빈 끼니로 준다("없음"도 정답).
  Map<String, List<String>> mealsOn(DateTime d) =>
      days[dietYmd(d)] ??
      {'breakfast': <String>[], 'lunch': <String>[], 'dinner': <String>[]};
}

/// 태그 하나의 글자. CDATA로 감싸져 있으면 벗기고 앞뒤 공백을 뗀다.
String? _tagText(String xml, String tag) {
  final open = xml.indexOf('<$tag>');
  if (open < 0) return null;
  final close = xml.indexOf('</$tag>', open);
  if (close < 0) return null;
  var t = xml.substring(open + tag.length + 2, close).trim();
  if (t.startsWith('<![CDATA[') && t.endsWith(']]>')) {
    t = t.substring(9, t.length - 3);
  }
  return t.trim();
}

DateTime? _parseYmd(String? s) {
  if (s == null || !RegExp(r'^\d{8}$').hasMatch(s)) return null;
  final y = int.parse(s.substring(0, 4));
  final m = int.parse(s.substring(4, 6));
  final d = int.parse(s.substring(6, 8));
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// `&amp;` 같은 표기를 글자로. CDATA 안이라 XML 파서가 풀어 주지 않는다.
/// `&amp;`를 맨 뒤에 풀어야 "&amp;lt;"가 "<"로 두 번 풀리지 않는다.
String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

const _mealHeadings = {'조식', '중식', '석식', '아침', '점심', '저녁'};

/// 끼니 하나의 글자를 메뉴 줄 목록으로. "정보 없음"이면 빈 목록.
/// 순수 함수 — 테스트 대상.
List<String> dietLines(String? raw) {
  if (raw == null) return const [];
  // "조식 : 백미밥…" → "백미밥…"
  final body = raw.trim().replaceFirst(RegExp(r'^(조식|중식|석식)\s*:\s*'), '');
  if (body.trim() == '정보 없음') return const [];
  return [
    for (final line in body.split(RegExp(r'[\r\n]+')))
      if (_unescape(line).trim() case final s
          when s.isNotEmpty && !_mealHeadings.contains(s) && !s.startsWith('['))
        s,
  ];
}

/// 식단 API 응답을 읽는다. 믿을 수 없는 응답이면 null. 순수 함수 — 테스트 대상.
///
/// [siteSe]로 요청한 식당과 응답의 식당 이름이 다르거나, [requested]가 응답의
/// 날짜 범위 밖이면 버린다 — 틀린 메뉴를 보여 주느니 비워 두는 편이 낫다
/// (예전에 다른 주 메뉴가 공용 캐시에 굳어 2주 동안 틀린 식단이 나간 적이 있다).
DietWeek? parseDietWeek(String xml, {required String siteSe, required DateTime requested}) {
  final siteName = kDietSiteNames[siteSe];
  if (siteName == null) return null;

  final start = _parseYmd(_tagText(xml, 'StartDate'));
  final end = _parseYmd(_tagText(xml, 'EndDate'));
  if (start == null || end == null || end.isBefore(start)) return null;
  final day = DateTime(requested.year, requested.month, requested.day);
  if (day.isBefore(start) || day.isAfter(end)) return null;

  final days = <String, Map<String, List<String>>>{};
  for (final m in RegExp(r'<item>([\s\S]*?)</item>').allMatches(xml)) {
    final item = m.group(1)!;
    final site = _tagText(item, 'siteSe');
    if (site == null || !site.contains(siteName)) return null;
    final date = _parseYmd(_tagText(item, 'stdde'));
    if (date == null || date.isBefore(start) || date.isAfter(end)) continue;
    days[dietYmd(date)] = {
      'breakfast': dietLines(_tagText(item, 'mornDiet')),
      'lunch': dietLines(_tagText(item, 'lunchDiet')),
      'dinner': dietLines(_tagText(item, 'dinnrDiet')),
    };
  }
  if (days.isEmpty) return null;
  return DietWeek(start: start, end: end, days: days);
}

/// 그 날짜가 속한 주의 식단을 받는다. 실패하거나 응답을 믿을 수 없으면 null.
Future<DietWeek?> fetchDietWeek(String siteSe, DateTime date) async {
  final uri = dietApiUri(siteSe, date);
  try {
    final res = await http
        .get(uri, headers: await SchoolHttp.headers())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return parseDietWeek(
      utf8.decode(res.bodyBytes, allowMalformed: true),
      siteSe: siteSe,
      requested: date,
    );
  } catch (e) {
    debugPrint('식단 API 실패: $e');
    return null;
  }
}
