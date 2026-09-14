// 공지 게시판 하나하나에 실제로 붙어 보는 점검기. 자동 테스트가 아니다
// (네트워크·학교 서버 상태에 따라 결과가 달라지므로 `_test.dart`로 두지 않았다).
//
//   flutter test test/notice_healthcheck.dart
//
// 화면에 뜨는 것과 같은 결과를 보려고 URL 목록과 파서는 앱 코드를 그대로 쓴다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:cp949_codec/cp949_codec.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_service.dart';

class Result {
  final String group, category, url;
  String status = '';
  int count = 0, dated = 0;
  String newest = '', sample = '', note = '';
  Result(this.group, this.category, this.url);
}

Future<Result> check(String group, String category, String url) async {
  final r = Result(group, category, url);
  if (url.startsWith('LINK:')) {
    r.status = 'LINK';
    r.note = '외부 링크 — 크롤링 대상 아님';
    return r;
  }
  final sw = Stopwatch()..start();
  http.Response res;
  try {
    res = await http.get(Uri.parse(url), headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }).timeout(const Duration(seconds: 15));
  } catch (e) {
    r.status = 'ERR';
    r.note = '$e'.replaceAll('\n', ' ');
    return r;
  }
  r.status = '${res.statusCode} ${sw.elapsedMilliseconds}ms';
  if (res.statusCode != 200) {
    r.note = 'HTTP ${res.statusCode}';
    return r;
  }

  List<Notice> notices;
  if (url.contains('pyxis-api')) {
    try {
      final list = jsonDecode(res.body)['data']['list'] as List;
      notices = [
        for (final it in list)
          Notice(
            id: 0,
            category: category,
            group: group,
            title: it['title'] ?? '제목없음',
            date: ((it['dateCreated'] ?? '') as String).split(' ').first,
            author: it['writer'] ?? '학교',
            link: '',
          )
      ];
    } catch (e) {
      r.note = 'JSON 파싱 실패: $e';
      return r;
    }
  } else {
    String html;
    try {
      html = utf8.decode(res.bodyBytes);
    } catch (_) {
      html = cp949.decode(res.bodyBytes);
    }
    notices = KnueScraper.parseHtml({
      'html': html,
      'group': group,
      'category': category,
      'url': url,
    });
  }

  r.count = notices.length;
  r.dated = notices.where((n) => n.date.isNotEmpty).length;
  final dates = notices.map((n) => n.date).where((d) => d.isNotEmpty).toList()
    ..sort();
  r.newest = dates.isEmpty ? '' : dates.last;
  if (notices.isNotEmpty) {
    final t = notices.first.title;
    r.sample = t.length > 34 ? '${t.substring(0, 34)}…' : t;
  }
  if (r.count == 0) r.note = '행은 받았으나 공지 0건 (선택자 불일치 의심)';
  if (r.count > 0 && r.dated == 0) r.note = '날짜를 하나도 못 읽음';
  return r;
}

void main() {
  // flutter_test는 기본적으로 모든 HTTP 요청에 400을 돌려준다. 실제 서버에
  // 붙어야 하는 점검이라 그 가로채기를 끈다.
  setUpAll(() => HttpOverrides.global = null);

  test('모든 공지 게시판 점검', () async {
    final scraper = KnueScraper();
    final jobs = <List<String>>[];
    for (final g in scraper.boardGroups.entries) {
      for (final b in g.value.entries) {
        jobs.add([g.key, b.key, b.value]);
      }
    }
    final results = <Result>[];
    for (var i = 0; i < jobs.length; i += 6) {
      final end = (i + 6).clamp(0, jobs.length);
      results.addAll(await Future.wait(
          jobs.sublist(i, end).map((j) => check(j[0], j[1], j[2]))));
    }

    String pad(String s, int n) {
      var w = 0;
      for (final c in s.runes) {
        w += c > 0x1100 ? 2 : 1;
      }
      return s + ' ' * (n - w).clamp(0, n);
    }

    var lastGroup = '';
    for (final r in results) {
      if (r.group != lastGroup) {
        // ignore: avoid_print
        print('\n── ${r.group} ${'─' * 60}');
        lastGroup = r.group;
      }
      final ok = r.note.isEmpty ? '정상' : (r.status == 'LINK' ? '링크' : '문제');
      // ignore: avoid_print
      print('$ok ${pad(r.category, 16)} ${pad(r.status, 12)} '
          '${pad('${r.count}건', 7)} ${pad(r.newest, 12)} '
          '${r.note.isEmpty ? r.sample : r.note}');
    }

    final bad = results.where((r) => r.note.isNotEmpty && r.status != 'LINK');
    // ignore: avoid_print
    print('\n전체 ${results.length}개 · 정상 '
        '${results.where((r) => r.note.isEmpty).length}개 · 문제 ${bad.length}개');
    for (final r in bad) {
      // ignore: avoid_print
      print('  ✗ ${r.group}/${r.category}  ${r.note}\n     ${r.url}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
