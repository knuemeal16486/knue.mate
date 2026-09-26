// 개발자 모드에서 고친 건물 **외형·위치**를 지도 파일에 굽는다.
//
//   dart run tool/bake_overrides.dart          # 바뀔 내용만 보여준다
//   dart run tool/bake_overrides.dart --write  # assets/housing/campus_traced.json에 쓴다
//
// 앱은 지도 파일(에셋)로 먼저 그리고 Firestore의 개발자 수정을 받아 다시
// 그린다. 수정이 쌓이면 그 차이가 매번 받아 와야 하는 몫이 되므로, 확정된
// 외형은 파일에 넣어 둔다. 구운 뒤에도 Firestore 수정 문서는 그대로 둔다 —
// 같은 모양을 한 번 더 덮을 뿐이라 화면은 달라지지 않고, 이름·색·가게·시세는
// 계속 거기서 온다.
//
// 굽는 것: 외곽선(customRing), 층수(floors), 삭제·병합된 건물 빼기,
// 직접 추가·병합한 건물(housing_custom_buildings) 넣기.
// 굽지 않는 것: 이름·구역·색·이름표 숨김·가게·시세(계속 Firestore에서 온다).
//
// ⚠️ campus_traced.json은 build_index로 다시 만들면 교내 21동 이름이 사라진다
// (CLAUDE.md). 이 도구는 파일을 다시 만들지 않고 건물 목록만 고친다.
import 'dart:convert';
import 'dart:io';

const _project = 'knue-mate';
const _apiKey = 'AIzaSyBRA5y_n7yZcthH8LWc7ivY2fn7O9lrHY4';
const _asset = 'assets/housing/campus_traced.json';

/// Firestore REST의 타입 붙은 값 → 평범한 Dart 값.
Object? _plain(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('integerValue')) return int.parse(v['integerValue'] as String);
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('timestampValue')) return v['timestampValue'];
  if (v.containsKey('arrayValue')) {
    final values = (v['arrayValue'] as Map)['values'] as List? ?? const [];
    return [for (final x in values) _plain(x as Map<String, dynamic>)];
  }
  if (v.containsKey('mapValue')) {
    final fields = (v['mapValue'] as Map)['fields'] as Map? ?? const {};
    return {for (final e in fields.entries) e.key as String: _plain(e.value as Map<String, dynamic>)};
  }
  return null;
}

Future<Map<String, Map<String, dynamic>>> _fetch(String collection) async {
  final client = HttpClient();
  final out = <String, Map<String, dynamic>>{};
  String? token;
  do {
    final uri = Uri.https('firestore.googleapis.com',
        '/v1/projects/$_project/databases/(default)/documents/$collection', {
      'pageSize': '300',
      'key': _apiKey,
      if (token != null) 'pageToken': token,
    });
    final res = await (await client.getUrl(uri)).close();
    final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    if (body['error'] != null) throw StateError('$collection: ${body['error']}');
    for (final d in (body['documents'] as List? ?? const [])) {
      final m = d as Map<String, dynamic>;
      final id = (m['name'] as String).split('/').last;
      final fields = m['fields'] as Map<String, dynamic>? ?? const {};
      out[id] = {for (final e in fields.entries) e.key: _plain(e.value as Map<String, dynamic>)};
    }
    token = body['nextPageToken'] as String?;
  } while (token != null);
  client.close();
  return out;
}

double _r1(num v) => (v * 10).roundToDouble() / 10;

/// 외곽선: {x,y} 맵이나 옛 [x,y] 둘 다 읽고, 에셋처럼 닫힌 모양으로 만든다.
List<List<double>>? _ring(Object? raw) {
  if (raw is! List) return null;
  final pts = <List<double>>[];
  for (final p in raw) {
    if (p is Map && p['x'] is num && p['y'] is num) {
      pts.add([_r1(p['x'] as num), _r1(p['y'] as num)]);
    } else if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
      pts.add([_r1(p[0] as num), _r1(p[1] as num)]);
    }
  }
  if (pts.length < 3) return null;
  final first = pts.first, last = pts.last;
  if (first[0] != last[0] || first[1] != last[1]) pts.add([...first]);
  return pts;
}

bool _gone(Map<String, dynamic>? o) {
  if (o == null) return false;
  final merged = o['mergedWith'];
  return o['isDeleted'] == true || (merged is String && merged.isNotEmpty);
}

Future<void> main(List<String> args) async {
  final write = args.contains('--write');
  final overrides = await _fetch('housing_building_overrides');
  final custom = await _fetch('housing_custom_buildings');

  final raw = File(_asset).readAsStringSync();
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final buildings = (data['buildings'] as List).cast<Map<String, dynamic>>();

  var removed = 0, reshaped = 0, refloored = 0, added = 0;
  final out = <Map<String, dynamic>>[];
  for (final b in buildings) {
    final o = overrides[b['id']];
    if (_gone(o)) {
      removed++;
      continue;
    }
    final ring = _ring(o?['customRing']);
    if (ring != null && jsonEncode(ring) != jsonEncode(b['ring'])) {
      b['ring'] = ring;
      reshaped++;
    }
    final floors = o?['floors'];
    if (floors is int && floors >= 1 && floors != b['floors']) {
      b['floors'] = floors;
      refloored++;
    }
    out.add(b);
  }

  // 합친 건물은 원래 조각(mergedWith로 가리키는 건물)의 교내 여부·용도를
  // 이어받는다(lib/housing_service.dart의 mergedCampusTraits와 같은 규칙).
  final partsOf = <String, List<Map<String, dynamic>>>{};
  for (final b in buildings) {
    final target = overrides[b['id']]?['mergedWith'];
    if (target is String && target.isNotEmpty) (partsOf[target] ??= []).add(b);
  }
  Map<String, dynamic> campusTraits(String id) {
    final campus = [for (final p in partsOf[id] ?? const <Map<String, dynamic>>[]) if (p['campus'] == true) p];
    if (campus.isEmpty) return const {};
    final counts = <String, int>{};
    for (final p in campus) {
      final u = p['use'];
      if (u is String) counts[u] = (counts[u] ?? 0) + 1;
    }
    String? best;
    for (final e in counts.entries) {
      if (best == null || e.value > counts[best]!) best = e.key;
    }
    return {'campus': true, if (best != null) 'use': best};
  }

  final have = {for (final b in out) b['id']};
  final ids = custom.keys.toList()..sort();
  for (final id in ids) {
    if (have.contains(id)) continue;
    final c = custom[id]!;
    final o = overrides[id];
    if (_gone(o)) continue;
    final ring = _ring(o?['customRing']) ?? _ring(c['ring']);
    if (ring == null) continue;
    final floors = (o?['floors'] is int && (o!['floors'] as int) >= 1) ? o['floors'] : (c['floors'] ?? 3);
    final traits = campusTraits(id);
    out.add({
      'id': id,
      if (c['name'] is String) 'name': c['name'],
      'floors': floors,
      if (c['use'] is String) 'use': c['use'] else if (traits['use'] != null) 'use': traits['use'],
      'campus': c['isCampus'] == true || traits['campus'] == true,
      if (c['road'] is String) 'road': c['road'],
      if (c['buildingNo'] is String) 'bno': c['buildingNo'],
      'ring': ring,
    });
    added++;
  }

  stdout.writeln('수정 문서 ${overrides.length}개 · 추가 건물 ${custom.length}개');
  stdout.writeln('건물 ${buildings.length} → ${out.length}동: '
      '빼기 $removed · 모양 $reshaped · 층수 $refloored · 넣기 $added');

  if (!write) {
    stdout.writeln('(--write 없이 돌려 파일은 그대로다)');
    return;
  }
  data['buildings'] = out;
  // 저장소의 파일과 같은 모양(들여쓰기 2칸, 끝 줄바꿈 없음)으로 써서 바뀐
  // 건물만 diff에 나오게 한다.
  File(_asset).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  stdout.writeln('→ $_asset');
}
