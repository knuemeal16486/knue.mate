// 자취방 지도를 파일로 떠서 눈으로 확인하는 도구. 테스트가 아니다.
// (파일명이 _test.dart로 끝나지 않아 `flutter test`가 자동으로 집지 않는다)
//
//   flutter test test/map_preview.dart
//   → build/map_preview.png, build/map_preview_dark.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';

Future<void> shoot(WidgetTester tester, CampusBase base, bool isDark, String out) async {
  const proj = IsoProjection(scale: 2.4, rotation: 0);
  final blds = layoutBuildings(base.buildings, proj);
  final roads = projectRoads(base.roads, proj);
  final terrain = projectTerrain(base.terrain, proj);
  final landuse = projectLandUse(base.landuse, proj);
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
  testWidgets('지도 미리보기 PNG', (tester) async {
    final base = await CampusBase.load();
    stdout.writeln('건물 ${base.buildings.length}동 '
        '(교내 ${base.buildings.where((b) => b.isCampus).length}) '
        '도로 ${base.roads.length}');
    Directory('build').createSync(recursive: true);
    await shoot(tester, base, false, 'build/map_preview.png');
    await shoot(tester, base, true, 'build/map_preview_dark.png');
  });
}
