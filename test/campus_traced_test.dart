// 캡처에서 뽑은 지형(assets/housing/campus_traced.json)이 아귀가 맞는지 지킨다.
//
// 검사하는 건 "값이 예쁜가"가 아니라 **다시 뽑았을 때 조용히 망가지지 않는가**다.
// tool/trace_map.dart 임계값을 건드리면 제일 먼저 여기서 걸린다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

late Map<String, dynamic> traced;
late Map<String, dynamic> vworld;

List<List<double>> ring(dynamic r) => [
      for (final p in r) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
    ];

List<List<List<double>>> rings(dynamic l) =>
    [for (final r in (l as List)) ring(r)];

List<List<List<double>>> pavementRings() {
  final pv = traced['pavement'] as Map<String, dynamic>;
  return [...rings(pv['outer']), ...rings(pv['holes'])];
}

List<List<List<double>>> campusBuildingRings() => [
      for (final b in (traced['buildings'] as List))
        if ((b as Map<String, dynamic>)['campus'] == true) ring(b['ring'])
    ];

/// 둘레 100m당 '급한 꺾임(45° 초과)' 개수.
///
/// 래스터 계단(톱니)은 90° 꺾임이 촘촘히 박히므로 이 값이 폭발한다.
/// 꼭짓점 수로 재면 안 된다 — 디테일이 살아나도 점은 늘기 때문에
/// 톱니와 구분이 안 된다.
double sharpPer100m(List<List<List<double>>> rs) {
  var sharp = 0;
  var per = 0.0;
  for (final r in rs) {
    if (r.length < 6) continue;
    for (var i = 0; i < r.length; i++) {
      final a = r[(i - 1 + r.length) % r.length], b = r[i];
      final c = r[(i + 1) % r.length];
      final v1x = b[0] - a[0], v1y = b[1] - a[1];
      final v2x = c[0] - b[0], v2y = c[1] - b[1];
      final l1 = math.sqrt(v1x * v1x + v1y * v1y);
      final l2 = math.sqrt(v2x * v2x + v2y * v2y);
      if (l1 < 1e-9 || l2 < 1e-9) continue;
      per += l2;
      final ang = math.atan2((v1x * v2y - v1y * v2x) / (l1 * l2),
              ((v1x * v2x + v1y * v2y) / (l1 * l2)).clamp(-1.0, 1.0)) *
          180 /
          math.pi;
      if (ang.abs() > 45) sharp++;
    }
  }
  return per <= 0 ? 0 : sharp / per * 100;
}

double ringArea(List<List<double>> r) {
  var s = 0.0;
  for (var i = 0; i < r.length; i++) {
    final a = r[i], b = r[(i + 1) % r.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return s.abs() / 2;
}

List<double> ringCenter(List<List<double>> r) {
  var a = 1e9, b = -1e9, c = 1e9, d = -1e9;
  for (final p in r) {
    a = math.min(a, p[0]);
    b = math.max(b, p[0]);
    c = math.min(c, p[1]);
    d = math.max(d, p[1]);
  }
  return [(a + b) / 2, (c + d) / 2];
}

bool inside(List<List<double>> r, List<double> p) {
  var t = false;
  for (var i = 0, k = r.length - 1; i < r.length; k = i++) {
    final a = r[i], b = r[k];
    if ((a[1] > p[1]) != (b[1] > p[1]) &&
        p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]) {
      t = !t;
    }
  }
  return t;
}

void main() {
  setUpAll(() {
    traced = jsonDecode(
        File('assets/housing/campus_traced.json').readAsStringSync());
    vworld =
        jsonDecode(File('assets/housing/campus_base.json').readAsStringSync());
  });

  group('캠퍼스 부지 경계', () {
    test('폴리곤이 하나이고 면적이 교원대 규모다', () {
      final out = rings(traced['outline']);
      expect(out, hasLength(1));
      final ha = ringArea(out.first) / 10000;
      // 한국교원대 본교 부지는 대략 70~90ha다. 크게 벗어나면 학교용지 색
      // 판정이 원룸촌이나 논밭까지 삼킨 것이다.
      expect(ha, greaterThan(60));
      expect(ha, lessThan(100));
    });
  });

  group('건물', () {
    test('교내·교외가 모두 있다', () {
      final b = traced['buildings'] as List;
      final campus = b.where((e) => e['campus'] == true).length;
      // 자동 추출은 108동이었는데, 사람이 지도를 보고 22그룹을 하나로 합치고
      // 5동을 지워 54동이 됐다(tool/mapsrc/manual_fixes.json).
      // 네이버가 큰 건물 안에 동 구분선을 그어 한 건물이 조각나 있었다.
      expect(campus, greaterThanOrEqualTo(45));
      expect(b.length - campus, greaterThanOrEqualTo(150));
    });

    test('id가 겹치지 않는다', () {
      final ids = (traced['buildings'] as List).map((e) => e['id']).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('교내 번호가 1..N 중복 없이 매겨져 있다', () {
      final nos = (traced['buildings'] as List)
          .where((e) => e['no'] != null)
          .map((e) => e['no'] as int)
          .toList()
        ..sort();
      expect(nos, List.generate(nos.length, (i) => i + 1));
    });

    test('교내 건물이 전부 부지 안이다', () {
      final out = rings(traced['outline']).first;
      for (final b in (traced['buildings'] as List)) {
        if (b['campus'] != true) continue;
        expect(inside(out, ringCenter(ring(b['ring']))), isTrue,
            reason: '${b['no']}번이 부지 밖');
      }
    });

    test('주요 건물의 층수가 실제와 맞다', () {
      // VWorld는 이것들을 전부 "1층"으로 준다. 실제 값으로 덮고 있는지 본다.
      const expected = {
        '대학본부': 6, '종합교육관': 7, '미래도서관': 6, '교육연구관': 6,
        '융합과학관': 5, '인문과학관': 4, '자연과학관': 4, '교양학관': 4,
        '제1학생회관': 3, '미술관': 3, '체육관': 3,
        // 제2학생회관은 뺐다 — 사람 교정에서 제1학생회관과 한 건물로 합쳐져
        // 이름이 하나만 남는다.
      };
      for (final e in expected.entries) {
        final b = (traced['buildings'] as List).where((x) => x['name'] == e.key);
        expect(b, isNotEmpty, reason: '${e.key}이(가) 없다');
        expect(b.first['floors'], e.value, reason: e.key);
      }
    });

    test('서로 겹치지 않는다', () {
      // 예전엔 요소마다 따로 부풀려 붙어 있는 동끼리 6m씩 포개졌다. 지금은
      // 씨앗을 심고 영역을 나눠 갖게 해서 한 셀이 한 동에만 속한다.
      final polys = [
        for (final b in (traced['buildings'] as List)) ring(b['ring'])
      ];
      const cell = 1.0;
      var mnx = 1e9, mny = 1e9, mxx = -1e9, mxy = -1e9;
      for (final r in polys) {
        for (final p in r) {
          mnx = math.min(mnx, p[0]);
          mxx = math.max(mxx, p[0]);
          mny = math.min(mny, p[1]);
          mxy = math.max(mxy, p[1]);
        }
      }
      final w = ((mxx - mnx) / cell).ceil() + 2;
      final h = ((mxy - mny) / cell).ceil() + 2;
      final hits = List<int>.filled(w * h, 0);
      var painted = 0, dup = 0;
      for (final r in polys) {
        for (var j = 0; j < h; j++) {
          final yw = mny + j * cell;
          final xs = <double>[];
          for (var i = 0; i < r.length; i++) {
            final a = r[i], b = r[(i + 1) % r.length];
            if ((a[1] <= yw) != (b[1] <= yw)) {
              xs.add(a[0] + (yw - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
            }
          }
          xs.sort();
          for (var k = 0; k + 1 < xs.length; k += 2) {
            for (var i = ((xs[k] - mnx) / cell).ceil();
                i <= ((xs[k + 1] - mnx) / cell).floor();
                i++) {
              if (i < 0 || i >= w) continue;
              painted++;
              if (hits[j * w + i]++ > 0) dup++;
            }
          }
        }
      }
      // 격자 반올림 때문에 맞닿은 경계 한 줄은 겹칠 수 있다.
      expect(dup / painted, lessThan(0.01),
          reason: '겹친 면적 ${(dup * 100 / painted).toStringAsFixed(2)}%');
    });

    test('한 건물이라기엔 지나치게 큰 덩어리가 없다', () {
      for (final b in (traced['buildings'] as List)) {
        expect(ringArea(ring(b['ring'])), lessThan(8000),
            reason: '${b['id']}가 너무 크다 — 여러 동이 뭉쳤다');
      }
    });
  });

  group('원룸 제보 링크', () {
    test('부지 밖 건물은 전부 VWorld 지적이다', () {
      // 사진에서 뽑던 시절엔 230동에 그쳤고(실제 305동) 흐린 구역 건물은
      // 모양이 뭉개졌다. 부지 밖은 지적을 쓴다 — 사용자가 정한 원칙이다.
      final vwIds = {for (final b in (vworld['buildings'] as List)) b['id']};
      final outside =
          (traced['buildings'] as List).where((b) => b['campus'] != true);
      expect(outside.length, greaterThanOrEqualTo(400));
      for (final b in outside) {
        expect(vwIds.contains(b['id']), isTrue,
            reason: '${b['id']}는 지적에 없는 id다');
      }
    });

    test('예전 사진 기반 id 승계도 남아 있다', () {
      // HousingReport.buildingId가 Firestore에 이 id로 저장돼 있다.
      // 사진 기하로 갈아끼우면서 id가 바뀌면 기존 제보가 전부 끊긴다.
      final vwIds = {for (final b in (vworld['buildings'] as List)) b['id']};
      final inherited = (traced['buildings'] as List)
          .where((b) => b['campus'] != true && vwIds.contains(b['id']))
          .length;
      expect(inherited, greaterThanOrEqualTo(100));
    });

    test('alias가 가리키는 곳이 실제로 존재한다', () {
      final ids = {for (final b in (traced['buildings'] as List)) b['id']};
      (traced['alias'] as Map).forEach((from, to) {
        expect(ids.contains(to), isTrue, reason: '$from → $to 가 없다');
      });
    });
  });

  group('바닥 레이어', () {
    test('포장면이 원룸촌까지 덮는다', () {
      final pave = traced['pavement'] as Map<String, dynamic>;
      final area =
          rings(pave['outer']).fold<double>(0, (a, r) => a + ringArea(r)) -
              rings(pave['holes']).fold<double>(0, (a, r) => a + ringArea(r));
      // 부지 안만 뽑던 시절엔 15만㎡였다. 전 범위면 그보다 커야 한다.
      expect(area, greaterThan(160000));
    });

    test('운동시설·녹지·주차장이 있다', () {
      expect((traced['facilities'] as List).length, greaterThanOrEqualTo(5));
      expect((traced['greens'] as List).length, greaterThanOrEqualTo(8));
      expect((traced['parking'] as List).length, greaterThanOrEqualTo(8));
    });

    test('대운동장 블록이 400m 트랙 규모다', () {
      final big = rings(traced['facilities'])
          .map(ringArea)
          .reduce((a, b) => a > b ? a : b);
      expect(big, greaterThan(11000));
      expect(big, lessThan(20000));
    });

    test('국도가 잡혔다', () {
      expect((traced['major'] as List), isNotEmpty);
    });
  });

  group('도로 곧기', () {
    // 도로가 구불구불하던 걸 잡고 나서, 다시 나빠지면 여기서 걸리게 한다.
    // 지표: 이웃한 두 꺾임이 **반대 방향이고 둘 다 45° 미만**이면 지그재그다.
    // 진짜 곡선은 한 방향으로 꾸준히 돌고, 진짜 모서리는 크게 한 번 꺾인다.
    test('지그재그율이 낮다', () {
      final pv = traced['pavement'] as Map<String, dynamic>;
      final rs = [...rings(pv['outer']), ...rings(pv['holes'])];
      var zig = 0, pairs = 0;
      for (final r in rs) {
        if (r.length < 8) continue;
        var len = 0.0;
        for (var i = 0; i < r.length; i++) {
          final j = (i + 1) % r.length;
          len += math.sqrt(math.pow(r[j][0] - r[i][0], 2) +
              math.pow(r[j][1] - r[i][1], 2));
        }
        if (len < 40) continue;
        double turn(int i) {
          final a = r[(i - 1 + r.length) % r.length], b = r[i];
          final c = r[(i + 1) % r.length];
          final v1x = b[0] - a[0], v1y = b[1] - a[1];
          final v2x = c[0] - b[0], v2y = c[1] - b[1];
          final l1 = math.sqrt(v1x * v1x + v1y * v1y);
          final l2 = math.sqrt(v2x * v2x + v2y * v2y);
          if (l1 < 1e-6 || l2 < 1e-6) return 0;
          return math.atan2((v1x * v2y - v1y * v2x) / (l1 * l2),
                  ((v1x * v2x + v1y * v2y) / (l1 * l2)).clamp(-1.0, 1.0)) *
              180 /
              math.pi;
        }

        for (var i = 0; i < r.length; i++) {
          final a = turn(i), b = turn((i + 1) % r.length);
          if (a.abs() < 1 || b.abs() < 1) continue;
          pairs++;
          if (a * b < 0 && a.abs() < 45 && b.abs() < 45) zig++;
        }
      }
      // 실측 14.5%. 20%를 넘으면 굽이가 다시 생긴 것이다.
      expect(zig / pairs, lessThan(0.20),
          reason: '지그재그 ${(zig * 100 / pairs).toStringAsFixed(1)}%');
    });

    test('변이 잘게 쪼개져 있지 않다', () {
      final pv = traced['pavement'] as Map<String, dynamic>;
      final lens = <double>[];
      for (final r in [...rings(pv['outer']), ...rings(pv['holes'])]) {
        for (var i = 0; i < r.length; i++) {
          final j = (i + 1) % r.length;
          lens.add(math.sqrt(math.pow(r[j][0] - r[i][0], 2) +
              math.pow(r[j][1] - r[i][1], 2)));
        }
      }
      lens.sort();
      // 모서리 깎기를 켰을 땐 중앙 2.2m까지 잘게 쪼개졌다. 실측 3.4m.
      //
      // 예전엔 6m대라 하한이 3.5였는데, 그건 세게 흐려서 얻은 값이었다.
      // 흐림을 걷고 충실도를 올리면서 변이 짧아진 것은 **디테일이 살아난
      // 결과**이므로 하한만 지키고(계단이 살아나면 1m대로 떨어진다)
      // 울퉁불퉁함은 아래 톱니 검사로 따로 본다.
      expect(lens[lens.length ~/ 2], greaterThan(2.5));
    });

    test('톱니(계단)가 남아 있지 않다', () {
      // 둘레 100m당 '급한 꺾임(45° 초과)' 개수. 래스터 계단은 90° 꺾임이
      // 촘촘히 박히므로 이 값이 폭발한다. 지그재그율(45° 미만 반대방향)로는
      // 계단이 잡히지 않아 따로 둔다 — 실제로 건물 쪽에서 33%가 톱니인데도
      // 지그재그 검사는 멀쩡히 통과했다.
      expect(sharpPer100m(pavementRings()), lessThan(16),
          reason: '포장면 ${sharpPer100m(pavementRings()).toStringAsFixed(1)}'
              '개/100m (실측 10.7)');
      expect(sharpPer100m(campusBuildingRings()), lessThan(18),
          reason: '교내 건물 '
              '${sharpPer100m(campusBuildingRings()).toStringAsFixed(1)}'
              '개/100m (실측 11.2)');
    });
  });

  group('사람 교정', () {
    // tool/mapsrc/manual_fixes.json이 조용히 안 먹으면 지도가 조각난 채로
    // 돌아간다. 좌표로 맞추는 방식이라 추출 임계값을 건드리면 못 찾을 수 있다.
    test('통합·삭제가 실제로 적용됐다', () {
      final fx = jsonDecode(
          File('tool/mapsrc/manual_fixes.json').readAsStringSync());
      final campus =
          (traced['buildings'] as List).where((b) => b['campus'] == true);
      final before = (fx['merge'] as List)
              .fold<int>(0, (a, g) => a + (g['at'] as List).length) +
          (fx['delete'] as List).length;
      // 통합 전 108동에서 71동이 22개로, 5동은 삭제 → 54동
      expect(before, greaterThan(60));
      expect(campus.length, lessThan(70));
    });

    test('통합된 건물이 각져 있다', () {
      // 합집합 외곽선을 그대로 쓰면 조각들의 계단이 남아 울퉁불퉁하다.
      // regularize로 직각을 세우면 점이 확 준다 — 그게 각졌다는 증거다.
      //
      // 각도 정렬률(주 방향에 붙은 변의 비율)로 재려다 접었다. 날개가 서로
      // 다른 각도인 복합건물은 각져도 낮게 나와서 잣대가 안 된다.
      var worst = 0, worstNo = 0;
      for (final b in (traced['buildings'] as List)) {
        if (b['campus'] != true) continue;
        final n = (b['ring'] as List).length;
        if (n > worst) {
          worst = n;
          worstNo = (b['no'] as int?) ?? 0;
        }
      }
      // 꼭짓점 수는 "각졌나"의 잣대가 못 된다 — 흐림을 걷어 디테일을 살리면
      // 각져 있어도 점이 는다(실측 최대 40점대 → 122점). 울퉁불퉁함은
      // 위의 톱니 검사가 보고, 여기서는 **터무니없이 쪼개지지 않았는지만**
      // 본다.
      expect(worst, lessThan(220), reason: '$worstNo번 점 $worst개');
    });
  });

  group('부지 밖 병합', () {
    test('녹지에 안팎 구분이 달려 있다', () {
      final g = traced['greens'] as List;
      final o = traced['greensOutside'] as List;
      expect(o.length, g.length);
      expect(o.where((v) => v == true).length, greaterThan(5));
      expect(o.where((v) => v != true).length, greaterThan(5));
    });

    test('포장면이 지적 도로까지 합쳐 넓어졌다', () {
      final pave = traced['pavement'] as Map<String, dynamic>;
      final area =
          rings(pave['outer']).fold<double>(0, (a, r) => a + ringArea(r)) -
              rings(pave['holes']).fold<double>(0, (a, r) => a + ringArea(r));
      // 사진만 쓰던 시절 21만㎡ → 지적 도로 8만㎡를 더해 30만㎡ 가까이.
      expect(area, greaterThan(250000));
    });
  });

  group('디테일', () {
    test('POI가 종류별로 잡혔다', () {
      final kinds = <String, int>{};
      for (final p in (traced['pois'] as List)) {
        kinds[p['k'] as String] = (kinds[p['k'] as String] ?? 0) + 1;
      }
      expect(kinds['parking'] ?? 0, greaterThanOrEqualTo(5));
      expect(kinds.length, greaterThanOrEqualTo(2));
    });

    test('횡단보도 수가 터무니없지 않다', () {
      // 조건을 느슨하게 뒀을 때 연석·화단까지 360개가 잡힌 적이 있다.
      final n = (traced['crosswalks'] as List).length;
      expect(n, greaterThan(5));
      expect(n, lessThan(200));
    });

    test('주차 구획선이 방향·간격을 갖고 있다', () {
      for (final s in (traced['parkingStalls'] as List)) {
        expect((s['p'] as num).toDouble(), greaterThan(1.2));
        expect((s['p'] as num).toDouble(), lessThan(6.0));
        expect((s['i'] as num).toInt(),
            lessThan((traced['parking'] as List).length));
      }
    });
  });

  group('조사해 넣은 건물 이름', () {
    // tool/mapsrc/building_names.json 의 값이 실제로 지도 데이터에 구워졌는지.
    // 도로명주소가 바뀌거나 생성기가 이름 단계를 건너뛰면 여기서 걸린다.
    Map<String, dynamic> namesJson() => jsonDecode(
        File('tool/mapsrc/building_names.json').readAsStringSync());

    Map<String, String> byAddressInMap() {
      final got = <String, String>{};
      for (final b in (traced['buildings'] as List)) {
        final m = b as Map<String, dynamic>;
        if (m['name'] == null || m['road'] == null || m['bno'] == null) {
          continue;
        }
        got['${m['road']} ${m['bno']}'] = m['name'] as String;
      }
      return got;
    }

    test('byAddress에 적은 이름이 전부 붙었다', () {
      final want = (namesJson()['byAddress'] as Map).cast<String, String>();
      final got = byAddressInMap();
      final missing = [
        for (final e in want.entries)
          if (got[e.key] != e.value) '${e.key}=${e.value}'
      ];
      expect(missing, isEmpty, reason: '지도에 안 붙은 이름: $missing');
    });

    test('byId로 짚은 건물도 전부 붙었다', () {
      // 같은 도로명주소에 여러 동이 있어 주소로는 못 가리는 것들.
      final want = (namesJson()['byId'] as Map).cast<String, String>();
      final got = {
        for (final b in (traced['buildings'] as List))
          (b as Map<String, dynamic>)['id'] as String: b['name']
      };
      for (final e in want.entries) {
        expect(got[e.key], e.value, reason: 'id ${e.key}');
      }
    });

    test('원룸촌 도로 건물이 부지 외곽선에 삼켜지지 않는다', () {
      // build_index가 "부지 안"이라는 이유로 걸러내던 자리다. 외곽선이
      // 월탄3길·월탄1길 일부를 넘어 그어져 있어 원룸 13동이 통째로
      // 사라졌었다 — 이름을 붙여도 그릴 건물이 없으면 소용없다.
      const rescued = {
        '월탄3길 48-2': '아우름빌',
        '월탄3길 48-3': '등용문',
        '월탄3길 48-4': '그린캐슬',
        '월탄3길 40-6': '메이플빌',
        '월탄3길 36-6': '미소가',
        '월탄3길 32-13': '꿈터빌',
        '월탄3길 20-8': '청람드림빌 B',
        '월탄3길 20-12': '청람드림빌 C',
      };
      final got = byAddressInMap();
      for (final e in rescued.entries) {
        expect(got[e.key], e.value, reason: '${e.key} 가 빠졌다');
      }
    });

    test('교외 건물은 번호나 이름 중 하나는 갖는다', () {
      // 지도 이름표가 빈 캡슐로 뜨는 걸 막는다.
      var blank = 0;
      for (final b in (traced['buildings'] as List)) {
        final m = b as Map<String, dynamic>;
        if (m['campus'] == true) continue;
        final hasName = (m['name'] as String?)?.isNotEmpty ?? false;
        final hasNo = (m['bno'] as String?)?.isNotEmpty ?? false;
        if (!hasName && !hasNo) blank++;
      }
      // VWorld 지적에 주소가 비어 있는 부속 건물이 조금 있다.
      expect(blank, lessThan(45));
    });
  });
}
