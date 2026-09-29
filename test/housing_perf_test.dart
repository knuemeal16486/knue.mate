// 자취방 지도 성능 개선(2026-09-29)이 그림을 바꾸지 않았는지, 캐시가 제대로
// 먹는지 확인한다. 시간 측정은 test/perf_map_bench.dart.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart' show KnueWeatherInfo;
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_service.dart';
import 'package:knue_mate/ui_utils.dart';

BaseBuilding _b(String id, {String? name}) => BaseBuilding(
      id: id,
      floors: 4,
      ring: const [Offset(0, 0), Offset(20, 0), Offset(20, 20), Offset(0, 20)],
      officialName: name,
    );

void main() {
  group('IsoLayoutCache', () {
    const proj = IsoProjection(scale: 2.2);
    final a = _b('a', name: '파인빌'), c = _b('c', name: '에코빌');

    test('같은 건물·같은 조건이면 지난번 모양을 그대로 쓴다', () {
      final cache = IsoLayoutCache();
      final first = layoutBuildings([a, c], proj, zoneColors: const {'a': Color(0xFF03C75A)}, cache: cache);
      final second = layoutBuildings([a, c], proj, zoneColors: const {'a': Color(0xFF03C75A)}, cache: cache);
      for (var i = 0; i < first.length; i++) {
        expect(identical(first[i], second[i]), isTrue);
      }
    });

    // 건물 하나의 모양 조건이 바뀌면(고르기·색 칠하기 등) 그 건물만 다시 만든다.
    // (고르기는 강조 이름표를 만들어 테스트에 없는 글꼴을 부르므로 색으로 본다.)
    test('한 건물만 바뀌면 그 건물만 다시 만든다', () {
      final cache = IsoLayoutCache();
      final before = {for (final x in layoutBuildings([a, c], proj, cache: cache)) x.building.id: x};
      final after = {
        for (final x in layoutBuildings([a, c], proj, zoneColors: const {'a': Color(0xFF03C75A)}, cache: cache))
          x.building.id: x,
      };
      expect(identical(before['a'], after['a']), isFalse);
      expect(after['a']!.zoneColor, const Color(0xFF03C75A));
      expect(identical(before['c'], after['c']), isTrue);
    });

    test('시점을 돌리면 다시 만든다', () {
      final cache = IsoLayoutCache();
      final before = layoutBuildings([a], proj, cache: cache).single;
      final after = layoutBuildings([a], const IsoProjection(scale: 2.2, rotation: 0.5), cache: cache).single;
      expect(identical(before, after), isFalse);
    });

    test('건물 객체가 바뀌면(모양을 고치면) 다시 만든다', () {
      final cache = IsoLayoutCache();
      final before = layoutBuildings([a], proj, cache: cache).single;
      final moved = a.copyWith(ring: const [Offset(5, 5), Offset(25, 5), Offset(25, 25), Offset(5, 25)]);
      final after = layoutBuildings([moved], proj, cache: cache).single;
      expect(identical(before, after), isFalse);
    });
  });

  test('시세 말풍선이 바뀌면 다시 그린다 — 예전엔 [시세 뱃지]를 눌러도 안 떴다', () {
    HousingMapPainter p(Map<String, String>? tags) => HousingMapPainter(
          layer: HousingMapLayer.overlay,
          buildings: const [],
          roads: CombinedRoads.empty,
          terrain: IsoTerrain.empty,
          isDark: false,
          origin: Offset.zero,
          priceTags: tags,
        );
    expect(p({'a': '300/35'}).shouldRepaint(p(const {})), isTrue);
    expect(p({'a': '300/35'}).shouldRepaint(p({'a': '300/35'})), isFalse);
  });

  testWidgets('두 층(바닥+이름표)으로 나눠 그려도 한 번에 그린 것과 픽셀이 같다', (tester) async {
    final loaded = await tester.runAsync(() async => (await CampusBase.load(), await CampusBase.loadOsmRoads()));
    final (base, osm) = loaded!;
    const proj = IsoProjection(scale: 1.0);
    final style = housingMapStyle(base.buildings);
    // 이름표·말풍선 글씨는 테스트에 없는 글꼴(google_fonts)을 불러서 뺀다 — 여기선
    // 층을 나눠도 빠지거나 겹치는 그림이 없는지를 본다.
    final blds = layoutBuildings(base.buildings, proj,
        oneRoomIds: style.oneRoomIds, zoneColors: style.zoneColors, showLabels: false);
    final roads = projectRoads(base.roads, proj);
    final b = boundsOf(blds, roads);
    final origin = Offset(-b.left + 20, -b.top + 20);
    final size = Size(b.width + 40, b.height + 40);
    final view = TransformationController();
    HousingMapPainter painter(HousingMapLayer layer) => HousingMapPainter(
          layer: layer,
          buildings: blds,
          roads: roads,
          terrain: projectTerrain(base.terrain, proj),
          landuse: projectLandUse(base.landuse, proj),
          osmRoads: projectOsmRoads(osm, proj),
          isDark: false,
          origin: origin,
          projection: proj,
          view: view,
        );
    ui.Picture record(List<HousingMapLayer> layers) {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      for (final l in layers) {
        painter(l).paint(canvas, size);
      }
      return rec.endRecording();
    }

    Future<Uint8List> pixels(ui.Picture pic) async {
      final img = await pic.toImage(size.width.round(), size.height.round());
      return (await img.toByteData())!.buffer.asUint8List();
    }

    final both = await tester.runAsync(() async => (
          await pixels(record([HousingMapLayer.all])),
          await pixels(record([HousingMapLayer.base, HousingMapLayer.overlay])),
        ));
    expect(both!.$1, equals(both.$2));
  });

  testWidgets('날씨 입자: 맑은 날엔 애니메이션을 돌리지 않는다(매 프레임 요청 안 함)', (tester) async {
    const sunny = KnueWeatherInfo(temp: 22, weatherCode: 0, windSpeed: 2);
    await tester.pumpWidget(const MaterialApp(home: Stack(children: [WeatherParticlesOverlay(weather: sunny)])));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    const rain = KnueWeatherInfo(temp: 18, weatherCode: 61, windSpeed: 2);
    await tester.pumpWidget(const MaterialApp(home: Stack(children: [WeatherParticlesOverlay(weather: rain)])));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0), reason: '비 오는 날엔 돈다');

    await tester.pumpWidget(const MaterialApp(home: Stack(children: [WeatherParticlesOverlay(weather: sunny)])));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0, reason: '다시 맑아지면 멈춘다');
  });
}
