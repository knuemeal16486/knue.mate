// 사진에서 뽑은 기하(tool/mapsrc/traced_raw.json)에 이름·층수·용도·id를 붙여
// 최종 에셋 assets/housing/campus_traced.json 을 만든다.
//
// 자료 출처 원칙 (사용자가 정한 것):
//   교내 건물·도로   → 사진(캡처)
//   부지 밖 건물     → VWorld 지적. 사진에서 뽑으면 흐리게 그려진 구역을 놓쳐
//                      원룸이 통째로 사라지고 모양도 뭉개진다.
//   부지 밖 도로·녹지 → 사진 + VWorld 병합 (tool/trace_map.dart에서 합친다)
//
// VWorld는 그 밖에도 두 가지에 쓴다:
//  - id·도로명주소: 원룸 시세 제보가 `HousingReport.buildingId`로 Firestore에
//    묶여 있다(lib/housing_service.dart). 사진 기하로 갈아끼우면서 id를 새로
//    만들면 기존 제보가 통째로 끊긴다. 그래서 겹치는 VWorld 건물의 id를 물려받고,
//    한 바닥면에 여러 동이 겹치면 나머지는 alias로 남긴다.
//  - 층수: 부지 안은 앱이 가진 실제 층수(knue_buildings.json)로 덮는다.
//    VWorld는 연면적 800㎡ 넘는 39동 중 32동을 "1층"으로 준다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'map_trace_lib.dart' as mt;

/// 용도 — 지붕 색이 여기서 갈린다.
const purpose = <String, String>{
  '대학본부': 'admin', '관리동': 'admin', '교수회관': 'admin',
  '대학원': 'academic', '종합교육관': 'academic', '인문과학관': 'academic',
  '교양학관': 'academic', '교육연구관': 'academic', '자연과학관': 'academic',
  '융합과학관': 'academic', '응용과학관': 'academic',
  '미래도서관': 'library',
  '제1학생회관': 'student', '제2학생회관': 'student', '복지관': 'student',
  '호연관': 'dorm', '함덕당': 'dorm', '함인당': 'dorm', '다정관': 'dorm',
  '다감관': 'dorm', '교수아파트': 'dorm',
  '체육관': 'sports', '학군단': 'sports',
  '음악관': 'culture', '미술관': 'culture', '교원문화관': 'culture',
  '교육박물관': 'culture', '연수원 문화관': 'culture',
  '교원연수관': 'training', '국제연수관': 'training',
  '부설고': 'affiliate', '부설유치원': 'affiliate', '황새생태연구원': 'affiliate',
};

/// knue_buildings.json에 층 정보가 없는 동의 대타.
const floorFallback = <String, int>{
  '대학원': 4, '교수회관': 3, '관리동': 3, '복지관': 3, '음악관': 3,
  '교원문화관': 3, '교육박물관': 2, '함덕당': 5, '교원연수관': 5,
  '국제연수관': 5, '함인당': 5, '학군단': 2, '부설고': 4, '응용과학관': 4,
  '연수원 문화관': 3, '부설유치원': 2, '황새생태연구원': 2, '교수아파트': 5,
  '다정관': 12, '다감관': 11,
};


/// 캡처에 찍힌 네이버 라벨을 옮겨 적은 것. 좌표는 라벨 글자의 중심을
/// 월드로 환산한 값이다(배율 0.619, 캡처별 평행이동).
///
/// building_data.dart의 위경도와 달리 **계통 오차 보정이 필요 없다** —
/// 이미 캡처와 같은 좌표계이고, 실제로 겹치는 이름(교육박물관·교원문화관 등)으로
/// 대조해 보니 라벨이 건물 중심에서 5m 안쪽에 찍힌다.
const labelSeeds = <String, List<double>>{
  '기계실': [156.6, 291.3],
  '청람천문대': [516.8, 282.1],
  '총장공관': [262.6, 400.0],
  '제1대학': [564.5, 19.0],
  '제2대학': [473.5, -109.8],
  '제3대학': [637.4, 105.0],
  '제4대학': [609.7, 233.8],
  '제1체육관': [711.8, -85.0],
  '제2체육관': [732.2, -103.0],
};

/// 라벨로만 얻은 이름의 용도·층수. 캡처에 층수는 안 나오니 규모로 잡는다.
const labelPurpose = <String, String>{
  '기계실': 'etc', '청람천문대': 'culture', '총장공관': 'admin',
  '제1대학': 'academic', '제2대학': 'academic', '제3대학': 'academic',
  '제4대학': 'academic', '제1체육관': 'sports', '제2체육관': 'sports',
};
const labelFloors = <String, int>{
  '기계실': 2, '청람천문대': 2, '총장공관': 2,
  '제1대학': 4, '제2대학': 4, '제3대학': 4, '제4대학': 3,
  '제1체육관': 2, '제2체육관': 2,
};

List<List<double>> asRing(dynamic r) => [
      for (final p in r) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
    ];

double area(List<List<double>> r) {
  var s = 0.0;
  for (var i = 0; i < r.length; i++) {
    final a = r[i], b = r[(i + 1) % r.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return s.abs() / 2;
}

List<double> center(List<List<double>> r) {
  var a = 1e9, b = -1e9, c = 1e9, d = -1e9;
  for (final p in r) {
    a = math.min(a, p[0]);
    b = math.max(b, p[0]);
    c = math.min(c, p[1]);
    d = math.max(d, p[1]);
  }
  return [(a + b) / 2, (c + d) / 2];
}

bool pip(List<List<double>> ring, double x, double y) {
  var t = false;
  for (var i = 0, k = ring.length - 1; i < ring.length; k = i++) {
    final a = ring[i], b = ring[k];
    if ((a[1] > y) != (b[1] > y) &&
        x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) {
      t = !t;
    }
  }
  return t;
}

double median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

double _r1(double v) => (v * 10).roundToDouble() / 10;

void main() {
  final raw = jsonDecode(File('tool/mapsrc/traced_raw.json').readAsStringSync());
  final base =
      jsonDecode(File('assets/housing/campus_base.json').readAsStringSync());
  final knue =
      jsonDecode(File('assets/buildings/knue_buildings.json').readAsStringSync());
  final meta = (jsonDecode(File('tool/mapsrc/meta_pos.json').readAsStringSync())
          as Map<String, dynamic>)
      .map((k, v) =>
          MapEntry(k, [(v[0] as num).toDouble(), (v[1] as num).toDouble()]));

  final outline = asRing(raw['outline'][0]);
  var rings = [for (final r in raw['buildings']) asRing(r)];
  rings = applyManualFixes(rings);
  final centers = [for (final r in rings) center(r)];
  final areas = [for (final r in rings) area(r)];
  final isCampus = [
    for (final c in centers) pip(outline, c[0], c[1])
  ];
  final nCampus = isCampus.where((v) => v).length;
  stdout.writeln('사진에서 뽑은 건물 ${rings.length}동 '
      '(교내 $nCampus, 교외 ${rings.length - nCampus})');

  // ── 실제 층수 ──
  final realFloors = <String, int>{};
  for (final b in knue['buildings']) {
    var maxF = 0;
    for (final f in (b['floors'] as List)) {
      final m = RegExp(r'(\d+)\s*F').firstMatch('${f['floor']}');
      if (m != null) maxF = math.max(maxF, int.parse(m.group(1)!));
    }
    if (maxF > 0) realFloors[b['name']] = maxF;
  }

  // ── 이름 배정 (교내만) ──
  // building_data.dart의 위경도는 실측 대비 계통 오차가 있다. 중앙값으로
  // 먼저 오차를 재고 보정한 뒤 1:1로 짝짓는다.
  final dxs = <double>[], dys = <double>[];
  meta.forEach((name, p) {
    var best = 1e9, bi = -1;
    for (var i = 0; i < centers.length; i++) {
      if (!isCampus[i]) continue;
      final d = math.sqrt(math.pow(centers[i][0] - p[0], 2) +
          math.pow(centers[i][1] - p[1], 2));
      if (d < best) {
        best = d;
        bi = i;
      }
    }
    if (bi >= 0 && best < 55) {
      dxs.add(centers[bi][0] - p[0]);
      dys.add(centers[bi][1] - p[1]);
    }
  });
  final offX = median(dxs), offY = median(dys);
  stdout.writeln('building_data.dart 계통 오차 '
      'dx ${offX.toStringAsFixed(1)}m dy ${offY.toStringAsFixed(1)}m '
      '(표본 ${dxs.length}동)');

  final pairs = <List<dynamic>>[];
  meta.forEach((name, p) {
    final x = p[0] + offX, y = p[1] + offY;
    for (var i = 0; i < centers.length; i++) {
      if (!isCampus[i]) continue;
      final d = math.sqrt(
          math.pow(centers[i][0] - x, 2) + math.pow(centers[i][1] - y, 2));
      if (d < 60) pairs.add([d, name, i]);
    }
  });
  pairs.sort((a, b) => (a[0] as double).compareTo(b[0] as double));
  final tookName = <String>{}, tookIdx = <int>{};
  final nameOf = <int, String>{};
  for (final p in pairs) {
    final name = p[1] as String, i = p[2] as int;
    if (tookName.contains(name) || tookIdx.contains(i)) continue;
    tookName.add(name);
    tookIdx.add(i);
    nameOf[i] = name;
  }
  // 캡처 라벨로 이름을 더 붙인다. 보정 없이 그대로 쓰되, 폴리곤이 라벨을
  // 담고 있으면 우선하고 아니면 35m 안 최근접으로 간다.
  final labelPairs = <List<dynamic>>[];
  labelSeeds.forEach((name, p) {
    for (var i = 0; i < centers.length; i++) {
      if (!isCampus[i]) continue;
      final d = math.sqrt(math.pow(centers[i][0] - p[0], 2) +
          math.pow(centers[i][1] - p[1], 2));
      if (d > 35) continue;
      labelPairs.add([pip(rings[i], p[0], p[1]) ? d - 100 : d, name, i]);
    }
  });
  labelPairs.sort((a, b) => (a[0] as double).compareTo(b[0] as double));
  var fromLabel = 0;
  for (final p in labelPairs) {
    final name = p[1] as String, i = p[2] as int;
    if (tookName.contains(name) || tookIdx.contains(i)) continue;
    tookName.add(name);
    tookIdx.add(i);
    nameOf[i] = name;
    fromLabel++;
  }
  stdout.writeln('캡처 라벨로 추가 배정 $fromLabel동');

  final missed = meta.keys.where((k) => !tookName.contains(k)).toList();
  stdout.writeln('이름 배정 ${nameOf.length}/${meta.length}동'
      '${missed.isEmpty ? "" : " — 실패: ${missed.join(", ")}"}');

  // ── VWorld id 승계 ──
  // 사진 바닥면 안에 중심이 들어오는 VWorld 건물을 모은다. 가장 큰 것이 대표,
  // 나머지는 alias로 남겨 옛 제보가 계속 붙게 한다.
  final vw = [
    for (final b in base['buildings'])
      {
        'id': b['id'] as String,
        'ring': asRing(b['ring']),
        'floors': (b['floors'] as num).toInt(),
        'road': b['road'],
        'no': b['no'],
      }
  ];
  for (final v in vw) {
    v['c'] = center(v['ring'] as List<List<double>>);
    v['a'] = area(v['ring'] as List<List<double>>);
  }
  final idOf = List<String?>.filled(rings.length, null);
  final vwOf = List<Map<String, dynamic>?>.filled(rings.length, null);
  final alias = <String, String>{};
  var inherited = 0;
  for (var i = 0; i < rings.length; i++) {
    final hits = <Map<String, dynamic>>[];
    for (final v in vw) {
      final c = v['c'] as List<double>;
      if (pip(rings[i], c[0], c[1])) hits.add(v);
    }
    if (hits.isEmpty) continue;
    hits.sort((a, b) => (b['a'] as double).compareTo(a['a'] as double));
    idOf[i] = hits.first['id'] as String;
    vwOf[i] = hits.first;
    inherited++;
    for (var k = 1; k < hits.length; k++) {
      alias[hits[k]['id'] as String] = hits.first['id'] as String;
    }
  }
  // 짝이 없으면 좌표에서 만든 결정적 id — 다시 돌려도 같은 값이 나온다
  for (var i = 0; i < rings.length; i++) {
    idOf[i] ??= 't${(centers[i][0] / 2).round()}_${(centers[i][1] / 2).round()}';
  }
  stdout.writeln('VWorld id 승계 $inherited동, alias ${alias.length}개');

  // ── 번호: 교내만. 이름 있는 동을 북→남, 나머지는 면적순 ──
  final campusIdx = [
    for (var i = 0; i < rings.length; i++)
      if (isCampus[i]) i
  ];
  final order = <int>[
    ...campusIdx.where(nameOf.containsKey).toList()
      ..sort((a, b) => centers[a][1].compareTo(centers[b][1])),
    ...campusIdx.where((i) => !nameOf.containsKey(i)).toList()
      ..sort((a, b) => areas[b].compareTo(areas[a])),
  ];
  final noOf = <int, int>{};
  for (var k = 0; k < order.length; k++) {
    noOf[order[k]] = k + 1;
  }

  // ── 최종 에셋 ──
  final buildings = <Map<String, dynamic>>[];
  for (var i = 0; i < rings.length; i++) {
    final name = nameOf[i];
    var fl = 0;
    if (isCampus[i]) {
      fl = name == null
          ? 0
          : (realFloors[name] ?? floorFallback[name] ?? labelFloors[name] ?? 0);
      if (fl == 0) {
        final a = areas[i];
        fl = a > 1500 ? 4 : (a > 800 ? 3 : (a > 400 ? 2 : 1));
      }
    } else {
      // 교외는 VWorld 층수를 그대로 쓴다. 원룸 판정(_looksLikeOneRoom)이
      // 층수 임계를 보므로 함부로 올리면 원룸이 아닌 것까지 원룸이 된다.
      fl = (vwOf[i]?['floors'] as int?) ?? 1;
    }
    buildings.add({
      'id': idOf[i],
      if (noOf[i] != null) 'no': noOf[i],
      if (name != null) 'name': name,
      'floors': fl,
      'use': isCampus[i]
          ? (purpose[name] ?? labelPurpose[name] ?? 'etc')
          : 'etc',
      'campus': isCampus[i],
      if (vwOf[i]?['road'] != null) 'road': vwOf[i]!['road'],
      if (vwOf[i]?['no'] != null) 'bno': vwOf[i]!['no'],
      'ring': [
        for (final p in rings[i]) [p[0], p[1]]
      ],
    });
  }

  // ── 부지 밖 건물: VWorld 지적을 그대로 ──
  // 사진에서 뽑던 시절엔 230동에 그쳤고(실제 305동) 흐린 구역 건물은 모양이
  // 뭉개졌다. 지적은 측량값이라 개수도 모양도 정확하다.
  final names = loadBuildingNames();
  var outsideCount = 0;
  var rescued = 0;
  var named = 0;
  for (final v in vw) {
    final c = v['c'] as List<double>;
    final road = v['road'] as String?;
    // 부지 안은 사진 몫 — 다만 **원룸촌 도로명이 붙어 있으면 예외**다.
    //
    // 외곽선이 월탄3길·월탄1길 일부를 넘어 그어져 있어서, 그대로 걸러내면
    // 그 골목 원룸 13동이 "사진 몫"으로 넘어갔다가 정작 사진 추출은 교내만
    // 하므로 아무도 그리지 않는다 — 지도에서 통째로 사라진다. 실제로
    // 아우름빌·등용문·그린캐슬·메이플빌·미소가·꿈터빌·청람드림빌 B/C 등이
    // 그렇게 빠져 있었다. 이 길들은 캠퍼스일 수가 없으니 이름으로 되살린다.
    if (!kResidentialRoads.contains(road) && pip(outline, c[0], c[1])) continue;
    if (kResidentialRoads.contains(road) && pip(outline, c[0], c[1])) rescued++;
    final r = v['ring'] as List<List<double>>;
    if (r.length < 3 || (v['a'] as double) < 12) continue;
    final no = v['no'] as String?;
    final byId = names['byId'] ?? const {};
    final byAddress = names['byAddress'] ?? const {};
    var name = byId[v['id']];
    if (name == null && road != null && no != null) {
      name = byAddress['$road $no'];
    }
    if (name != null) named++;
    buildings.add({
      'id': v['id'],
      if (name != null) 'name': name,
      'floors': math.max(1, v['floors'] as int),
      'use': 'etc',
      'campus': false,
      if (road != null) 'road': road,
      if (no != null) 'bno': no,
      'ring': [
        for (final p in r) [_r1(p[0]), _r1(p[1])]
      ],
    });
    outsideCount++;
  }
  stdout.writeln('부지 밖 건물 ${outsideCount}동 (VWorld 지적) '
      '— 외곽선에 삼켜졌다가 되살린 원룸 $rescued동, 이름 붙임 $named동');

  final out = <String, dynamic>{
    'note': '네이버지도 캡처에서 뽑은 지형. '
        'tool/trace_map.dart + tool/build_index.dart 가 생성한다. 직접 고치지 마라.',
    'origin': raw['origin'],
    'outline': raw['outline'],
    'buildings': buildings,
    'facilities': raw['facilities'],
    'parking': raw['parking'],
    'greens': raw['greens'],
    'greensOutside': raw['greensOutside'],
    'water': raw['water'],
    'major': raw['major'],
    'fieldLines': raw['fieldLines'],
    'pavement': raw['pavement'],
    'parkingStalls': raw['parkingStalls'],
    'crosswalks': raw['crosswalks'],
    'pois': raw['pois'],
    'alias': alias,
  };
  final f = File('assets/housing/campus_traced.json');
  f.writeAsStringSync(jsonEncode(out));
  stdout.writeln('→ assets/housing/campus_traced.json '
      '(${f.lengthSync() ~/ 1024} KB)');

  final md = StringBuffer('| 번호 | 이름 | 층 | 용도 | 바닥면적 |\n'
      '|---:|---|---:|---|---:|\n');
  final rows = [
    for (var i = 0; i < rings.length; i++)
      if (noOf[i] != null)
        [noOf[i]!, nameOf[i] ?? '—', buildings[i]['floors'], buildings[i]['use'],
          areas[i].round()]
  ]..sort((a, b) => (a[0] as int).compareTo(b[0] as int));
  for (final r in rows) {
    md.writeln('| ${r[0]} | ${r[1]} | ${r[2]} | ${r[3]} | ${r[4]}㎡ |');
  }
  File('tool/mapsrc/buildings.md').writeAsStringSync(md.toString());
  stdout.writeln('→ tool/mapsrc/buildings.md (교내 ${rows.length}동)');
}


/// 사람이 지도를 보고 짚어준 교정을 적용한다 (tool/mapsrc/manual_fixes.json).
///
/// 자동 추출은 한 건물을 여러 조각으로 쪼개기도 하고(네이버가 큰 건물 안에
/// 동 구분선을 긋는 탓), 건물이 아닌 것을 건물로 잡기도 한다. 사람 눈이
/// 제일 정확한 판정자라 그 결과를 데이터로 받아 적용한다.
///
/// 번호가 아니라 **좌표**로 맞춘다 — 통합·삭제하면 번호가 다시 매겨지므로
/// 번호로 저장하면 다음 실행에서 엉뚱한 건물을 건드린다.
/// 캠퍼스일 수 없는 주거지 도로. 부지 외곽선이 이 길들 일부를 넘어 그어져
/// 있어서, 외곽선만 믿고 거르면 멀쩡한 원룸이 지도에서 사라진다.
const kResidentialRoads = {
  '월탄1길',
  '월탄2길',
  '월탄3길',
  '다락탑연길',
  '황탄리길',
};

/// 사람이 조사해 넣은 건물 이름표(tool/mapsrc/building_names.json).
/// 파일이 없어도 생성은 그대로 돌아간다 — 이름만 안 붙는다.
Map<String, Map<String, String>> loadBuildingNames() {
  final f = File('tool/mapsrc/building_names.json');
  if (!f.existsSync()) return const {};
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  Map<String, String> section(String key) {
    final m = raw[key];
    if (m is! Map) return const {};
    return {
      for (final e in m.entries) e.key as String: e.value as String,
    };
  }

  return {'byAddress': section('byAddress'), 'byId': section('byId')};
}

List<List<List<double>>> applyManualFixes(List<List<List<double>>> rings) {
  final f = File('tool/mapsrc/manual_fixes.json');
  if (!f.existsSync()) return rings;
  final fx = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

  final centers = [for (final r in rings) center(r)];
  final used = <int>{};
  int? find(List at) {
    final x = (at[0] as num).toDouble(), y = (at[1] as num).toDouble();
    var best = -1;
    var bd = 6.0;
    for (var i = 0; i < centers.length; i++) {
      if (used.contains(i)) continue;
      final d = math.sqrt(math.pow(centers[i][0] - x, 2) +
          math.pow(centers[i][1] - y, 2));
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  final drop = <int>{};
  final merged = <List<List<double>>>[];
  var mergedN = 0, missing = 0;
  // 어느 항목이 아직 쓰이는지 찍어 둔다. 추출이 좋아지면 예전에 손으로
  // 이어 붙이던 조각이 애초에 안 생기므로 항목이 죽는다 — 그걸 모르면
  // 죽은 항목이 쌓여 "왜 안 먹지"를 반복하게 된다.
  final liveGroups = <String>[];
  var gi = -1;
  for (final g in (fx['merge'] as List)) {
    gi++;
    final idx = <int>[];
    for (final at in (g['at'] as List)) {
      final i = find(at);
      if (i == null) {
        missing++;
        continue;
      }
      used.add(i);
      idx.add(i);
    }
    if (idx.length < 2) continue;
    final u = unionRings([for (final i in idx) rings[i]]);
    if (u == null) continue;
    drop.addAll(idx);
    merged.add(u);
    mergedN++;
    liveGroups.add('$gi(${idx.length}조각)');
  }
  if (liveGroups.isNotEmpty) {
    stdout.writeln('  아직 쓰이는 merge 항목: ${liveGroups.join(', ')}');
  }
  var deleted = 0;
  for (final d in (fx['delete'] as List)) {
    final i = find(d['at'] as List);
    if (i == null) {
      missing++;
      continue;
    }
    used.add(i);
    drop.add(i);
    deleted++;
  }
  stdout.writeln('사람 교정: ${mergedN}그룹 통합, $deleted동 삭제'
      '${missing > 0 ? " (좌표로 못 찾은 것 $missing건)" : ""}');

  return [
    for (var i = 0; i < rings.length; i++)
      if (!drop.contains(i)) rings[i],
    ...merged,
  ];
}

/// 폴리곤 여럿을 하나로 합친다.
///
/// 격자에 찍어 합집합을 낸 뒤 외곽선을 다시 딴다. 붙어 있는 동 사이의 틈은
/// 닫기로 메운다 — 안 그러면 합쳐도 실금이 남아 두 덩어리로 나온다.
///
/// 마지막에 [mt.regularize]로 **직각으로 세운다**. 합집합 외곽선을 그대로
/// 쓰면 조각들의 계단이 그대로 남아 건물이 울퉁불퉁해 보인다.
List<List<double>>? unionRings(List<List<List<double>>> polys) {
  const res = 0.25;
  var mnx = 1e9, mny = 1e9, mxx = -1e9, mxy = -1e9;
  for (final r in polys) {
    for (final p in r) {
      mnx = math.min(mnx, p[0]);
      mxx = math.max(mxx, p[0]);
      mny = math.min(mny, p[1]);
      mxy = math.max(mxy, p[1]);
    }
  }
  const pad = 16; // 닫기 반경보다 넉넉히 — 도형이 격자 끝에 닿으면 안 된다
  final ox = mnx - pad * res, oy = mny - pad * res;
  final w = ((mxx - mnx) / res).ceil() + pad * 2;
  final h = ((mxy - mny) / res).ceil() + pad * 2;
  if (w < 4 || h < 4 || w * h > 40000000) return null;
  final m = mt.rasterize(polys, w, h, ox, oy, res);
  // 8셀 = 2m. 조각 사이 실금을 메우되 딴 건물까지 빨아들이진 않는 폭.
  final closed = mt.fillHoles(mt.closeM(m, 8));
  final loops = mt.traceSmooth(closed,
      blurR: 1, blurN: 1, round: 0, preEps: 4.0, minLoopArea: 40);
  if (loops.isEmpty) return null;
  final world = [
    for (final p in loops.first) mt.Pt(ox + p.x * res, oy + p.y * res)
  ];
  // 건물은 각져야 건물처럼 보인다.
  // 합친 건물도 각져야 한다. snapDeg 45 = 모든 변을 직각 격자에 세운다
  // (trace_map의 건물 추출과 같은 이유 — 거기 주석 참고).
  final reg = mt.regularize(world, snapDeg: 45, minEdge: 4.0, maxAreaDrift: 0.35);
  return [
    for (final p in reg) [(p.x * 10).roundToDouble() / 10, (p.y * 10).roundToDouble() / 10]
  ];
}
