// 자취방 지도 성능 측정 도구. 테스트가 아니다(`flutter test`가 자동으로 안 집는다).
//
//   flutter test test/perf_map_bench.dart
//
// 앱과 같은 함수·painter를 그대로 불러 단계별 시간을 잰다(10번 중 중앙값).
// 테스트 환경(JIT)이라 절대값은 기기와 다르지만, 어디가 무거운지 비교하는 데 쓴다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_service.dart';

double _median(List<double> xs) => (xs..sort())[xs.length ~/ 2];

double time(void Function() f, {int n = 10}) {
  f(); // 데우기
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    f();
    out.add(sw.elapsedMicroseconds / 1000);
  }
  return _median(out);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('지도 성능', (tester) async {
    final loaded = await tester.runAsync(() async {
      final base = await CampusBase.load();
      final osm = await CampusBase.loadOsmRoads();
      return (base, osm);
    });
    final (base, osm) = loaded!;
    const proj = IsoProjection(scale: 2.2, rotation: 0);

    late HousingMapStyle style;
    late List<IsoBuilding> blds;
    final r = <String, double>{};
    r['housingMapStyle'] = time(() => style = housingMapStyle(base.buildings));
    r['layoutBuildings'] = time(() => blds = layoutBuildings(base.buildings, proj,
        oneRoomIds: style.oneRoomIds, zoneColors: style.zoneColors, displayNames: style.displayNames));
    late CombinedRoads roads;
    late IsoTerrain terrain;
    late IsoLandUse landuse;
    late IsoOsmRoads osmRoads;
    r['projectRoads'] = time(() => roads = projectRoads(base.roads, proj));
    r['projectOsmRoads'] = time(() => osmRoads = projectOsmRoads(osm, proj));
    r['projectTerrain'] = time(() => terrain = projectTerrain(base.terrain, proj));
    r['projectLandUse'] = time(() => landuse = projectLandUse(base.landuse, proj));
    final b = boundsOf(blds, roads);
    final origin = Offset(-b.left + 80, -b.top + 80);
    final size = Size(b.width + 160, b.height + 160);
    final view = TransformationController(Matrix4.identity()..scale(1.5));

    HousingMapPainter painter() => HousingMapPainter(
          buildings: blds,
          roads: roads,
          terrain: terrain,
          landuse: landuse,
          osmRoads: osmRoads,
          isDark: false,
          origin: origin,
          projection: proj,
          view: view,
        );
    r['paint (한 프레임, 전체)'] = time(() {
      final rec = ui.PictureRecorder();
      painter().paint(Canvas(rec), size);
      rec.endRecording();
    });

    // ── 바뀐 뒤: 앱이 실제로 타는 길 ──
    // 건물 하나를 누를 때: 캐시가 있으면 강조가 바뀐 건물만 다시 만든다.
    final cache = IsoLayoutCache();
    layoutBuildings(base.buildings, proj,
        oneRoomIds: style.oneRoomIds, zoneColors: style.zoneColors,
        displayNames: style.displayNames, cache: cache);
    var sel = 0;
    final ids = base.buildings.map((b) => b.id).toList();
    r['layoutBuildings (캐시, 건물 선택)'] = time(() {
      sel = (sel + 1) % ids.length;
      layoutBuildings(base.buildings, proj,
          selectedId: ids[sel],
          oneRoomIds: style.oneRoomIds, zoneColors: style.zoneColors,
          displayNames: style.displayNames, cache: cache);
    });
    // 확대·축소할 때: 이름표 층만 다시 그린다(바닥 층은 캐시된 그림).
    r['paint (확대 중, 이름표 층만)'] = time(() {
      final rec = ui.PictureRecorder();
      HousingMapPainter(
        layer: HousingMapLayer.overlay,
        buildings: blds,
        roads: roads,
        terrain: terrain,
        isDark: false,
        origin: origin,
        projection: proj,
        view: view,
      ).paint(Canvas(rec), size);
      rec.endRecording();
    });

    for (final e in r.entries) {
      stdout.writeln('${e.key.padRight(28)} ${e.value.toStringAsFixed(2)} ms');
    }
    stdout.writeln('건물 ${blds.length} · 캔버스 ${size.width.round()}x${size.height.round()}');
    tester.takeException();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
