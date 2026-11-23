// 지도를 **위에서 본 그림**으로 떠서 원본 캡처와 나란히 대조하는 도구. 테스트가 아니다.
// (파일명이 _test.dart로 끝나지 않아 `flutter test`가 자동으로 집지 않는다)
//
//   flutter test test/map_topdown_preview.dart
//   → build/topdown_core.png · topdown_north.png · topdown_south.png
//
// 세 그림은 tool/mapsrc의 캡처(core.jpg · north.png · south.png)와 **같은 범위·
// 같은 배율**(0.619 m/px)이라, 두 파일을 번갈아 띄우면 빠진 것이 바로 보인다.
// 바닥 구조물(주차선·코트·샛길)처럼 작은 것은 [_zooms]의 확대본으로 본다.
// 앱의 HousingMapPainter를 그대로 쓴다. google_fonts 예외로 "실패"가 찍히지만
// PNG는 정상 생성된다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_service.dart';

/// 캡처와 같은 범위(월드 m).
const _shots = <String, Rect>{
  'core': Rect.fromLTRB(-201, -215, 909, 307),
  'north': Rect.fromLTRB(-237, -713, 761, -191),
  'south': Rect.fromLTRB(-117, 163, 972, 683),
};

/// 확대해서 볼 곳(월드 m). 미터당 6픽셀.
const _zooms = <String, Rect>{
  // 테니스장·학군단 운동장
  'zoom_tennis': Rect.fromLTRB(480, 290, 800, 450),
  // 교육연구관·교수회관 앞 주차장
  'zoom_parking': Rect.fromLTRB(180, -230, 440, -100),
  // 제1·2체육관 옆 코트와 농구장
  'zoom_courts': Rect.fromLTRB(540, -110, 760, 110),
  // 동쪽 건물들 사이 주차칸
  'zoom_east': Rect.fromLTRB(540, 60, 800, 190),
  // 청람천문대 둘레 샛길
  'zoom_paths': Rect.fromLTRB(330, 190, 640, 420),
};

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('위에서 본 지도 PNG', (tester) async {
    final loaded = await tester.runAsync(
      () async => (await CampusBase.load(), await CampusBase.loadOsmRoads()),
    );
    final (base, osm) = loaded!;
    final style = housingMapStyle(base.buildings);

    Future<void> shoot(String name, Rect r, double ppm, {bool labels = true}) async {
      final proj = IsoProjection(scale: ppm / 0.7071, topDown: true);
      final blds = layoutBuildings(
        base.buildings,
        proj,
        oneRoomIds: style.oneRoomIds,
        zoneColors: style.zoneColors,
        displayNames: style.displayNames,
        showLabels: labels,
      );
      final size = Size(r.width * ppm, r.height * ppm);
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(Offset.zero & size, Paint()..color = mapBackgroundColor(false));
      HousingMapPainter(
        buildings: blds,
        roads: projectRoads(base.roads, proj),
        terrain: projectTerrain(base.terrain, proj),
        landuse: projectLandUse(base.landuse, proj),
        osmRoads: projectOsmRoads(osm, proj),
        isDark: false,
        origin: -proj.project(r.left, r.top),
        projection: proj,
      ).paint(canvas, size);
      final pic = rec.endRecording();
      await tester.runAsync(() async {
        final img = await pic.toImage(size.width.round(), size.height.round());
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('build/topdown_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      stdout.writeln('build/topdown_$name.png');
    }

    for (final e in _shots.entries) {
      await shoot(e.key, e.value, 1 / 0.619);
    }
    for (final e in _zooms.entries) {
      await shoot(e.key, e.value, 6, labels: false);
    }
    tester.takeException();
  });
}
