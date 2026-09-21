// 자취방 지도를 파일로 떠서 눈으로 확인하는 도구. 테스트가 아니다.
// (파일명이 _test.dart로 끝나지 않아 `flutter test`가 자동으로 집지 않는다)
//
//   flutter test test/map_preview.dart
//   → build/map_preview.png, build/map_preview_dark.png
//
// **앱의 HousingMapPainter를 그대로** 쓴다. tool/preview_iso.dart는 칠하는
// 순서를 따로 흉내 낸 것이라 앱과 어긋날 수 있다 — 실제로 OSM 도로를
// 교내 지형이 덮어 가리는 버그를 그쪽 미리보기로는 못 봤다. 앱에서 어떻게
// 보이는지 판단할 땐 이 도구를 쓴다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_service.dart';

Future<void> shoot(
  WidgetTester tester,
  CampusBase base,
  List<OsmRoad> osm,
  bool isDark,
  String out,
) async {
  const proj = IsoProjection(scale: 2.4, rotation: 0);
  // 화면과 같은 색칠 규칙 — 월탄3길 초록·원룸 이름표까지 앱 그대로 나온다.
  // (제보·관리자 수정은 서버 값이라 여기선 빈 채로 본다)
  final style = housingMapStyle(base.buildings);
  final blds = layoutBuildings(
    base.buildings,
    proj,
    oneRoomIds: style.oneRoomIds,
    zoneColors: style.zoneColors,
    displayNames: style.displayNames,
  );
  final roads = projectRoads(base.roads, proj);
  final terrain = projectTerrain(base.terrain, proj);
  final landuse = projectLandUse(base.landuse, proj);
  // 도로는 OSM 중심선이다 — 이걸 빼면 앱과 다른 그림을 보고 판단하게 된다.
  final osmRoads = projectOsmRoads(osm, proj);
  final b = boundsOf(blds, roads);
  final origin = Offset(-b.left + 40, -b.top + 40);
  final size = Size(b.width + 80, b.height + 80);

  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
      Offset.zero & size, Paint()..color = mapBackgroundColor(isDark));
  HousingMapPainter(
    buildings: blds,
    roads: roads,
    terrain: terrain,
    landuse: landuse,
    osmRoads: osmRoads,
    isDark: isDark,
    origin: origin,
    showBuildingNumbers: true,
  ).paint(canvas, size);
  final pic = rec.endRecording();
  // flutter_test에서 실제 래스터화는 runAsync 밖에서 영영 안 끝난다.
  await tester.runAsync(() async {
    final img = await pic.toImage(size.width.round(), size.height.round());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File(out).writeAsBytesSync(png!.buffer.asUint8List());
  });
  stdout.writeln('$out  ${size.width.round()}x${size.height.round()}');
}

void main() {
  // 이름표 글씨가 google_fonts를 쓰는데, 테스트에선 네트워크가 막혀 폰트를
  // 받으려다 실패로 끝난다. 기하를 보려는 도구라 글씨체는 상관없으니 끈다.
  // (끄면 "에셋에 폰트가 없다"는 예외가 남아 결과가 실패로 찍히지만, PNG는
  //  그 전에 다 써진다. 이름표는 대체 글꼴이라 검은 네모로 보인다.)
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('지도 미리보기 PNG', (tester) async {
    // 에셋 읽기도 runAsync 안에서 — 테스트 본문은 가짜 시간이라 실제
    // 파일 읽기를 바깥에서 기다리면 제한 시간까지 매달린다.
    final loaded = await tester.runAsync(() async {
      final base = await CampusBase.load();
      final osm = await CampusBase.loadOsmRoads();
      return (base, osm);
    });
    final (base, osm) = loaded!;
    stdout.writeln('건물 ${base.buildings.length}동 '
        '(교내 ${base.buildings.where((b) => b.isCampus).length}) '
        '도로 ${base.roads.length} · OSM ${osm.length}');
    Directory('build').createSync(recursive: true);
    await shoot(tester, base, osm, false, 'build/map_preview.png');
    await shoot(tester, base, osm, true, 'build/map_preview_dark.png');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
