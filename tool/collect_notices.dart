// 공지 중앙 수집기. GitHub Actions(.github/workflows/collect-notices.yml)가
// 30분마다 돌린다. 손으로도 돌릴 수 있다:
//
//   dart run tool/collect_notices.dart --out build/feed
//   dart run tool/collect_notices.dart --out build/feed --prev https://<계정>.github.io/<저장소>/feed
//
// 학교 게시판을 서버마다 한 번에 하나씩, 사이를 두고 받아
// 제목·링크·날짜·부서만 추린 파일을 만든다(lib/notice_collector.dart 참고).
//
//   <out>/index.json      게시판별 갱신 시각·지문
//   <out>/b/<id>.json     게시판 하나의 글 목록
//
// --prev: 지난번에 배포한 수집 파일의 주소. 이번에 받을 차례가 아니거나 받다가
//         실패한 게시판은 거기 있는 내용을 그대로 다시 싣는다(배포가 사이트를
//         통째로 갈아 끼우므로, 안 실으면 그 게시판이 사라진다).
// --force: 간격을 무시하고 전부 받는다.
// --gap <ms>: 같은 서버로 보내는 요청 사이 간격(기본 1500).
import 'dart:convert';
import 'dart:io';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:http/http.dart' as http;
import 'package:knue_mate/notice_collector.dart';

const _headers = {'User-Agent': kCollectorUserAgent};

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return cp949.decode(bytes);
  }
}

/// 게시판 하나의 결과: 실을 파일 내용과 목록의 한 줄.
typedef _Result = ({String body, FeedBoardEntry entry, String note});

Future<void> main(List<String> args) async {
  final outDir = _arg(args, '--out');
  if (outDir == null) {
    stderr.writeln('usage: dart run tool/collect_notices.dart --out <dir> '
        '[--prev <url>] [--force] [--gap <ms>]');
    exit(64);
  }
  final prevBase = _arg(args, '--prev')?.replaceAll(RegExp(r'/+$'), '');
  final force = args.contains('--force');
  final gap = Duration(
    milliseconds:
        int.tryParse(_arg(args, '--gap') ?? '') ??
        kCollectRequestGap.inMilliseconds,
  );
  final now = DateTime.now().toUtc();
  final client = http.Client();

  // ── 지난번 배포본 ──
  final prevEntries = <String, FeedBoardEntry>{};
  final prevBodies = <String, String>{};
  if (prevBase != null) {
    try {
      final res = await client
          .get(Uri.parse('$prevBase/index.json'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      final index = res.statusCode == 200
          ? parseFeedIndex(utf8.decode(res.bodyBytes))
          : null;
      for (final e in index?.boards ?? const <FeedBoardEntry>[]) {
        final r = await client
            .get(Uri.parse('$prevBase/${e.file}'), headers: _headers)
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) continue;
        prevEntries[e.file] = e;
        prevBodies[e.file] = utf8.decode(r.bodyBytes);
      }
      stdout.writeln('지난 배포본: 게시판 ${prevEntries.length}개');
    } catch (e) {
      stdout.writeln('지난 배포본을 못 읽음(처음이면 정상): $e');
    }
  }

  // ── 수집 ── 서버마다 줄을 세워 한 번에 하나씩 받는다.
  final boards = collectBoards();
  final results = <String, _Result>{};
  final queues = <String, List<CollectBoard>>{};
  for (final b in boards) {
    (queues[b.host] ??= []).add(b);
  }
  var requests = 0, bytes = 0;

  String fileOf(CollectBoard b) => 'b/${b.fileId}.json';

  /// 이번에 새로 받지 않고 지난번 내용을 다시 싣는다.
  _Result? carry(CollectBoard b, {required bool ok, required String note}) {
    final file = fileOf(b);
    final prev = prevEntries[file], body = prevBodies[file];
    if (prev == null || body == null) return null;
    return (
      body: body,
      entry: FeedBoardEntry(
        group: b.group,
        category: b.category,
        file: file,
        fetchedAt: prev.fetchedAt,
        ok: ok,
        count: prev.count,
        hash: prev.hash,
      ),
      note: note,
    );
  }

  _Result empty(CollectBoard b, String note) => (
    body: jsonEncode({
      'group': b.group,
      'category': b.category,
      'fetchedAt': null,
      'items': const [],
    }),
    entry: FeedBoardEntry(
      group: b.group,
      category: b.category,
      file: fileOf(b),
      fetchedAt: null,
      ok: false,
      count: 0,
      hash: '',
    ),
    note: note,
  );

  await Future.wait(queues.entries.map((q) async {
    var failuresInRow = 0, sent = 0;
    for (final b in q.value) {
      final file = fileOf(b);
      final prev = prevEntries[file];
      if (!force && !isBoardDue(prev?.fetchedAt, b.interval, now)) {
        results[file] = carry(b, ok: prev?.ok ?? true, note: '차례 아님')!;
        continue;
      }
      if (failuresInRow >= kCollectMaxFailuresInRow) {
        results[file] =
            carry(b, ok: false, note: '서버 연속 실패로 건너뜀') ??
            empty(b, '서버 연속 실패로 건너뜀');
        continue;
      }
      if (sent > 0) await Future.delayed(gap);
      sent++;
      String note;
      try {
        final res = await client
            .get(Uri.parse(b.fetchUrl), headers: _headers)
            .timeout(const Duration(seconds: 20));
        requests++;
        bytes += res.bodyBytes.length;
        if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
        final notices = parseCollected(b, _decode(res.bodyBytes));
        if (notices == null) throw '응답을 읽을 수 없음';
        // 글이 있던 게시판이 갑자기 0건이면 형식이 바뀌었거나 오류 화면이다.
        if (notices.isEmpty && (prev?.count ?? 0) > 0) throw '0건(지난번 ${prev!.count}건)';
        final items = encodeFeedItems(notices);
        results[file] = (
          body: jsonEncode({
            'group': b.group,
            'category': b.category,
            'fetchedAt': now.toIso8601String(),
            'items': items,
          }),
          entry: FeedBoardEntry(
            group: b.group,
            category: b.category,
            file: file,
            fetchedAt: now,
            ok: true,
            count: items.length,
            hash: fnvHex(jsonEncode(items)),
          ),
          note: '${b.rssUrl != null ? 'RSS' : '목록'} ${res.bodyBytes.length ~/ 1024}KB → ${items.length}건',
        );
        failuresInRow = 0;
        continue;
      } catch (e) {
        failuresInRow++;
        note = '실패: $e';
        // 요청 시각·주소·오류 — 학교에 알릴 때 필요한 정보다.
        stderr.writeln('${now.toIso8601String()} ${b.fetchUrl} $e');
      }
      results[file] = carry(b, ok: false, note: note) ?? empty(b, note);
    }
  }));
  client.close();

  // ── 쓰기 ──
  Directory('$outDir/b').createSync(recursive: true);
  final entries = <FeedBoardEntry>[];
  for (final b in boards) {
    final r = results[fileOf(b)]!;
    File('$outDir/${r.entry.file}').writeAsStringSync(r.body);
    entries.add(r.entry);
    stdout.writeln(
      '${r.entry.ok ? 'OK  ' : 'FAIL'} ${b.group.padRight(5)} ${b.category}  ${r.note}',
    );
  }
  File('$outDir/index.json').writeAsStringSync(encodeFeedIndex(now, entries));

  final ok = entries.where((e) => e.ok).length;
  final withData = entries.where((e) => e.count > 0).length;
  stdout.writeln(
    '\n게시판 ${entries.length}개 · 성공 $ok · 글 있는 게시판 $withData · '
    '학교 요청 $requests건 · ${(bytes / 1024 / 1024).toStringAsFixed(1)}MB',
  );
  // 하나도 못 건졌으면 배포하지 않는다 — 빈 파일로 멀쩡한 배포본을 덮으면 안 된다.
  if (withData == 0) {
    stderr.writeln('실을 글이 하나도 없다. 배포하지 않는다.');
    exit(1);
  }
}
