// 버스 탭을 그림으로 확인한다(2026-11-12). 기기 없이 실제 위젯을 그대로 그린다.
//
//   flutter test test/bus_preview.dart   # → build/bus_preview/*.png
//
// 앱 글꼴(Noto Sans KR)은 Windows 글꼴 폴더에서 읽는다. 없으면 글자가 네모로
// 나오지만 배치는 확인할 수 있다. 이름이 _test로 끝나지 않아 `flutter test`
// 전체 실행에는 끼지 않는다.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/bus_card.dart';
import 'package:knue_mate/bus_model.dart';
import 'package:knue_mate/bus_route_snapshot.dart';
import 'package:knue_mate/bus_screen.dart';
import 'package:knue_mate/nearby_stop.dart';
import 'package:knue_mate/ui_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'build/bus_preview';

Future<void> _loadFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final candidates = [
    'C:/Windows/Fonts/NotoSansKR-VF.ttf',
    'C:/Windows/Fonts/malgun.ttf',
    '/System/Library/Fonts/AppleSDGothicNeo.ttc',
  ];
  final file = candidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
  if (file == null) return;
  final bytes = file.readAsBytesSync();
  // 앱이 쓰는 이름들(기본·GoogleFonts 등록명)에 모두 같은 글꼴을 건다.
  // GoogleFonts는 테스트에서 글꼴 파일을 못 찾아 비동기 오류를 낸다 — 미리보기엔 상관없다.
  String? appFamily;
  runZonedGuarded(() => appFamily = KnueTokens.fontFamily, (_, _) {});
  for (final family in {'Roboto', 'NotoSansKR', appFamily ?? 'NotoSansKR'}) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }
  // 아이콘 글꼴
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(icons.readAsBytesSync()).buffer)));
    await loader.load();
  }
}

/// 예시 차량 — 정류장 순번·남은 정거장은 노선 스냅샷에서 계산한다(실제와 같게).
BusArrival _a(String route, String at, int ud, double min, {bool api = false}) {
  final stops = kRouteStopsSnapshot[busRouteConfig(route)!.routeId]!;
  final stop = stops.firstWhere((s) => s.nodeName == at && s.upDownCd == ud);
  final next = nextTargetFor(stop.nodeOrd, snapshotTargetsFor(route))!;
  return BusArrival(
    remainStops: next.ord - stop.nodeOrd,
    currentStopName: at,
    nodeOrd: stop.nodeOrd,
    direction: next.dir,
    estimatedMinutes: min,
    etaFromApi: api,
  );
}

BusSummary _bus(int n, String type, String desc, bool direct, List<BusArrival> arr) => BusSummary(
      id: n,
      number: '$n',
      type: type,
      direction: desc,
      arrivals: arr,
      congestion: 'normal',
      isDirect: direct,
    );

// 2026-11-12 밤 실제 차량 위치를 바탕으로 한 예시.
final sampleBuses = [
  _bus(513, 'blue', '교원대 정문행 (직행)', true, [
    _a('513', '산업단지입구', 0, 36),
  ]),
  _bus(514, 'blue', '교원대 정문행 (직행)', true, [
    _a('514', '월탄1리', 0, 1.8),
    _a('514', '청주체육관', 0, 54),
  ]),
  _bus(518, 'blue', '교원대 정문행 (직행)', true, [
    _a('518', '만수공원', 1, 22.8, api: true),
  ]),
  _bus(913, 'green', '평동↔미호종점', true, const []),
  _bus(500, 'blue', '탑연삼거리 하차', false, [
    _a('500', '지서', 0, 11.1, api: true),
    _a('500', '만수공원', 1, 5.1, api: true),
  ]),
  _bus(502, 'blue', '탑연삼거리 하차', false, [
    _a('502', '시계탑', 0, 28, api: true),
    _a('502', '오송역5', 1, 17.6, api: true),
  ]),
  _bus(509, 'red', '조치원/오송', false, [
    _a('509', '죽천교', 0, 13.3, api: true),
  ]),
  _bus(511, 'blue', '탑연삼거리 하차', false, [
    _a('511', '고속버스터미널', 0, 12.9, api: true),
    _a('511', '만수초등학교', 1, 25.7),
  ]),
  _bus(747, 'red', '급행 (탑연 경유)', false, const []),
];

final sampleNearby = (
  const [
    NearbyStop(nodeId: 'CJB271000402', name: '한국교원대정문', sources: [(cityCode: 33010, nodeId: 'CJB271000402')], nodeNo: '3333', latitude: 36.60698, longitude: 127.35358, distanceMeters: 40),
    NearbyStop(nodeId: 'CJB274000278', name: '한국교원대학교입구', sources: [(cityCode: 33010, nodeId: 'CJB274000278')], nodeNo: '4031', latitude: 36.60677, longitude: 127.35436, distanceMeters: 90),
    NearbyStop(nodeId: 'CJB271000424', name: '한국교원대정문', sources: [(cityCode: 33010, nodeId: 'CJB271000424')], nodeNo: '2107', latitude: 36.60602, longitude: 127.35402, distanceMeters: 120),
  ],
  const [
    StopArrival(routeNo: '913', routeType: '지선버스', stopsAway: 1, arrivalSeconds: 72, lowFloor: true),
    StopArrival(routeNo: '513', routeType: '간선버스', stopsAway: 5, arrivalSeconds: 540, lowFloor: false),
    StopArrival(routeNo: '518', routeType: '지선버스', stopsAway: 8, arrivalSeconds: 593, lowFloor: true),
    StopArrival(routeNo: '311', routeType: '간선버스', stopsAway: 12, arrivalSeconds: 1100, lowFloor: false),
  ],
);

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  final png = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  Directory(_out).createSync(recursive: true);
  File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

Widget _app(Widget home, {required bool dark}) => RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.light, colorSchemeSeed: const Color(0xFF1E5AA8), fontFamily: 'NotoSansKR'),
        darkTheme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF1E5AA8), fontFamily: 'NotoSansKR'),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: home,
      ),
    );

void main() {
  setUpAll(_loadFonts);

  for (final dark in [false, true]) {
    final suffix = dark ? '_dark' : '';
    testWidgets('실시간 탭$suffix', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        BusAppScreen(previewBuses: sampleBuses, previewNearby: sampleNearby, initialTab: 1),
        dark: dark,
      ));
      await _shot(tester, 'realtime$suffix');
    });

    testWidgets('운행 차량 없음$suffix', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        BusAppScreen(previewBuses: const [], previewNearby: (sampleNearby.$1, const <StopArrival>[]), initialTab: 1),
        dark: dark,
      ));
      await _shot(tester, 'realtime_empty$suffix');
    });

    testWidgets('시간표 탭$suffix', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        BusAppScreen(previewBuses: sampleBuses, previewNearby: sampleNearby, initialTab: 0),
        dark: dark,
      ));
      await _shot(tester, 'timetable$suffix');
    });

    testWidgets('노선도 시트$suffix', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final bus = sampleBuses.firstWhere((b) => b.number == '511');
      await tester.pumpWidget(_app(
        Scaffold(body: ListView(children: [BusCard(bus: bus, direction: BusDirection.inbound)])),
        dark: dark,
      ));
      await tester.tap(find.byType(BusCard));
      await tester.pump(const Duration(seconds: 1));
      await _shot(tester, 'route_sheet$suffix');
    });
  }
}
