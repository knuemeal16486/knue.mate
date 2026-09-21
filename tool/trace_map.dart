// 네이버지도 캡처 3장에서 캠퍼스 지형을 그대로 뽑아 lib/campus_traced.dart를 만든다.
//
// 등록(px→월드)은 tool/register2.dart(학교용지 파란영역 상관)와
// tool/register3.dart(VWorld 건물 폴리곤 상관) 두 방법이 독립적으로 2.5m 안쪽
// 같은 값을 낸 것을 확인하고 고정했다. 배율은 세 장 모두 같은 줌(50m 눈금)이라 하나다.
//
// 캡처 색이 무엇을 뜻하는지:
//   212,224,240  학교용지 바탕 — **건물 외곽선도 같은 색**이다(213,225,239).
//                덕분에 붙어 있는 두 동 사이에 항상 이 색 선이 한 줄 있다.
//   239,244,248  건물·운동시설 채움 (JPEG에선 244,247,250로 밀린다)
//   249,247,244  포장면(도로·광장·주차장)
//   208,228,188  잔디
//   164,208,240  수면
//   219,224,229  주차 구획선(빗살). 무채색이라 파란 건물선과 구분된다.
//   148,180,242  P 마커
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'map_trace_lib.dart';

const kScale = 0.619; // m/px
const kShots = <String, List<double>>{
  //            tx       ty      색 허용오차
  'core.jpg': [-201.2, -215.0, 16],
  'north.png': [-236.5, -712.5, 10],
  'south.png': [-116.8, 163.5, 10],
};

/// 격자 해상도. 캡처가 0.619 m/px이므로 그보다 잘게 잡아야 건물 사이
/// 한 줄짜리 외곽선이 살아남는다 — 그 선이 곧 건물을 떼는 칼이다.
const res = 0.3;
const ox = -260.0, oy = -730.0;
// 캡처 3장의 합집합은 x -236.5..972.0, y -712.5..682.8이다.
// 예전 격자(x -320..910)는 동쪽 62m를 잘라먹고 있었다.
const gw = 4140, gh = 4780; // 월드 -260..982 x -730..704

class Layers {
  // ── 부지 안 ──
  final campus = Mask(gw, gh); // 학교용지 바탕 + 건물 외곽선
  final pave = Mask(gw, gh); // 도로·광장·주차장
  final green = Mask(gw, gh);
  final water = Mask(gw, gh);
  final pale = Mask(gw, gh); // 건물 + 운동시설 채움
  final mark = Mask(gw, gh); // 주차 구획선
  final pmark = Mask(gw, gh); // P 마커

  // ── 부지 밖 ──
  //
  // 밖에서는 건물이 채움색이 아니라 **외곽선**으로 그려진다. 실측한 팔레트는
  //   배경 247 < 건물 252 < 도로 255,  그 사이를 외곽선·연석(210~242)이 가른다.
  // 3~5단계 차이라 픽셀 하나로 가르면 위태롭다. 그래서 '밝은 것'을 한 덩어리로
  // 잡아두고, 외곽선이 갈라놓은 **덩어리마다 평균 밝기**로 건물/도로를 정한다.
  // 덩어리는 수백~수천 픽셀이라 평균은 아주 안정적이다.
  final outBright = Mask(gw, gh); // 건물 ∪ 도로 (밝은 무채색)
  final outGround = Mask(gw, gh); // 배경 지면
  final major = Mask(gw, gh); // 국도 노랑
  final lum = Uint8List(gw * gh); // 밝기 (덩어리 평균을 내려고 들고 있는다)
}

void main() {
  final L = Layers();
  // 겹치는 구역은 **더 안쪽으로 찍힌 캡처**가 이긴다.
  //
  // 예전엔 세 장을 그냥 OR로 합쳤다. 그러면 등록 오차 몇 m 때문에 같은 잔디가
  // 두 장에서 살짝 어긋나게 찍혀 운동장 잔디에 꼬리가 붙었다. 캡처 테두리에서
  // 먼 픽셀일수록 믿을 만하므로, 그 점수로 한 장만 고른다.
  final best = Uint16List(gw * gh);
  // 캡처가 겹치는 곳에서 잔디 판정이 갈리면 이음매를 따라 초승달 찌꺼기가
  // 남는다(대운동장 트랙 옆에 40x15m짜리가 붙어 있었다). 몇 장이 덮었고
  // 몇 장이 잔디라고 했는지 세어, 겹치는 곳에서는 **둘 다 동의할 때만** 잔디로 친다.
  final coverN = Uint8List(gw * gh);
  final greenN = Uint8List(gw * gh);
  const order = ['north.png', 'south.png', 'core.jpg'];
  for (final f in order) {
    final im = img.decodeImage(File('tool/mapsrc/$f').readAsBytesSync())!;
    final c = kShots[f]!;
    final tx = c[0], ty = c[1];
    final tol = c[2].toInt();
    for (var j = 0; j < gh; j++) {
      final py = ((oy + j * res - ty) / kScale).round();
      if (py < 0 || py >= im.height) continue;
      final row = j * gw;
      for (var i = 0; i < gw; i++) {
        final px = ((ox + i * res - tx) / kScale).round();
        if (px < 0 || px >= im.width) continue;
        final pv = im.getPixel(px, py);
        coverN[row + i]++;
        if (near(pv, 208, 228, 188, tol) || near(pv, 220, 236, 204, tol)) {
          greenN[row + i]++;
        }
        // 캡처 테두리까지의 거리 = 이 픽셀을 얼마나 믿을 수 있나
        final score = math.min(math.min(px, im.width - 1 - px),
                math.min(py, im.height - 1 - py)) +
            1;
        if (score <= best[row + i]) continue;
        best[row + i] = score;
        // 다른 캡처가 먼저 칠했을 수 있으니 이 셀을 비우고 다시 판정한다
        L.campus.bits[row + i] = 0;
        L.green.bits[row + i] = 0;
        L.water.bits[row + i] = 0;
        L.pale.bits[row + i] = 0;
        L.pave.bits[row + i] = 0;
        L.mark.bits[row + i] = 0;
        L.pmark.bits[row + i] = 0;
        L.outBright.bits[row + i] = 0;
        L.outGround.bits[row + i] = 0;
        L.major.bits[row + i] = 0;
        final p = im.getPixel(px, py);
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final tint = b - r;
        // 부지 파랑은 넓고 평평한 채움이라 노이즈가 작다. 허용오차를 넓게 잡으면
        // 부지 밖 파르스름한 회색까지 딸려와 경계가 원룸촌을 삼킨다.
        if (near(p, 212, 224, 240, math.min(tol, 9))) {
          L.campus.bits[row + i] = 1;
        } else if (near(p, 208, 228, 188, tol) || near(p, 220, 236, 204, tol)) {
          L.green.bits[row + i] = 1;
          L.campus.bits[row + i] = 1; // 녹지도 부지 안쪽이다
        } else if (near(p, 164, 208, 240, tol)) {
          L.water.bits[row + i] = 1;
        } else if (tint > 60 && b > 200 && r < 200) {
          L.pmark.bits[row + i] = 1; // P 마커의 진한 파랑
        } else if (r >= 231 && r <= 250 && tint >= 3 && tint <= 13 && g >= r) {
          // 건물·운동시설 채움. 절대색으로 찍으면 캡처마다 값이 달라 놓친다
          // (PNG 239,244,248 / JPEG 244,247,250). **푸른 기운**으로 가른다.
          L.pale.bits[row + i] = 1;
        } else if (r >= 240 && g >= 238 && b >= 236) {
          // 밝은 무채색 = 포장면. 부지 밖 배경(244 회색)과 색이 거의 같아서
          // 여기서 거르지 않고 나중에 부지 안쪽으로 잘라낸다.
          L.pave.bits[row + i] = 1;
        } else if (r >= 200 && r <= 236 && tint.abs() <= 18 && g >= r - 4) {
          // 포장면보다 한 톤 어두운 무채색 선 = 주차 구획선(빗살).
          // 건물 외곽선(213,225,239)은 푸르스름해서 여기 안 걸린다.
          L.mark.bits[row + i] = 1;
        }
        // ── 부지 밖 ──
        if (near(p, 252, 240, 180, 14)) {
          L.major.bits[row + i] = 1; // 국도 노랑
        } else {
          final mx = math.max(r, math.max(g, b));
          final mn = math.min(r, math.min(g, b));
          // 밝기는 채도와 무관하게 늘 기록한다 — 국소 평균에 빈칸이 있으면
          // 옅은 외곽선 검출이 어긋난다.
          final v = (r + g + b) ~/ 3;
          L.lum[row + i] = v;
          if (mx - mn <= 10) {
            if (v >= 249) {
              L.outBright.bits[row + i] = 1;
            } else if (v >= 242) {
              L.outGround.bits[row + i] = 1;
            }
          }
        }
      }
    }
  }
  // 두 장 이상이 덮은 곳에서 한 장만 잔디라고 하면 이음매 찌꺼기다.
  var seamDrop = 0;
  for (var i = 0; i < L.green.bits.length; i++) {
    if (L.green.bits[i] != 0 && coverN[i] >= 2 && greenN[i] < 2) {
      L.green.bits[i] = 0;
      seamDrop++;
    }
  }
  stdout.writeln('이음매에서 어긋난 잔디 ${(seamDrop * res * res).round()}㎡ 제외');
  stdout.writeln('격자 ${gw}x$gh (${res}m/셀)  바탕 ${L.campus.count}  '
      '포장 ${L.pave.count}  녹지 ${L.green.count}  '
      '구획선 ${L.mark.count}  P ${L.pmark.count}');

  // ── 1. 부지 경계 ──────────────────────────────────────────────
  // 부지 안 도로·건물 때문에 파란영역이 숭숭 뚫려 있다. 거칠게 닫고 외곽만 딴다.
  // 과반 축소를 쓰는 이유: OR 축소는 오분류 한 점도 살려내서 닫기가 그걸
  // 부지로 이어붙인다.
  const cf = 4; // 1.2 m/셀
  final coarse = L.campus.shrinkMajority(cf, 0.45);
  final closed = closeM(coarse, 18); // 18셀 = 21.6m — 부지 안 도로 폭을 메운다
  final bl = label4(closed, minArea: 16000);
  final boundary = <List<Pt>>[];
  for (var id = 1; id <= bl.count; id++) {
    if (bl.area[id - 1] < 16000) continue;
    const pad = 8;
    final crop = bl.crop(id, pad: pad);
    final o = bl.cropOrigin(id, pad: pad);
    for (final loop in traceSmooth(crop,
        blurR: 1, blurN: 1, round: 3, preEps: 1.0, postEps: 0.6,
        minLoopArea: 8000)) {
      boundary.add([
        for (final p in loop)
          Pt(ox + (p.x + o[0]) * res * cf, oy + (p.y + o[1]) * res * cf)
      ]);
    }
  }
  boundary.sort((a, b) => polyArea(b).compareTo(polyArea(a)));
  stdout.writeln('경계 ${boundary.length}개  '
      '${(polyArea(boundary.first) / 10000).toStringAsFixed(1)} ha');
  final outline = boundary.first;

  bool insidePoly(List<Pt> poly) {
    final c = polyCenterBox(poly)[0];
    return pip(outline, c.x, c.y);
  }

  final inCampus = closeM(coarse, 28).upscaleTo(gw, gh, cf);
  final base = loadBase();

  // 부지 밖 건물은 VWorld 지적을 쓴다(사용자가 정한 원칙). 그 자리를 도로나
  // 녹지가 덮으면 지도가 뭉개진다 — 실측해 보니 건물의 6.4%(7,580㎡)가
  // 포장면 아래 깔려 있었다. 아래 레이어들에서 미리 빼둔다.
  final bldBlock = dilate(
      rasterize([
        for (final b in base['buildings'])
          [
            for (final p in b['ring'])
              [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
          ]
      ], gw, gh, ox, oy, res),
      1);

  // ── 2. 잔디·수면 ──────────────────────────────────────────────
  /// 마스크 → 매끈한 월드 폴리곤. 계단 모양을 없애려고 흐린 뒤 0.5 등고선을
  /// 딴다([traceSmooth]). [round]는 모서리를 얼마나 둥글릴지.
  List<List<Pt>> blobs(Mask m, double minM2, {int round = 2, int blurR = 2}) {
    final need = (minM2 / (res * res)).round();
    final l = label4(m, minArea: need);
    final out = <List<Pt>>[];
    for (var id = 1; id <= l.count; id++) {
      if (l.area[id - 1] < need) continue;
      final pad = blurR * 3 + 2;
      final crop = l.crop(id, pad: pad);
      final o = l.cropOrigin(id, pad: pad);
      // 넓은 숲은 허용오차를 키운다 — 잔디처럼 또렷할 필요가 없고,
      // 그대로 두면 점이 수만 개로 불어난다.
      final wide = l.area[id - 1] > 40000; // 3600㎡ 이상
      for (final loop in traceSmooth(crop,
          blurR: wide ? 4 : blurR,
          round: 0,
          preEps: wide ? 6.0 : 1.2,
          minLoopArea: need * 0.6)) {
        final poly = roundCorners(straighten([
          for (final p in loop) Pt(ox + (p.x + o[0]) * res, oy + (p.y + o[1]) * res)
        ], mergeDeg: 9, minEdge: 1.2), iters: round);
        // 실 같은 초승달 조각은 버린다. 캡처 두 장이 만나는 자리에서 잔디가
        // 몇 m 어긋나며 생기는 찌꺼기라, 지도에 실오라기로 남는다.
        // 4·면적/둘레 = 대략의 폭. 3m보다 얇으면 지도에 그릴 게 못 된다.
        var per = 0.0;
        for (var k = 0; k < poly.length; k++) {
          final a = poly[k], b = poly[(k + 1) % poly.length];
          per += math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
        }
        if (per > 0 && 4 * polyArea(poly) / per < 3.0) continue;
        // 부지 밖 녹지(지적 임야·공원)도 쓴다 — 사용자가 정한 원칙이다.
        if (poly.length >= 6) out.add(poly);
      }
    }
    out.sort((a, b) => polyArea(b).compareTo(polyArea(a)));
    return out;
  }

  // 부지 밖 녹지는 사진과 지적을 함께 쓴다. 네이버는 부지 밖 숲을 흐리게
  // 그려 색으로 잘 안 잡히는데, 지적 임야·공원 필지는 또렷하다.
  {
    final vwGreen = rasterize([
      for (final l in base['landuse'])
        if (l['g'] == 'forest' || l['g'] == 'park')
          [
            for (final p in l['ring'])
              [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
          ]
    ], gw, gh, ox, oy, res);
    final outside = closeM(coarse, 28).upscaleTo(gw, gh, cf).inverted;
    for (var i = 0; i < L.green.bits.length; i++) {
      if (vwGreen.bits[i] != 0 &&
          outside.bits[i] != 0 &&
          bldBlock.bits[i] == 0) {
        L.green.bits[i] = 1;
      }
    }
  }

  // 잔디 위 흰 라인(축구장 선·코트 네트선)이 면을 조각내므로 먼저 메운다.
  // 열기를 먼저 건다. 캡처 두 장이 만나는 자리에서 잔디가 몇 m 어긋나며
  // 가는 혓바닥이 생기는데, 운동장 잔디에 꼬리처럼 붙어 보인다.
  // 닫기는 그 뒤에 — 축구장 흰 선으로 조각난 면을 도로 잇는 건 그다음이다.
  final greens = blobs(closeM(openM(L.green, 3), 3), 120);
  final waters = blobs(L.water, 150);

  // ── 3. 건물·운동시설 ──────────────────────────────────────────
  // 붙어 있는 동 사이에는 부지색 외곽선이 한 줄 지나간다. 0.3m 격자에서는
  // 그 선이 2셀쯤 되어 살아 있으므로, 살짝만 깎아도 서로 떨어진다.
  final paleIn = L.pale & inCampus;
  // ⚠️ 네이버는 **한 건물 안에도** 날개를 나누는 칸막이 선을 긋는다.
  // 그 선까지 '건물 사이 틈'으로 읽으면 한 동이 여러 조각으로 쪼개지고,
  // 조각마다 층수가 달리 잡혀 3D로 세우면 블록을 쌓아 놓은 더미가 된다
  // (교원문화관이 4조각, 호연관·종합교육관·국제연수관도 같은 꼴이었다).
  //
  // 둘은 **폭**으로 갈린다. 칸막이는 원본 1px(≈2셀)이고, 진짜 건물 사이
  // 틈은 3~5px(≈6~10셀)이다. 반지름 2셀(0.6m)로 닫으면 4셀까지 메워지니
  // 칸막이만 사라지고 진짜 틈은 남는다.
  final paleJoined = closeM(paleIn, 2);

  // 다만 닫기만 하면 **진짜로 붙어 있는 두 동**까지 하나가 된다. 호연관과
  // 미래도서관, 체육관과 제2체육관 사이가 그렇게 좁다.
  //
  // 그건 캡처가 알려준다 — 건물 이름표는 동마다 하나씩 찍혀 있다
  // (tool/mapsrc/seeds.json). 한 덩어리 안에 이름표가 둘 이상 들어 있으면
  // 서로 다른 동이 붙은 것이므로, 이름표 자리마다 씨앗을 놓아 도로 가른다.
  final labelPts = <List<int>>[];
  {
    final raw = jsonDecode(
        File('tool/mapsrc/seeds.json').readAsStringSync()) as Map<String, dynamic>;
    for (final v in raw.values) {
      final x = ((v[0] as num).toDouble() - ox) / res;
      final y = ((v[1] as num).toDouble() - oy) / res;
      labelPts.add([x.round(), y.round()]);
    }
  }

  final eroded = erode(paleJoined, 3);
  final comp = label4(eroded, minArea: 800); // 800셀 ≈ 72㎡
  // 이름표 자리를 그대로 찍으면 안 된다 — **글자 픽셀이 건물 채움색이
  // 아니라서 마스크에 구멍이 난다.** 실제로 27개 중 16개가 그렇게 빗나갔다
  // (호연관·체육관·교원문화관 등 대부분). 주변에서 가장 가까운 건물 셀을
  // 찾아 그 덩어리에 넣는다. 10m까지만 본다 — 그보다 멀면 이름표가 건물
  // 위가 아니라 옆에 놓인 경우라 어느 동인지 단정할 수 없다.
  final ptsOf = <int, List<List<int>>>{};
  const maxR = 34; // 34셀 ≈ 10m
  for (final c in labelPts) {
    var found = false;
    for (var r = 0; r <= maxR && !found; r++) {
      for (var dy = -r; dy <= r && !found; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          // 껍데기만 훑는다(이미 안쪽은 앞선 반지름에서 봤다)
          if (r > 0 && dx.abs() != r && dy.abs() != r) continue;
          final x = c[0] + dx, y = c[1] + dy;
          if (x < 0 || y < 0 || x >= gw || y >= gh) continue;
          final id = comp.labels[y * gw + x];
          if (id == 0) continue;
          (ptsOf[id] ??= []).add([x, y]);
          found = true;
          break;
        }
      }
    }
  }

  final seedMask = Mask(gw, gh);
  for (var i = 0; i < seedMask.bits.length; i++) {
    final id = comp.labels[i];
    // 이름표가 둘 이상인 덩어리는 통째 씨앗으로 쓰지 않는다 — 아래에서
    // 이름표 자리에 작은 씨앗을 따로 놓는다.
    if (id == 0 || (ptsOf[id]?.length ?? 0) >= 2) continue;
    seedMask.bits[i] = 1;
  }
  // 이름표 자리마다 작은 씨앗을 놓는다. 경계는 두 씨앗에서 동시에 자란
  // 것이 만나는 자리에 생긴다.
  //
  // 칸막이 이전 조각을 통째로 씨앗으로 쓰는 방법도 대봤지만 더 나빴다 —
  // 한 동의 날개가 여러 조각으로 갈려 있어서, 조각 하나를 통째로 집으면
  // 옆 동의 씨앗과 뒤엉켜 호연관·미래도서관이 같은 영역을 중복으로 덮었다
  // (둘 다 3241㎡로 나왔다).
  var reSplit = 0;
  for (final e in ptsOf.entries) {
    if (e.value.length < 2) continue;
    reSplit++;
    for (final c in e.value) {
      for (var dy = -3; dy <= 3; dy++) {
        for (var dx = -3; dx <= 3; dx++) {
          if (dx * dx + dy * dy > 9) continue;
          final x = c[0] + dx, y = c[1] + dy;
          if (x < 0 || y < 0 || x >= gw || y >= gh) continue;
          // 씨앗은 건물 안에만 놓는다.
          if (paleIn.bits[y * gw + x] != 0) seedMask.bits[y * gw + x] = 1;
        }
      }
    }
  }
  stdout.writeln('칸막이 메움 · 이름표가 둘 이상이라 도로 가른 덩어리 $reSplit개');

  final seeds = label4(seedMask, minArea: 1);
  // 씨앗을 원래 영역으로 되돌린다. 요소마다 따로 부풀리면 옆 동과 겹친다.
  //
  // 두 번에 나눠 키운다.
  //  1) 칸막이가 살아 있는 원본(paleIn)에서 먼저 — 이름표가 앉은 칸을
  //     제 것으로 확보한다. 실제 경계선이 있는 자리는 그대로 지켜진다.
  //  2) 칸막이를 메운 것(paleJoined)에서 한 번 더 — 아무도 못 닿은 칸을
  //     가까운 쪽이 가져간다. 이 단계가 없으면 이름표로 가른 동이 제
  //     칸 하나에 갇힌다(제2체육관이 254㎡로 쪼그라들었다).
  growInto(seeds, paleIn);
  growInto(seeds, paleJoined);

  final greenGrown = dilate(L.green, 3);
  final facils = <List<Pt>>[];
  final blds = <List<Pt>>[];
  for (var id = 1; id <= seeds.count; id++) {
    if (seeds.area[id - 1] < 800) continue;
    const pad = 8;
    final crop = seeds.crop(id, pad: pad);
    final o = seeds.cropOrigin(id, pad: pad);
    // 건물은 둥글리지 않는다. 등고선을 딴 뒤 **직각으로 세운다**([regularize]).
    // 물확산으로 나눈 자리는 경계가 지그재그라, 그냥 두면 흐물흐물해 보인다.
    // **흐리지 않는다**(blurR 0). 캡처는 항공사진이 아니라 벡터로 그린 지도라
    // 건물 모서리가 이미 칼같이 서 있다. 흐리면 그 모서리를 우리 손으로
    // 뭉개는 셈이고, 그렇게 둥글려진 등고선은 직각화도 제대로 못 한다.
    //
    // 실측(원본 픽셀 대비 건물 IoU):
    //   blurR 2 preEps 1.6  59.6%   ← 예전
    //   blurR 2 preEps 0.8  60.1%
    //   blurR 1 preEps 0.8  62.3%
    //   blurR 0 preEps 0.8  63.9%   ← 지금
    // 덤으로 꼭짓점이 중앙 13→34개로 늘어 건물의 홈·날개가 살아난다
    // (흐림을 걷으니 단순화와 충실도를 함께 얻었다).
    final loops = traceSmooth(crop, blurR: 1, blurN: 1, round: 0, preEps: 0.8);
    if (loops.isEmpty) continue;
    final raw = [
      for (final p in loops.first)
        Pt(ox + (p.x + o[0]) * res, oy + (p.y + o[1]) * res)
    ];
    // snapDeg는 45 — **모든 변을 직각 격자에 세운다.**
    //
    // 기본값 32로 두면 32°보다 많이 틀어진 변이 제 각도를 유지하는데,
    // 물확산 경계는 온갖 각도의 짧은 변으로 이뤄져 있어 그게 그대로 남는다.
    // 실측: 32°에서는 54동 중 47동이 직각률 75% 미만(여럿은 0%)이었다.
    // 45°로 세우면 1동만 남고 평균 직각률이 98%가 된다. 원본 픽셀과의
    // IoU는 61.3%→59.6%로 1.7%p 내려가지만, 그 '원본'이란 게 뭉개진
    // 등고선이지 건물의 실제 모양이 아니다. 건물은 각져야 건물로 보인다.
    //
    // 비스듬히 앉은 건물은 dominantAngle(θ)이 통째로 기울여 잡아 주므로
    // 여기서 45로 세워도 사선 건물이 억지로 똑바로 서지 않는다.
    // 짧은 변을 걷어내는 기준을 **건물 크기에 비례**하게 잡는다.
    //
    // 0.8m 고정으로 두면 큰 건물에는 적당한데 작은 건물에는 그게 잡음
    // 크기다 — 격자가 0.3m라 17m짜리 건물은 한 변이 57칸뿐이고, 경계가
    // 한두 칸만 흔들려도 전체 모양의 3%가 흔들린다(큰 건물은 1%).
    // 실제로 작은 건물(<600㎡)이 큰 건물보다 급한 꺾임이 1.6배 많았고,
    // 교원문화관(556㎡)은 꼭짓점이 47개였다.
    final side = math.sqrt(polyArea(raw));
    final poly = deSpike(regularize(raw,
        snapDeg: 38, minEdge: (side * 0.11).clamp(0.8, 3.5)));
    if (poly.length < 4 || !insidePoly(poly)) continue;
    // 운동시설이냐 건물이냐 — **잔디를 품고 있는가**로 가른다. 트랙·코트
    // 블록은 가운데가 초록이라, 구멍을 메우고 나서 재야 겹침이 잡힌다.
    final filled = fillHoles(crop);
    var greenIn = 0, tot = 0;
    for (var y = 0; y < filled.h; y++) {
      for (var x = 0; x < filled.w; x++) {
        if (filled.bits[y * filled.w + x] == 0) continue;
        tot++;
        if (greenGrown.at(x + o[0], y + o[1])) greenIn++;
      }
    }
    if (greenIn > tot * 0.08) {
      // 운동시설은 트랙처럼 진짜 곡선이다. 더 흐리고 더 둥글려 다시 딴다.
      final sm = traceSmooth(crop, blurR: 3, blurN: 3, round: 0, preEps: 0.9);
      facils.add(sm.isEmpty
          ? raw
          : roundCorners(straighten([
              for (final p in sm.first)
                Pt(ox + (p.x + o[0]) * res, oy + (p.y + o[1]) * res)
            ], mergeDeg: 7, minEdge: 1.2), iters: 2));
    } else {
      blds.add(poly);
    }
  }
  facils.sort((a, b) => polyArea(b).compareTo(polyArea(a)));

  // 운동시설 안에 들어앉은 자잘한 초록은 버린다.
  //
  // 트랙에 인필드는 하나뿐이다. 캡처 두 장이 만나는 자리에서 잔디가 몇 m
  // 어긋나면 트랙 가장자리를 따라 **초승달 모양 찌꺼기**가 남는데, 가늘지도
  // 작지도 않아서(395㎡, 폭 10m) 두께나 면적으로는 못 거른다.
  // "시설 넓이의 4분의 1도 안 되면서 그 안에 있다"는 조건이 정확히 잡아낸다.
  greens.removeWhere((g) {
    final c = polyCenterBox(g)[0];
    final a = polyArea(g);
    for (final f in facils) {
      if (pip(f, c.x, c.y) && a < polyArea(f) * 0.25) return true;
    }
    return false;
  });
  // 부지 안 잔디(운동장·화단)와 부지 밖 숲은 성격이 다르다. 네이버도 숲을
  // 훨씬 흐리게 그린다 — 같은 초록으로 칠하면 지도가 요란해진다.
  // **녹지를 다 걸러낸 뒤에** 짝을 만들어야 인덱스가 어긋나지 않는다.
  final greenOutside = [
    for (final g in greens) !insidePoly(g)
  ];
  blds.sort((a, b) => polyArea(b).compareTo(polyArea(a)));

  // ㄷ자·ㅁ자 건물은 바깥 고리만 따면 안뜰이 메워진다. 그 안뜰에 다른 동이
  // 들어앉아 있으면 통째로 덮여 보이지도 않으면서 겹침으로만 잡힌다.
  // 큰 것부터 정렬돼 있으니, 앞선 동 안에 든 것을 뺀다.
  final nested = <int>[];
  for (var i = 0; i < blds.length; i++) {
    final c = polyCenterBox(blds[i])[0];
    for (var j = 0; j < i; j++) {
      if (pip(blds[j], c.x, c.y)) {
        nested.add(i);
        break;
      }
    }
  }
  if (nested.isNotEmpty) {
    final sizes = nested.map((i) => polyArea(blds[i]).round()).join(', ');
    stdout.writeln('안뜰에 파묻힌 동 ${nested.length}개 제외 ($sizes ㎡)');
    for (final i in nested.reversed) {
      blds.removeAt(i);
    }
  }

  // ── 4. 주차장 ─────────────────────────────────────────────────
  // 주차 구획선만 색으로 집으려 하면 실패한다 — 포장면과 부지 바탕이 만나는
  // 가장자리의 안티에일리어싱 픽셀이 똑같은 회색이라 캠퍼스 전체가 잡힌다.
  //
  // 가르는 건 색이 아니라 **밀도**다. 주차 빗살은 2.5m 간격으로 줄이 서 있어
  // 8m 창 안에서 20%를 넘지만, 길가장자리는 한 줄뿐이라 7% 언저리다.
  final markIn = Mask(gw, gh);
  final nearPale = dilate(paleIn, 6);
  for (var i = 0; i < markIn.bits.length; i++) {
    markIn.bits[i] = (L.mark.bits[i] != 0 &&
            inCampus.bits[i] != 0 &&
            nearPale.bits[i] == 0)
        ? 1
        : 0;
  }
  const win = 13; // 반지름 13셀 = 27x27셀 ≈ 8m 창
  final dens = _density(markIn, win);
  final parkMask = Mask(gw, gh);
  final side = (win * 2 + 1) * (win * 2 + 1);
  for (var i = 0; i < parkMask.bits.length; i++) {
    parkMask.bits[i] = dens[i] > side * 0.18 ? 1 : 0;
  }
  final parkClean = openM(closeM(parkMask, 8), 5);
  final blocked = dilate(paleIn | L.green | L.water, 2);
  for (var i = 0; i < parkMask.bits.length; i++) {
    parkMask.bits[i] =
        (parkClean.bits[i] != 0 && blocked.bits[i] == 0) ? 1 : 0;
  }
  final pl = label4(parkMask, minArea: 900); // 900셀 ≈ 81㎡
  final pmarkGrown = dilate(L.pmark, 40); // 12m 안에 P가 있으면 주차장
  final parks = <List<Pt>>[];
  for (var id = 1; id <= pl.count; id++) {
    final a = pl.area[id - 1];
    if (a < 900) continue;
    const pad = 11;
    final crop = pl.crop(id, pad: pad);
    final o = pl.cropOrigin(id, pad: pad);
    var hasP = false;
    for (var y = 0; y < crop.h && !hasP; y++) {
      for (var x = 0; x < crop.w; x++) {
        if (crop.bits[y * crop.w + x] != 0 &&
            pmarkGrown.at(x + o[0], y + o[1])) {
          hasP = true;
          break;
        }
      }
    }
    // P가 없으면 횡단보도·계단 같은 잔무늬일 수 있으니 넉넉한 크기를 요구한다
    if (!hasP && a < 2800) continue;
    for (final loop in traceSmooth(crop, blurR: 2, round: 0, preEps: 1.6,
        minLoopArea: 600)) {
      final poly = straighten([
        for (final p in loop)
          Pt(ox + (p.x + o[0]) * res, oy + (p.y + o[1]) * res)
      ], mergeDeg: 14, minEdge: 2.2);
      if (poly.length >= 6 && insidePoly(poly)) parks.add(poly);
    }
  }
  parks.sort((a, b) => polyArea(b).compareTo(polyArea(a)));

  // ── 4.5 부지 밖 도로 ──────────────────────────────────────────
  //
  // 원칙: **교내는 사진, 부지 밖 건물은 VWorld, 부지 밖 도로·녹지는 둘 다.**
  // 여기서는 사진 몫만 뽑는다 — VWorld 몫은 아래에서 합친다.
  //
  // 밝은 무채색(≥249) 덩어리는 건물 아니면 도로다. 둘은 3단계밖에 차이가
  // 안 나지만(건물 252, 도로 255) 외곽선·연석이 덩어리를 갈라놓기 때문에,
  // **덩어리 평균 밝기**로 가르면 픽셀 하나로 재는 것보다 훨씬 안정적이다.
  // 건물로 갈린 덩어리는 버린다 — 부지 밖 건물은 VWorld가 더 정확하다
  // (사진에서 뽑으면 흐리게 그려진 구역을 놓쳐 원룸이 통째로 사라졌다).
  final notCampus = inCampus.inverted;
  final ol = label4(L.outBright & notCampus, minArea: 200);
  final outRoad = Mask(gw, gh);
  for (var id = 1; id <= ol.count; id++) {
    final a = ol.area[id - 1];
    if (a < 200) continue;
    final crop = ol.crop(id, pad: 6);
    final o = ol.cropOrigin(id, pad: 6);
    var sum = 0, n = 0;
    for (var y = 0; y < crop.h; y++) {
      for (var x = 0; x < crop.w; x++) {
        if (crop.bits[y * crop.w + x] == 0) continue;
        sum += L.lum[(y + o[1]) * gw + (x + o[0])];
        n++;
      }
    }
    final mean = n == 0 ? 0 : sum / n;
    // 2만㎡ 넘는 덩어리는 길그물이다 — 중간에 건물이 몇 채 붙어 평균이
    // 내려가도 도로로 본다.
    if (mean < 253.2 && a * res * res <= 20000) continue;
    for (var y = 0; y < crop.h; y++) {
      for (var x = 0; x < crop.w; x++) {
        final k = (y + o[1]) * gw + (x + o[0]);
        if (crop.bits[y * crop.w + x] != 0 && bldBlock.bits[k] == 0) {
          outRoad.bits[k] = 1;
        }
      }
    }
  }

  // VWorld 도로 필지를 합친다. 사진만으로는 건물 그림자에 묻힌 골목이나
  // 흐리게 그려진 구간을 놓친다 — 지적은 그런 데서 빠지지 않는다.
  final vwRoad = rasterize([
    for (final l in base['landuse'])
      if (l['g'] == 'road')
        [
          for (final p in l['ring'])
            [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
        ]
  ], gw, gh, ox, oy, res);
  var addedByVw = 0;
  for (var i = 0; i < outRoad.bits.length; i++) {
    if (vwRoad.bits[i] != 0 &&
        notCampus.bits[i] != 0 &&
        bldBlock.bits[i] == 0 &&
        outRoad.bits[i] == 0) {
      outRoad.bits[i] = 1;
      addedByVw++;
    }
  }
  // 두 출처가 몇 m 어긋나 있어 그냥 합치면 경계가 톱니처럼 된다.
  // 닫고-열어 화해시킨다: 닫기가 둘 사이 틈을 메우고, 열기가 한쪽에만 있는
  // 얇은 혓바닥을 깎는다.
  final outRoadClean = openM(closeM(outRoad, 5), 4);
  for (var i = 0; i < outRoad.bits.length; i++) {
    // 닫기가 건물 위를 도로 메우므로 마지막에 한 번 더 뺀다
    outRoad.bits[i] =
        (outRoadClean.bits[i] != 0 && bldBlock.bits[i] == 0) ? 1 : 0;
  }
  stdout.writeln('부지 밖 도로 ${(outRoad.count * res * res).round()}㎡ '
      '(그중 지적이 채운 몫 ${(addedByVw * res * res).round()}㎡)');

  // ── 5. 포장면 ─────────────────────────────────────────────────
  // 중심선을 굵게 긋는 대신 포장면 자체를 면으로 낸다. 세선화는 광장·주차장에서
  // 잔가지투성이가 되어 길이 끊겨 보였다.
  final paveIn = Mask(gw, gh);
  final notRoad = dilate(paleIn, 2);
  for (var i = 0; i < paveIn.bits.length; i++) {
    final inside = L.pave.bits[i] != 0 &&
        inCampus.bits[i] != 0 &&
        notRoad.bits[i] == 0;
    paveIn.bits[i] = (inside || outRoad.bits[i] != 0) ? 1 : 0;
  }
  final road = openM(closeM(paveIn, 3), 2);
  stdout.writeln('포장면 ${(road.count * res * res).round()} ㎡');

  // 도로는 이제 OSM 중심선을 굵기로 그어 따로 그린다. 캡처에서 뜬 포장면이
  // 도로 통로까지 품고 있으면, 깔끔한 도로선 옆으로 **들쭉날쭉한 옛 가장자리가
  // 비어져 나온다.** 포장면이 맡을 건 광장·주차 앞마당 같은 너른 면뿐이므로
  // OSM 도로가 덮는 통로를 빼고 남는 것만 추적한다.
  //
  // 뺀 뒤에는 도로 옆에 가는 띠가 남는다(캡처의 길이 OSM 폭보다 조금 넓은
  // 자리). 반지름 3셀(0.9m)로 열어 폭 2m 안쪽 띠는 걷어낸다.
  //
  // 원본 road는 그대로 둔다 — 횡단보도 검출은 도로 위를 봐야 한다.
  final plaza = openM(road & osmCorridor().inverted, 3);
  stdout.writeln('도로를 뺀 포장면(광장·마당) '
      '${(plaza.count * res * res).round()} ㎡');

  // 도로 가장자리는 실제로 곡선이다. 계단 모양을 없애려고 흐린 뒤 0.5
  // 등고선을 따고([traceSmooth]) 모서리를 두 번 깎는다.
  final rl = label4(plaza, minArea: 3000); // 3000셀 ≈ 270㎡
  final outers = <List<Pt>>[];
  final holes = <List<Pt>>[];
  for (var id = 1; id <= rl.count; id++) {
    if (rl.area[id - 1] < 3000) continue;
    const pad = 11;
    final crop = rl.crop(id, pad: pad);
    final o = rl.cropOrigin(id, pad: pad);
    // 도로가 구불구불하던 원인은 **흐리기 자체**였다.
    //
    // 캡처가 0.619 m/px인데 0.3m 격자에 최근접으로 찍으니 경계가 계단진다.
    // 예전엔 그 계단을 흐려서(blurR 4) 없앴는데, 캡처는 항공사진이 아니라
    // 벡터로 그린 지도라 도로 가장자리가 원래 **완벽한 직선**이다. 흐리면
    // 그 직선과 모서리를 우리 손으로 둥글려 놓고 그걸 다시 펴려 애쓰는 꼴이
    // 된다. 계단은 흐리기가 아니라 **단순화 허용오차**(preEps)로 타 넘어야
    // 한다 — 계단 높이(≤0.62m)보다 크고 진짜 모서리보다 작은 값이면 된다.
    //
    // 실측(포장면 IoU / 지그재그율 / 점 수):
    //   blurR 4 preEps 2.5  88.2%  10.1%   4132   ← 예전
    //   blurR 2 preEps 1.5  89.6%  13.9%   5057
    //   blurR 0 preEps 2.5  90.5%   6.1%   7824
    //   blurR 0 preEps 1.8  91.7%   5.8%  10701   ← 지금
    //   blurR 0 preEps 0.8  94.1%   0.8%  32446   (계단을 그대로 담는다)
    // 흐리기를 걷으니 충실도와 곧기가 **함께** 좋아졌다. 점이 2.6배로 늘지만
    // 한 번 만들어 두고 그리는 Path라 부담이 크지 않다.
    final loops = traceSmooth(crop, blurR: 0, blurN: 1, round: 0,
        preEps: 2.2, minLoopArea: 400); // 400셀² ≈ 36㎡
    for (var k = 0; k < loops.length; k++) {
      final w = straighten([
        for (final p in loops[k])
          Pt(ox + (p.x + o[0]) * res, oy + (p.y + o[1]) * res)
        // **충실도를 택한 값이다.**
        //
        // 한동안 여기 mergeDeg를 62까지 올려 길을 곧게 펴려 했다. 그때는
        // 포장면이 도로망까지 책임졌기 때문인데, 곧게 펼수록 길이 제자리를
        // 벗어나는 맞바꿈이 끝이 없었다(긴 변 64%→87%에 IoU 91%→80%).
        //
        // 이제 도로는 OSM 중심선을 굵기로 그어 따로 그린다. 포장면이 맡는
        // 건 **광장·주차 앞마당 같은 너른 면**뿐이고, 그런 면은 원래 곧은
        // 직선이 아니라 제 모양이 있다. 그러니 억지로 펴지 말고 있는 그대로
        // 뜨는 게 맞다 — IoU를 되찾는다.
        //
        // 실측(둘레 중 8m 이상 긴 변 비율 / 포장면 IoU / 점 수):
        //   28,1.4  64.4%  91.2%  8722   ← 지금
        //   40,2.5  73.5%  89.2%  7188
        //   62,5.0  86.8%  80.3%  3769
      ], mergeDeg: 28, maxOffset: 1.4, minEdge: 2.0);
      // 곧게 펴면서 생긴 '나갔다 되돌아오는 가시'를 걷어낸다. 면적은 거의
      // 0이라 앞의 실오라기 검사에 안 걸리는데, 그려 놓으면 머리카락 같은
      // 자국이 지도를 가로지른다.
      final w2 = deSpike(w);
      // 실오라기는 버린다. 폭이 1.5m도 안 되면서 12m 넘게 뻗은 고리는
      // 길을 갈라놓은 가위 자국이지 실제 지형이 아니다.
      //
      // 바깥 고리가 실오라기면 그 덩어리 자체가 찌꺼기이므로 **구멍까지
      // 통째로** 버린다(면적 순이라 첫 고리가 바깥이다).
      final thin = isSliver(w2, maxWidth: 1.5, minLength: 12);
      if (k == 0 && thin) break;
      if (thin) continue;
      (k == 0 ? outers : holes).add(w2);
    }
  }
  outers.sort((a, b) => polyArea(b).compareTo(polyArea(a)));

  stdout.writeln('건물 ${blds.length}  운동시설 ${facils.length}  '
      '주차장 ${parks.length}  녹지 ${greens.length}  수면 ${waters.length}');
  stdout.writeln('포장면 외곽 ${outers.length}  구멍 ${holes.length}  '
      '점 ${outers.fold<int>(0, (a, r) => a + r.length) + holes.fold<int>(0, (a, r) => a + r.length)}');
  for (var i = 0; i < facils.length; i++) {
    stdout.writeln('  시설$i ${desc(facils[i])}');
  }
  for (var i = 0; i < parks.length; i++) {
    stdout.writeln('  주차$i ${desc(parks[i])}');
  }

  // ── 6. 국도·주차칸·횡단보도·POI ────────────────────────────────
  final majors = <List<Pt>>[];
  {
    final ml = label4(closeM(L.major, 3), minArea: 2000);
    for (var id = 1; id <= ml.count; id++) {
      if (ml.area[id - 1] < 2000) continue;
      final crop = ml.crop(id, pad: 10);
      final o = ml.cropOrigin(id, pad: 10);
      final loops = traceSmooth(crop, blurR: 2, blurN: 2, round: 0, preEps: 1.6);
      for (final l in loops) {
        majors.add(roundCorners(straighten([
          for (final p in l) Pt(ox + (p.x + o[0]) * res, oy + (p.y + o[1]) * res)
        ])));
      }
    }
  }

  // 주차칸은 선분을 수천 개 저장하지 않는다. 구역마다 **빗살 방향과 간격**만
  // 재두면 페인터가 그 두 숫자로 그려낸다.
  final stalls = <Map<String, dynamic>>[];
  final markLabel = label4(L.mark, minArea: 8);
  for (var pi = 0; pi < parks.length; pi++) {
    final poly = parks[pi];
    final cb = polyCenterBox(poly);
    var sx = 0.0, sy = 0.0, wsum = 0.0;
    final proj = <double>[];
    for (var id = 1; id <= markLabel.count; id++) {
      final k = id - 1;
      if (markLabel.area[k] < 8 || markLabel.area[k] > 400) continue;
      final cx = ox + (markLabel.minX[k] + markLabel.maxX[k]) / 2 * res;
      final cy = oy + (markLabel.minY[k] + markLabel.maxY[k]) / 2 * res;
      if ((cx - cb[0].x).abs() > cb[1].x / 2 + 2) continue;
      if ((cy - cb[0].y).abs() > cb[1].y / 2 + 2) continue;
      if (!pip(poly, cx, cy)) continue;
      // 눈금 하나의 방향 = 경계상자의 긴 축
      final dw = (markLabel.maxX[k] - markLabel.minX[k] + 1) * res;
      final dh = (markLabel.maxY[k] - markLabel.minY[k] + 1) * res;
      final ang = dw >= dh ? 0.0 : math.pi / 2;
      final len = math.max(dw, dh);
      sx += len * math.cos(2 * ang);
      sy += len * math.sin(2 * ang);
      wsum += len;
      proj.add(cx);
      proj.add(cy);
    }
    if (wsum < 4 || proj.length < 6) continue;
    final angle = math.atan2(sy, sx) / 2;
    // 간격 = 눈금 중심들을 빗살에 수직인 축으로 투영했을 때의 중앙 간격
    final perp = <double>[];
    for (var k = 0; k + 1 < proj.length; k += 2) {
      perp.add(-proj[k] * math.sin(angle) + proj[k + 1] * math.cos(angle));
    }
    perp.sort();
    final gaps = <double>[];
    for (var k = 1; k < perp.length; k++) {
      final g = perp[k] - perp[k - 1];
      if (g > 1.2 && g < 6) gaps.add(g);
    }
    gaps.sort();
    // 방향은 쟀는데 간격이 안 잡히는 구역이 많다(눈금이 성기거나 뭉쳐서).
    // 그때는 국내 주차 구획 표준폭 2.5m로 대신한다 — 방향이 맞으면 그것만으로도
    // 바닥이 주차장으로 읽힌다.
    final pitch = gaps.isEmpty ? 2.5 : gaps[gaps.length ~/ 2];
    stalls.add({
      'i': pi,
      'a': (angle * 1000).round() / 1000,
      'p': (pitch * 100).round() / 100,
      if (gaps.isEmpty) 'est': true,
    });
  }

  // 횡단보도 = 포장면 위, 주차구역 밖에 있는 짧은 평행 막대 뭉치
  final crosswalks = <Map<String, dynamic>>[];
  {
    final onRoad = dilate(road, 3);
    final inPark = Mask(gw, gh);
    for (final p in parks) {
      final cb = polyCenterBox(p);
      final i0 = ((cb[0].x - cb[1].x / 2 - ox) / res).floor();
      final i1 = ((cb[0].x + cb[1].x / 2 - ox) / res).ceil();
      final j0 = ((cb[0].y - cb[1].y / 2 - oy) / res).floor();
      final j1 = ((cb[0].y + cb[1].y / 2 - oy) / res).ceil();
      for (var j = math.max(0, j0); j <= math.min(gh - 1, j1); j++) {
        for (var i = math.max(0, i0); i <= math.min(gw - 1, i1); i++) {
          inPark.bits[j * gw + i] = 1;
        }
      }
    }
    final bars = Mask(gw, gh);
    for (var i = 0; i < bars.bits.length; i++) {
      bars.bits[i] = (L.mark.bits[i] != 0 &&
              onRoad.bits[i] != 0 &&
              inPark.bits[i] == 0)
          ? 1
          : 0;
    }
    // 횡단보도는 **막대 여러 개가 나란히** 있는 것이다. 그냥 '도로 위의 무늬'로
    // 잡으면 연석·화단 테두리까지 360개가 걸린다. 뭉치 안에 막대가 셋 이상
    // 있고, 뭉친 넓이를 다 채우지 않는(줄무늬라 성긴) 것만 남긴다.
    final barLabel = label4(bars, minArea: 4);
    final cl = label4(closeM(bars, 5), minArea: 160);
    final barsIn = List<int>.filled(cl.count + 1, 0);
    for (var id = 1; id <= barLabel.count; id++) {
      final k = id - 1;
      if (barLabel.area[k] < 4) continue;
      final cx = (barLabel.minX[k] + barLabel.maxX[k]) ~/ 2;
      final cy = (barLabel.minY[k] + barLabel.maxY[k]) ~/ 2;
      final lab = cl.labels[cy * gw + cx];
      if (lab > 0) barsIn[lab]++;
    }
    for (var id = 1; id <= cl.count; id++) {
      final k = id - 1;
      final a = cl.area[k] * res * res;
      if (a < 14 || a > 160) continue;
      if (barsIn[id] < 3) continue;
      final w = (cl.maxX[k] - cl.minX[k] + 1) * res;
      final h = (cl.maxY[k] - cl.minY[k] + 1) * res;
      final lng = math.max(w, h), sht = math.min(w, h);
      if (lng < 4 || lng > 24 || sht < 2.0 || lng / sht < 1.5) continue;
      final fillRatio = a / (w * h);
      if (fillRatio > 0.85) continue; // 꽉 찬 건 줄무늬가 아니다
      crosswalks.add({
        'c': [
          _r1(ox + (cl.minX[k] + cl.maxX[k]) / 2 * res),
          _r1(oy + (cl.minY[k] + cl.maxY[k]) / 2 * res),
        ],
        'w': (sht * 10).round() / 10,
        'l': (lng * 10).round() / 10,
        'a': w >= h ? 0 : 90,
      });
    }
  }

  final pois = extractPois();
  stdout.writeln('국도 ${majors.length}  주차칸 ${stalls.length}구역  '
      '횡단보도 ${crosswalks.length}  POI ${pois.length}');

  // ── 6.5 필드 라인 ─────────────────────────────────────────────
  // 잔디 폴리곤 **안쪽**의 초록 아닌 밝은 픽셀 = 축구장 선·트랙 레인·코트 라인.
  // 잔디를 뽑을 때 이 선들을 메워버리기 때문에(closeM), 따로 되살려야 보인다.
  final fieldLines = <List<Pt>>[];
  {
    // 녹지 폴리곤은 매끈하게 다듬어 둔 것이라 실제 잔디 픽셀보다 바깥으로
    // 조금 부푼다. 그대로 빼면 **가장자리 테두리가 통째로 '선'으로 잡혀**
    // 지도에 가위로 오린 듯한 바늘이 남는다(실측 6개, 길이 15~77m).
    // 안쪽으로 4셀(1.2m) 깎고 나서 빼면 테두리가 걸리지 않는다.
    final greenMask = erode(
        rasterize([
          for (final r in greens)
            [
              for (final p in r) [p.x, p.y]
            ]
        ], gw, gh, ox, oy, res),
        3);
    final lineRaw = Mask(gw, gh);
    for (var i = 0; i < lineRaw.bits.length; i++) {
      lineRaw.bits[i] =
          (greenMask.bits[i] != 0 && L.green.bits[i] == 0) ? 1 : 0;
    }
    final ll = label4(openM(lineRaw, 1), minArea: 30);
    for (var id = 1; id <= ll.count; id++) {
      final k = id - 1;
      if (ll.area[k] < 30) continue;
      final crop = ll.crop(id, pad: 4);
      final o = ll.cropOrigin(id, pad: 4);
      for (final l in traceSmooth(crop,
          blurR: 1, blurN: 1, round: 0, preEps: 0.7, minLoopArea: 20)) {
        final ring = [
          for (final p in l) Pt(ox + (p.x + o[0]) * res, oy + (p.y + o[1]) * res)
        ];
        // 그래도 남는 실오라기는 버린다. 평균 폭(2·면적/둘레)이 1m도 안
        // 되면서 15m 넘게 뻗은 것은 운동장 선이 아니라 찌꺼기다.
        if (isSliver(ring, maxWidth: 1.0, minLength: 15)) continue;
        fieldLines.add(ring);
      }
    }
  }
  stdout.writeln('필드 라인 ${fieldLines.length}개');

  // ── 7. 씽크로율 ───────────────────────────────────────────────
  // 뽑아낸 폴리곤을 같은 격자에 도로 찍어, 원본 픽셀 분류와 얼마나 겹치는지
  // 잰다(IoU). "사진과 얼마나 똑같나"에 숫자로 답하는 유일한 방법이고,
  // 임계값을 건드렸을 때 조용히 나빠지는 걸 잡아준다.
  double iou(Mask src, List<List<Pt>> polys, {List<List<Pt>> minus = const []}) {
    final rast = rasterize([
      for (final r in polys)
        [
          for (final p in r) [p.x, p.y]
        ]
    ], gw, gh, ox, oy, res);
    if (minus.isNotEmpty) {
      final m = rasterize([
        for (final r in minus)
          [
            for (final p in r) [p.x, p.y]
          ]
      ], gw, gh, ox, oy, res);
      for (var i = 0; i < rast.bits.length; i++) {
        if (m.bits[i] != 0) rast.bits[i] = 0;
      }
    }
    var inter = 0, uni = 0;
    for (var i = 0; i < rast.bits.length; i++) {
      final a = src.bits[i] != 0, b = rast.bits[i] != 0;
      if (a && b) inter++;
      if (a || b) uni++;
    }
    return uni == 0 ? 0 : inter / uni;
  }

  final bldSrc = Mask(gw, gh);
  for (var i = 0; i < bldSrc.bits.length; i++) {
    bldSrc.bits[i] =
        paleIn.bits[i] != 0 ? 1 : 0;
  }
  stdout.writeln('── 씽크로율(IoU, 원본 픽셀 분류 대비) ──');
  // 운동시설도 원본에서는 같은 '옅은 채움'이라 함께 비교해야 공평하다
  stdout.writeln('  건물   ${(iou(bldSrc, [...blds, ...facils]) * 100).toStringAsFixed(1)}%');
  stdout.writeln('  포장면 ${(iou(plaza, outers, minus: holes) * 100).toStringAsFixed(1)}%  (도로 뺀 광장·마당 대비)');
  stdout.writeln('  녹지   ${(iou(L.green, greens) * 100).toStringAsFixed(1)}%');
  stdout.writeln('  부지   ${(iou(closeM(coarse, 18).upscaleTo(gw, gh, cf), boundary) * 100).toStringAsFixed(1)}%');
  // 직각화·직선펴기가 포기하면 물결치는 원본이 그대로 나간다. 건물이
  // 흐물흐물해 보이면 여기부터 본다.
  stdout.writeln('  직각화 시도 $regularizeTried '
      '· 면적포기 $regularizeGaveUp · 꼭짓점실패 $regularizeNoCorners'
      ' | 직선펴기 포기 $straightenGaveUp/$straightenTried');

  emit(boundary, greens, greenOutside, waters, facils, parks, blds, outers, holes, majors,
      fieldLines, stalls, crosswalks, pois);
  debugPng(L, road, parkMask, boundary, blds, facils, parks);
}

String desc(List<Pt> r) {
  final cb = polyCenterBox(r);
  return '중심(${cb[0].x.round()},${cb[0].y.round()}) '
      '${cb[1].x.round()}x${cb[1].y.round()}m '
      '${polyArea(r).round()}㎡ 점${r.length}';
}

// ───────────────────────── 출력 ─────────────────────────
/// 기하만 담은 중간 산출물. tool/build_index.dart가 이걸 읽어
/// VWorld에서 id·주소·층수를 승계하고 최종 에셋을 만든다.
///
/// Dart const 대신 JSON으로 내는 이유: 좌표가 4만 개를 넘어가면 const 배열이
/// 웹 번들에 통째로 컴파일돼 1MB에 육박한다. 에셋은 gzip으로 전송되고
/// JS로 컴파일되지 않는다.
void emit(
  List<List<Pt>> boundary,
  List<List<Pt>> greens,
  List<bool> greenOutside,
  List<List<Pt>> waters,
  List<List<Pt>> facils,
  List<List<Pt>> parks,
  List<List<Pt>> blds,
  List<List<Pt>> outers,
  List<List<Pt>> holes,
  List<List<Pt>> majors,
  List<List<Pt>> fieldLines,
  List<Map<String, dynamic>> stalls,
  List<Map<String, dynamic>> crosswalks,
  List<Map<String, dynamic>> pois,
) {
  List<List<List<double>>> rings(List<List<Pt>> src) => [
        for (final r in src)
          [
            for (final p in r)
              [_r1(p.x), _r1(p.y)]
          ]
      ];

  final j = <String, dynamic>{
    'note': '네이버지도 캡처에서 뽑은 지형. tool/trace_map.dart가 생성한다.',
    'origin': {'lon': 127.3544, 'lat': 36.6092},
    'outline': rings(boundary),
    'buildings': rings(blds),
    'facilities': rings(facils),
    'parking': rings(parks),
    'greens': rings(greens),
    'greensOutside': greenOutside,
    'water': rings(waters),
    'major': rings(majors),
    'fieldLines': rings(fieldLines),
    'pavement': {'outer': rings(outers), 'holes': rings(holes)},
    'parkingStalls': stalls,
    'crosswalks': crosswalks,
    'pois': pois,
  };
  File('tool/mapsrc/traced_raw.json').writeAsStringSync(jsonEncode(j));
  final kb = File('tool/mapsrc/traced_raw.json').lengthSync() ~/ 1024;
  final pts = blds.fold<int>(0, (a, r) => a + r.length) +
      outers.fold<int>(0, (a, r) => a + r.length) +
      holes.fold<int>(0, (a, r) => a + r.length);
  stdout.writeln('→ tool/mapsrc/traced_raw.json (${kb} KB, 건물+포장 ${pts}점)');

  File('tool/mapsrc/outline.json').writeAsStringSync(jsonEncode({
    'buildings': rings(blds),
    'outline': rings(boundary),
  }));
}

double _r1(double v) => (v * 10).roundToDouble() / 10;


/// 분류 결과를 PNG로 떠서 눈으로 검증한다. (2배 축소)
void debugPng(Layers l, Mask road, Mask park, List<List<Pt>> boundary,
    List<List<Pt>> blds, List<List<Pt>> facils, List<List<Pt>> parks) {
  const f = 2;
  final w = gw ~/ f, h = gh ~/ f;
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(26, 26, 30));
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      final s = (j * f) * gw + (i * f);
      int r, g, b;
      if (l.water.bits[s] != 0) {
        r = 60; g = 120; b = 190;
      } else if (l.green.bits[s] != 0) {
        r = 70; g = 150; b = 80;
      } else if (park.bits[s] != 0) {
        r = 190; g = 130; b = 60;
      } else if (l.pale.bits[s] != 0) {
        r = 120; g = 120; b = 132;
      } else if (road.bits[s] != 0) {
        r = 220; g = 210; b = 170;
      } else if (l.mark.bits[s] != 0) {
        r = 150; g = 90; b = 40;
      } else if (l.campus.bits[s] != 0) {
        r = 46; g = 56; b = 74;
      } else if (l.major.bits[s] != 0) {
        r = 210; g = 190; b = 70;
      } else if (l.outBright.bits[s] != 0) {
        r = 150; g = 150; b = 160;
      } else if (l.outGround.bits[s] != 0) {
        r = 60; g = 58; b = 52;
      } else {
        r = 26; g = 26; b = 30;
      }
      im.setPixelRgb(i, j, r, g, b);
    }
  }
  void ring(List<Pt> pts, int r, int g, int b) {
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], c = pts[(i + 1) % pts.length];
      img.drawLine(im,
          x1: ((a.x - ox) / res / f).round(),
          y1: ((a.y - oy) / res / f).round(),
          x2: ((c.x - ox) / res / f).round(),
          y2: ((c.y - oy) / res / f).round(),
          color: img.ColorRgb8(r, g, b));
    }
  }

  for (final p in boundary) {
    ring(p, 255, 90, 90);
  }
  for (final p in blds) {
    ring(p, 90, 220, 255);
  }
  for (final p in facils) {
    ring(p, 255, 140, 255);
  }
  for (final p in parks) {
    ring(p, 255, 200, 60);
  }
  File('tool/mapsrc/debug.png').writeAsBytesSync(img.encodePng(im));
  stdout.writeln('→ tool/mapsrc/debug.png ${w}x$h');
}

/// 각 셀 둘레 (2r+1)² 창 안의 켜진 셀 수. 적분영상으로 창 크기와 무관하게 O(n).
Int32List _density(Mask m, int r) {
  final sat = Int32List((m.w + 1) * (m.h + 1));
  for (var y = 0; y < m.h; y++) {
    var row = 0;
    for (var x = 0; x < m.w; x++) {
      row += m.bits[y * m.w + x];
      sat[(y + 1) * (m.w + 1) + x + 1] = sat[y * (m.w + 1) + x + 1] + row;
    }
  }
  int box(int x0, int y0, int x1, int y1) {
    x0 = x0.clamp(0, m.w);
    x1 = x1.clamp(0, m.w);
    y0 = y0.clamp(0, m.h);
    y1 = y1.clamp(0, m.h);
    return sat[y1 * (m.w + 1) + x1] -
        sat[y0 * (m.w + 1) + x1] -
        sat[y1 * (m.w + 1) + x0] +
        sat[y0 * (m.w + 1) + x0];
  }

  final out = Int32List(m.w * m.h);
  for (var y = 0; y < m.h; y++) {
    for (var x = 0; x < m.w; x++) {
      out[y * m.w + x] = box(x - r, y - r, x + r + 1, y + r + 1);
    }
  }
  return out;
}

/// 지도 마커에서 POI 위치를 뽑는다.
///
/// 마커는 화면 고정 크기라 월드에서 크기가 무의미하다 — **중심점만** 쓴다.
/// 색은 캡처에서 직접 잰 값이다:
///   72,167,245  버스정류장   148,180,242  주차장 P   249,215,138  편의점
/// 국도 노랑(252,240,180)과 편의점 앰버가 비슷해서 초록 성분으로 가른다.
List<Map<String, dynamic>> extractPois() {
  final out = <Map<String, dynamic>>[];
  kShots.forEach((f, c) {
    final im = img.decodeImage(File('tool/mapsrc/$f').readAsBytesSync())!;
    final w = im.width, h = im.height;
    final kinds = <String, Mask>{
      'bus': Mask(w, h),
      'parking': Mask(w, h),
      'store': Mask(w, h),
    };
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final tint = b - r;
        if (tint >= 120 && b >= 200) {
          kinds['bus']!.bits[y * w + x] = 1;
        } else if (tint >= 55 && tint < 120 && b >= 220 && r >= 100) {
          kinds['parking']!.bits[y * w + x] = 1;
        } else if (r >= 240 && g >= 190 && g <= 232 && b <= 200) {
          kinds['store']!.bits[y * w + x] = 1;
        }
      }
    }
    kinds.forEach((kind, m) {
      final l = label4(closeM(m, 2), minArea: 40);
      for (var id = 1; id <= l.count; id++) {
        final k = id - 1;
        if (l.area[k] < 40 || l.area[k] > 1400) continue;
        final bw = l.maxX[k] - l.minX[k] + 1, bh = l.maxY[k] - l.minY[k] + 1;
        // 마커는 동글동글하다. 길쭉하면 도로나 글자다.
        if (bw > 40 || bh > 40 || bw / bh > 2.2 || bh / bw > 2.2) continue;
        final px = (l.minX[k] + l.maxX[k]) / 2, py = (l.minY[k] + l.maxY[k]) / 2;
        out.add({
          'k': kind,
          'p': [
            _r1(px * kScale + c[0]),
            _r1(py * kScale + c[1]),
          ],
        });
      }
    });
  });
  // 캡처가 겹치는 데서 같은 마커가 두 번 잡힌다 — 6m 안쪽은 하나로 본다
  final uniq = <Map<String, dynamic>>[];
  for (final p in out) {
    var dup = false;
    for (final q in uniq) {
      if (q['k'] != p['k']) continue;
      final dx = (q['p'][0] as double) - (p['p'][0] as double);
      final dy = (q['p'][1] as double) - (p['p'][1] as double);
      if (dx * dx + dy * dy < 36) {
        dup = true;
        break;
      }
    }
    if (!dup) uniq.add(p);
  }
  return uniq;
}

/// OSM 도로가 덮는 통로를 격자에 칠한다(assets/housing/campus_roads.json).
///
/// 앱은 이 도로를 실제 폭(m)으로 긋는다 — 같은 폭의 반을 반지름으로 원을
/// 찍어 나가면 앱에서 도로 노면이 덮는 자리와 같아진다. 에셋이 없으면
/// 빈 마스크를 돌려 예전처럼 포장면 전체를 추적한다.
Mask osmCorridor() {
  final m = Mask(gw, gh);
  final f = File('assets/housing/campus_roads.json');
  if (!f.existsSync()) return m;
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  for (final r in (j['roads'] as List)) {
    final w = (r['w'] as num).toDouble();
    final rad = (w / 2) / res; // 셀 단위 반지름
    final ri = rad.ceil();
    final pts = [
      for (final p in (r['pts'] as List))
        [((p[0] as num).toDouble() - ox) / res, ((p[1] as num).toDouble() - oy) / res]
    ];
    for (var k = 0; k + 1 < pts.length; k++) {
      final ax = pts[k][0], ay = pts[k][1];
      final bx = pts[k + 1][0], by = pts[k + 1][1];
      final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
      // 반지름의 절반 간격으로 원을 찍으면 선분이 빈틈없이 덮인다.
      final steps = math.max(1, (len / math.max(1.0, rad / 2)).ceil());
      for (var s = 0; s <= steps; s++) {
        final cx = ax + (bx - ax) * s / steps;
        final cy = ay + (by - ay) * s / steps;
        final x0 = cx.round(), y0 = cy.round();
        for (var dy = -ri; dy <= ri; dy++) {
          final y = y0 + dy;
          if (y < 0 || y >= gh) continue;
          for (var dx = -ri; dx <= ri; dx++) {
            final x = x0 + dx;
            if (x < 0 || x >= gw) continue;
            if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > rad * rad) continue;
            m.bits[y * gw + x] = 1;
          }
        }
      }
    }
  }
  return m;
}
