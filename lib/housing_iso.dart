import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'ui_utils.dart' show KnueTokens;

/// 건물 용도 — 지붕 색이 여기서 갈린다.
///
/// 예전에는 이름에 '본부'·'도서관'이 들어있나 훑어서 색을 정했다. 이름이 안 붙은
/// 동은 전부 기본색으로 빠져 들쭉날쭉해 보였다. 이제 대장에 못박아 둔다.
enum BuildingUse {
  academic,
  library,
  student,
  dorm,
  sports,
  culture,
  training,
  admin,
  affiliate,
  etc;

  static BuildingUse from(String? k) {
    for (final v in values) {
      if (v.name == k) return v;
    }
    return BuildingUse.etc;
  }
}

/// 지도에 그릴 건물 한 동
class BaseBuilding {
  final String id;
  final String? officialName;
  final int floors;
  final String? road;
  final String? buildingNo;
  final List<Offset> ring;
  final bool isCampus;

  /// 지도에 찍는 번호. 사람이 "몇 번 건물"이라고 짚으라고 있는 값이다.
  /// 교내 건물에만 붙는다.
  final int? mapNo;

  /// 용도. 지붕 색이 여기서 갈린다 — 이름 부분문자열 추측을 대신한다.
  final BuildingUse? use;

  const BaseBuilding({
    required this.id,
    required this.floors,
    required this.ring,
    this.officialName,
    this.road,
    this.buildingNo,
    this.isCampus = false,
    this.mapNo,
    this.use,
  });

  String get addressLabel {
    final parts = [
      if (road != null) road!,
      if (buildingNo != null && buildingNo!.isNotEmpty) buildingNo!,
    ];
    return parts.isEmpty ? '주소 정보 없음' : parts.join(' ');
  }

  Offset get center {
    var minX = ring.first.dx, maxX = ring.first.dx;
    var minY = ring.first.dy, maxY = ring.first.dy;
    for (final p in ring) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  double get footprintArea {
    var a = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final p = ring[i], q = ring[(i + 1) % ring.length];
      a += p.dx * q.dy - q.dx * p.dy;
    }
    return a.abs() / 2;
  }
}

/// 도로 또는 보행로 중심선
/// OpenStreetMap 도로 중심선 한 줄(ODbL).
///
/// 캡처에서 포장면을 **면으로** 떠내던 방식은 천장이 있었다 — 충실도를
/// 올리면 가장자리가 굽고, 곧게 펴면 길이 제자리를 벗어났다(IoU 91%→80%).
/// 실제 지도는 도로를 면이 아니라 **중심선을 굵기로 그어** 그린다. 그래야
/// 양 가장자리가 정확히 평행하고 교차점이 깔끔하다.
///
/// OSM 중심선은 사람이 측량해 그려 둔 것이라 애초에 곧다. 정합도 확인했다 —
/// OSM 도로 점이 우리 교내 건물 안에 떨어지는 비율 0.6%.
///
/// ⚠️ ODbL이라 화면에 "© OpenStreetMap 기여자" 표기가 있어야 한다.
@immutable
class OsmRoad {
  /// road(차도) · walk(보행로) · steps(계단) · path(오솔길) · major(간선)
  final String kind;

  /// 실제 도로 폭(m). 화면 폭은 여기에 배율을 곱해 낸다 — 확대하면 길도
  /// 같이 넓어져야 한다.
  final double widthM;
  final List<Offset> points;
  final String? name;

  const OsmRoad({
    required this.kind,
    required this.widthM,
    required this.points,
    this.name,
  });
}

class BaseRoad {
  final List<Offset> points;
  final String type; // 'major', 'campus_main', 'campus_sec', 'walkway'
  const BaseRoad(this.points, {this.type = 'campus_main'});
}

/// 횡단보도 데이터
class BaseCrosswalk {
  final Offset center;
  final double width;
  final double length;
  final double angleDeg;
  const BaseCrosswalk({
    required this.center,
    required this.width,
    required this.length,
    required this.angleDeg,
  });
}

/// 회전교차로 / 로터리 섬
class BaseRoundaboutIsland {
  final Offset center;
  final double radius;
  const BaseRoundaboutIsland({required this.center, required this.radius});
}

/// 캠퍼스 지형/녹지/수계/부지경계/체육시설/조경 데이터
/// 주차장 빗살. 선분을 수천 개 저장하는 대신 **방향과 간격**만 재둔다.
class ParkingStall {
  final double angle; // 라디안
  final double pitch; // m
  const ParkingStall(this.angle, this.pitch);
}

/// 지도 마커. 화면 고정 크기라 월드 크기는 뜻이 없고 중심점만 쓴다.
class MapPoi {
  final String kind; // bus | parking | store
  final Offset at;
  const MapPoi(this.kind, this.at);
}

/// 네이버지도 캡처에서 그대로 뽑은 바닥. 이쪽이 지도의 정답이다.
class TracedGround {
  final List<List<Offset>> campusOutline;

  /// 포장면(도로·광장). [pavementHoles]와 한 Path에 넣고 evenOdd로 칠해야
  /// 길 사이 블록이 뚫린다.
  final List<List<Offset>> pavementOutlines;
  final List<List<Offset>> pavementHoles;
  final List<List<Offset>> greens;

  /// [greens]와 같은 길이. true면 부지 밖 숲이라 흐리게 칠한다.
  /// 운동장 잔디와 산을 같은 초록으로 칠하면 지도가 요란해진다.
  final List<bool> greensOutside;
  final List<List<Offset>> sportsFacilities;
  final List<List<Offset>> parking;
  final List<List<Offset>> waterAreas;

  /// 국도 등 노란 간선.
  final List<List<Offset>> majorRoads;

  /// 운동장·코트 안쪽의 흰 선(축구장 라인·트랙 레인).
  /// 잔디를 뽑을 때 메워버리는 부분이라 따로 들고 있다가 위에 얹는다.
  final List<List<Offset>> fieldLines;

  /// [parking] 인덱스 → 빗살 정보.
  final Map<int, ParkingStall> parkingStalls;
  final List<BaseCrosswalk> crosswalks;
  final List<MapPoi> pois;

  const TracedGround({
    this.campusOutline = const [],
    this.pavementOutlines = const [],
    this.pavementHoles = const [],
    this.greens = const [],
    this.greensOutside = const [],
    this.sportsFacilities = const [],
    this.parking = const [],
    this.waterAreas = const [],
    this.majorRoads = const [],
    this.fieldLines = const [],
    this.parkingStalls = const {},
    this.crosswalks = const [],
    this.pois = const [],
  });

  static const empty = TracedGround();
}

class BaseTerrain {
  /// 캡처에서 뽑은 바닥 — 부지 안팎을 통틀어 지도의 본체다.
  final TracedGround traced;

  final List<Offset> campusBoundary;
  final List<Offset> athleticTrack;
  final List<Offset> athleticPitch;
  final List<Offset> grandstand;
  final List<Offset> pond;
  final List<Offset> pondBridge;
  final List<Offset> centralPlaza;
  final List<Offset> dormCourtyard;
  final List<Offset> basketballCourt;
  final List<Offset> tennisCourt;
  final List<List<Offset>> forestAreas;
  final List<List<Offset>> contours;
  final List<List<Offset>> parkingLots;
  final List<BaseCrosswalk> crosswalks;
  final List<BaseRoundaboutIsland> roundaboutIslands;
  final List<Offset> trees;

  const BaseTerrain({
    this.traced = TracedGround.empty,
    this.campusBoundary = const [],
    this.athleticTrack = const [],
    this.athleticPitch = const [],
    this.grandstand = const [],
    this.pond = const [],
    this.pondBridge = const [],
    this.centralPlaza = const [],
    this.dormCourtyard = const [],
    this.basketballCourt = const [],
    this.tennisCourt = const [],
    this.forestAreas = const [],
    this.contours = const [],
    this.parkingLots = const [],
    this.crosswalks = const [],
    this.roundaboutIslands = const [],
    this.trees = const [],
  });

  static const empty = BaseTerrain();
}

/// 에셋으로 구워둔 기본 지도
/// 지적도(LP_PA_CBND_BUBUN)의 지목으로 나눈 땅 용도.
///
/// 네이버지도가 깔끔해 보이는 이유는 건물이 아니라 **바닥**에 있다 —
/// 학교·논밭·산·물·도로가 각각 다른 색 면으로 깔려 있어서, 건물을 지우고 봐도
/// 지형이 읽힌다. 그래서 건물보다 먼저 이 면들을 깐다.
enum LandUse {
  /// 학교용지. 교원대 부지가 여기 해당한다.
  campus,
  road,
  water,
  farm,
  forest,
  park;

  static LandUse? fromKey(String? key) {
    for (final v in values) {
      if (v.name == key) return v;
    }
    return null;
  }
}

/// 용도별 땅 한 필지.
class BaseLandUse {
  final LandUse use;
  final List<Offset> ring;
  const BaseLandUse(this.use, this.ring);
}

/// 캡처 3장이 덮는 월드 범위 (x0, y0, x1, y1).
///
/// **이 안에서는 사진이 정답이다.** VWorld 도로·지적·건물은 여기 밖에만 남긴다.
/// 사용자가 명시한 원칙이고, 실제로도 VWorld는 교내 건물이 41동뿐이고 층수가
/// 거의 비어 있다.
const List<List<double>> kShotBounds = [
  [-201.2, -215.0, 908.7, 306.8], // core
  [-236.5, -712.5, 760.7, -191.3], // north
  [-116.8, 163.5, 972.0, 682.8], // south
];

bool _inShots(Offset p) {
  for (final b in kShotBounds) {
    if (p.dx >= b[0] && p.dx <= b[2] && p.dy >= b[1] && p.dy <= b[3]) {
      return true;
    }
  }
  return false;
}

class CampusBase {
  final List<BaseBuilding> buildings;
  final List<BaseRoad> roads;
  final BaseTerrain terrain;

  /// 지적 기반 용도별 바닥면. 건물보다 아래에 깔린다.
  final List<BaseLandUse> landuse;

  const CampusBase({
    required this.buildings,
    required this.roads,
    this.terrain = BaseTerrain.empty,
    this.landuse = const [],
  });

  static const empty = CampusBase(
    buildings: [],
    roads: [],
    terrain: BaseTerrain.empty,
    landuse: [],
  );

  /// OSM 도로 중심선(ODbL). 별도 에셋이라 따로 읽는다.
  static Future<List<OsmRoad>> loadOsmRoads() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/housing/campus_roads.json',
      );
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return [
        for (final r in (j['roads'] as List))
          OsmRoad(
            kind: r['k'] as String? ?? 'road',
            widthM: (r['w'] as num?)?.toDouble() ?? 5,
            name: r['n'] as String?,
            points: [
              for (final p in (r['pts'] as List))
                Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
            ],
          ),
      ];
    } catch (e) {
      // 도로가 없어도 지도는 떠야 한다.
      debugPrint('campus_roads.json 로드 실패: $e');
      return const [];
    }
  }

  static Future<CampusBase> load() async {
    final raw = await rootBundle.loadString('assets/housing/campus_base.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    // 사진에서 뽑은 지형. 이쪽이 정답이고 campus_base(VWorld)는 사진 밖 여백용이다.
    final tr =
        jsonDecode(
              await rootBundle.loadString('assets/housing/campus_traced.json'),
            )
            as Map<String, dynamic>;

    List<Offset> pts(dynamic list) => (list as List)
        .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList();

    List<List<Offset>> listOfPts(dynamic list) {
      if (list is! List) return [];
      return list.map((item) => pts(item)).toList();
    }

    // 캠퍼스 지형은 캡처에서 그대로 뽑은 것을 쓴다.
    // 예전엔 운동장·코트 위치를 규격 치수로 추정해 얹었는데, 실제와 어긋났다.
    final pave = tr['pavement'] as Map<String, dynamic>;
    final traced = TracedGround(
      campusOutline: listOfPts(tr['outline']),
      pavementOutlines: listOfPts(pave['outer']),
      pavementHoles: listOfPts(pave['holes']),
      greens: listOfPts(tr['greens']),
      greensOutside: [
        for (final v in (tr['greensOutside'] as List? ?? [])) v == true,
      ],
      sportsFacilities: listOfPts(tr['facilities']),
      parking: listOfPts(tr['parking']),
      waterAreas: listOfPts(tr['water']),
      majorRoads: listOfPts(tr['major']),
      fieldLines: listOfPts(tr['fieldLines']),
      parkingStalls: {
        for (final s in (tr['parkingStalls'] as List? ?? []))
          (s['i'] as num).toInt(): ParkingStall(
            (s['a'] as num).toDouble(),
            (s['p'] as num).toDouble(),
          ),
      },
      crosswalks: [
        for (final c in (tr['crosswalks'] as List? ?? []))
          BaseCrosswalk(
            center: Offset(
              (c['c'][0] as num).toDouble(),
              (c['c'][1] as num).toDouble(),
            ),
            width: (c['w'] as num).toDouble(),
            length: (c['l'] as num).toDouble(),
            angleDeg: (c['a'] as num).toDouble(),
          ),
      ],
      pois: [
        for (final p in (tr['pois'] as List? ?? []))
          MapPoi(
            p['k'] as String,
            Offset(
              (p['p'][0] as num).toDouble(),
              (p['p'][1] as num).toDouble(),
            ),
          ),
      ],
    );
    BaseTerrain parsedTerrain = BaseTerrain(traced: traced);
    if (json.containsKey('terrain')) {
      final t = json['terrain'] as Map<String, dynamic>;
      final af = t['athleticField'] as Map<String, dynamic>?;

      final cwList = <BaseCrosswalk>[];
      if (t['crosswalks'] is List) {
        for (final cw in t['crosswalks'] as List) {
          final m = cw as Map<String, dynamic>;
          final c = m['center'] as List;
          cwList.add(
            BaseCrosswalk(
              center: Offset(
                (c[0] as num).toDouble(),
                (c[1] as num).toDouble(),
              ),
              width: (m['width'] as num).toDouble(),
              length: (m['length'] as num).toDouble(),
              angleDeg: (m['angle'] as num).toDouble(),
            ),
          );
        }
      }

      final riList = <BaseRoundaboutIsland>[];
      if (t['roundaboutIslands'] is List) {
        for (final ri in t['roundaboutIslands'] as List) {
          final m = ri as Map<String, dynamic>;
          final c = m['center'] as List;
          riList.add(
            BaseRoundaboutIsland(
              center: Offset(
                (c[0] as num).toDouble(),
                (c[1] as num).toDouble(),
              ),
              radius: (m['radius'] as num).toDouble(),
            ),
          );
        }
      }

      parsedTerrain = BaseTerrain(
        // 캡처에서 뽑은 바닥은 에셋 terrain이 있어도 그대로 유지한다
        traced: traced,
        campusBoundary: t['campusBoundary'] != null
            ? pts(t['campusBoundary'])
            : [],
        athleticTrack: af != null && af['track'] != null
            ? pts(af['track'])
            : [],
        athleticPitch: af != null && af['pitch'] != null
            ? pts(af['pitch'])
            : [],
        grandstand: t['grandstand'] != null ? pts(t['grandstand']) : [],
        pond: t['pond'] != null ? pts(t['pond']) : [],
        pondBridge: t['pondBridge'] != null ? pts(t['pondBridge']) : [],
        centralPlaza: t['centralPlaza'] != null ? pts(t['centralPlaza']) : [],
        dormCourtyard: t['dormCourtyard'] != null
            ? pts(t['dormCourtyard'])
            : [],
        basketballCourt: t['basketballCourt'] != null
            ? pts(t['basketballCourt'])
            : [],
        tennisCourt: t['tennisCourt'] != null ? pts(t['tennisCourt']) : [],
        forestAreas: listOfPts(t['forestAreas']),
        contours: listOfPts(t['contours']),
        parkingLots: listOfPts(t['parkingLots']),
        crosswalks: cwList,
        roundaboutIslands: riList,
        trees: t['trees'] != null ? pts(t['trees']) : [],
      );
    }

    // 건물은 한 곳에서만 온다 — tool/build_index.dart가 이미 섞어 놓았다.
    //   교내: 사진에서 뽑은 바닥면 (VWorld는 교내가 41동뿐이고 층수도 비어 있다)
    //   교외: VWorld 지적 그대로 (사진에서 뽑으면 흐린 구역 원룸을 놓친다)
    final tracedBuildings = <BaseBuilding>[
      for (final b in (tr['buildings'] as List))
        BaseBuilding(
          id: b['id'] as String,
          officialName: b['name'] as String?,
          floors: (b['floors'] as num).toInt(),
          road: b['road'] as String?,
          buildingNo: b['bno'] as String?,
          ring: pts(b['ring']),
          isCampus: (b['campus'] as bool?) ?? false,
          mapNo: (b['no'] as num?)?.toInt(),
          use: BuildingUse.from(b['use'] as String?),
        ),
    ];

    return CampusBase(
      buildings: tracedBuildings,
      // 캡처가 덮는 범위에서는 VWorld 도로·지적을 아예 쓰지 않는다.
      //
      // 캡처가 실측보다 정확하다 — VWorld는 교내 건물이 41동뿐이고 층수도 거의
      // 비어 있다. 부지 안은 campus_traced.dart 하나만 그리고, VWorld는 부지
      // **밖**(원룸촌·논밭·국도)에만 남긴다. 정합·검증용으로는 계속 쓴다.
      roads: [
        ...(json['roads'] as List).map((r) {
          final m = r as Map<String, dynamic>;
          final p = pts(m['pts']);
          if (p.isEmpty || p.every(_inShots)) return null;
          return BaseRoad(p, type: (m['type'] as String?) ?? 'campus_main');
        }).whereType<BaseRoad>(),
      ],
      landuse: ((json['landuse'] as List?) ?? [])
          .map((l) {
            final m = l as Map<String, dynamic>;
            final use = LandUse.fromKey(m['g'] as String?);
            if (use == null) return null;
            final ring = pts(m['ring']);
            // 도로·학교용지는 사진 몫이라 뺀다. 논밭·임야·물은 남겨서
            // 부지 밖 맥락을 준다.
            if (ring.isEmpty) return null;
            if (use == LandUse.road || use == LandUse.campus) return null;
            return BaseLandUse(use, ring);
          })
          .whereType<BaseLandUse>()
          .toList(),
      terrain: parsedTerrain,
    );
  }
}

/// 360도 회전 2.5D 아이소메트릭 투영
class IsoProjection {
  final double scale;
  final double floorHeight;
  final double rotation;

  const IsoProjection({
    this.scale = 2.0,
    this.floorHeight = 3.0,
    this.rotation = 0.0,
  });

  Offset project(double x, double y, [double z = 0]) {
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    final rx = x * cosR - y * sinR;
    final ry = x * sinR + y * cosR;
    return Offset(
      (rx - ry) * 0.5 * scale,
      (rx + ry) * 0.25 * scale - z * scale,
    );
  }

  double heightOf(BaseBuilding b) => b.floors * floorHeight;

  double depthKey(BaseBuilding b) {
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    final c = b.center;
    final rx = c.dx * cosR - c.dy * sinR;
    final ry = c.dx * sinR + c.dy * cosR;
    return rx + ry;
  }
}

/// 화면 투영 지형 요소 (네이버 지도 스타일)
class IsoTerrain {
  /// 캡처에서 뽑은 층 — 부지 테두리·포장면·녹지·운동시설·수면.
  final Path campusOutline;
  final Path pavement;
  final Path majorRoads;
  final Path fieldLines;

  /// 주차 구획선·횡단보도 줄무늬. 월드에서 만들어 투영했기 때문에 바닥에
  /// 누워 보인다 (화면 좌표로 그으면 아이소메트릭에서 떠 보인다).
  final Path parkingStalls;
  final Path crosswalkBars;

  /// 지도 마커 — 투영된 화면 좌표와 종류.
  final List<MapEntry<String, Offset>> pois;
  final Path greens;
  final Path greensWood;
  final Path sportsFacilities;
  final Path parking;
  final Path waterAreas;

  final Path campusBoundary;
  final Path athleticTrack;
  final Path athleticPitch;
  final Path grandstand;
  final Path pond;
  final Path pondBridge;
  final Path centralPlaza;
  final Path dormCourtyard;
  final Path basketballCourt;
  final Path tennisCourt;
  final Path forestAreasCombined;
  final Path contoursCombined;
  final Path parkingLotsCombined;
  final Path crosswalkStripesCombined;
  final Path roundaboutIslandsCombined;

  // 네이버 지도 스타일 3D 수목 (Soft Shadow, Trunk, Dual-layer Foliage)
  final Path treeShadowsPath;
  final Path treeTrunksPath;
  final Path treeZelkovaBasePath;
  final Path treeZelkovaHighlightPath;
  final Path treeGinkgoBasePath;
  final Path treeGinkgoHighlightPath;
  final Path treeCherryBasePath;
  final Path treeCherryHighlightPath;
  final Path treePineBasePath;
  final Path treePineTopPath;

  const IsoTerrain({
    required this.campusOutline,
    required this.pavement,
    required this.majorRoads,
    required this.fieldLines,
    required this.parkingStalls,
    required this.crosswalkBars,
    required this.pois,
    required this.greens,
    required this.greensWood,
    required this.sportsFacilities,
    required this.parking,
    required this.waterAreas,
    required this.campusBoundary,
    required this.athleticTrack,
    required this.athleticPitch,
    required this.grandstand,
    required this.pond,
    required this.pondBridge,
    required this.centralPlaza,
    required this.dormCourtyard,
    required this.basketballCourt,
    required this.tennisCourt,
    required this.forestAreasCombined,
    required this.contoursCombined,
    required this.parkingLotsCombined,
    required this.crosswalkStripesCombined,
    required this.roundaboutIslandsCombined,
    required this.treeShadowsPath,
    required this.treeTrunksPath,
    required this.treeZelkovaBasePath,
    required this.treeZelkovaHighlightPath,
    required this.treeGinkgoBasePath,
    required this.treeGinkgoHighlightPath,
    required this.treeCherryBasePath,
    required this.treeCherryHighlightPath,
    required this.treePineBasePath,
    required this.treePineTopPath,
  });

  static IsoTerrain empty = IsoTerrain(
    campusOutline: Path(),
    pavement: Path(),
    majorRoads: Path(),
    fieldLines: Path(),
    parkingStalls: Path(),
    crosswalkBars: Path(),
    pois: const [],
    greens: Path(),
    greensWood: Path(),
    sportsFacilities: Path(),
    parking: Path(),
    waterAreas: Path(),
    campusBoundary: Path(),
    athleticTrack: Path(),
    athleticPitch: Path(),
    grandstand: Path(),
    pond: Path(),
    pondBridge: Path(),
    centralPlaza: Path(),
    dormCourtyard: Path(),
    basketballCourt: Path(),
    tennisCourt: Path(),
    forestAreasCombined: Path(),
    contoursCombined: Path(),
    parkingLotsCombined: Path(),
    crosswalkStripesCombined: Path(),
    roundaboutIslandsCombined: Path(),
    treeShadowsPath: Path(),
    treeTrunksPath: Path(),
    treeZelkovaBasePath: Path(),
    treeZelkovaHighlightPath: Path(),
    treeGinkgoBasePath: Path(),
    treeGinkgoHighlightPath: Path(),
    treeCherryBasePath: Path(),
    treeCherryHighlightPath: Path(),
    treePineBasePath: Path(),
    treePineTopPath: Path(),
  );
}

class _Wall {
  final Path path;
  final double depth;
  final bool facingLeft;
  const _Wall(this.path, this.depth, this.facingLeft);
}

class IsoBuilding {
  final BaseBuilding building;
  final Path top;
  final List<_Wall> walls;
  final Path silhouette;
  final bool highlighted;
  final bool isOneRoom;
  final Color? zoneColor;
  final String? displayName;
  final Offset topCenter;
  final TextPainter? cachedBadgePainter;

  const IsoBuilding({
    required this.building,
    required this.top,
    required this.walls,
    required this.silhouette,
    required this.topCenter,
    this.highlighted = false,
    this.isOneRoom = false,
    this.zoneColor,
    this.displayName,
    this.cachedBadgePainter,
  });
}

Path _poly(List<Offset> pts) {
  if (pts.isEmpty) return Path();
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

Path _line(List<Offset> pts) {
  if (pts.isEmpty) return Path();
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path;
}

IsoTerrain projectTerrain(BaseTerrain terrain, IsoProjection p) {
  List<Offset> projPts(List<Offset> pts) =>
      pts.map((v) => p.project(v.dx, v.dy)).toList();

  final crosswalkCombined = Path();
  for (final cw in terrain.crosswalks) {
    final rad = cw.angleDeg * math.pi / 180;
    final cosA = math.cos(rad), sinA = math.sin(rad);
    final hw = cw.width / 2;
    const numStripes = 6;
    for (var i = 0; i < numStripes; i++) {
      final t = (i / (numStripes - 1) - 0.5) * cw.length;
      final p1 = Offset(
        cw.center.dx + t * cosA - hw * sinA,
        cw.center.dy + t * sinA + hw * cosA,
      );
      final p2 = Offset(
        cw.center.dx + t * cosA + hw * sinA,
        cw.center.dy + t * sinA - hw * cosA,
      );
      final proj1 = p.project(p1.dx, p1.dy);
      final proj2 = p.project(p2.dx, p2.dy);
      crosswalkCombined.moveTo(proj1.dx, proj1.dy);
      crosswalkCombined.lineTo(proj2.dx, proj2.dy);
    }
  }

  final roundaboutCombined = Path();
  for (final ri in terrain.roundaboutIslands) {
    final islandPts = <Offset>[];
    for (var deg = 0; deg < 360; deg += 30) {
      final rad = deg * math.pi / 180;
      islandPts.add(
        Offset(
          ri.center.dx + ri.radius * math.cos(rad),
          ri.center.dy + ri.radius * math.sin(rad),
        ),
      );
    }
    roundaboutCombined.addPath(_poly(projPts(islandPts)), Offset.zero);
  }

  final forestCombined = Path();
  for (final pts in terrain.forestAreas) {
    forestCombined.addPath(_poly(projPts(pts)), Offset.zero);
  }

  final contoursCombined = Path();
  for (final pts in terrain.contours) {
    contoursCombined.addPath(_line(projPts(pts)), Offset.zero);
  }

  final parkingCombined = Path();
  for (final pts in terrain.parkingLots) {
    parkingCombined.addPath(_poly(projPts(pts)), Offset.zero);
  }

  // 네이버 지도 스타일 정갈한 3D 수목 (Soft Shadow, Trunk, Crisp Foliage)
  final treeShadows = Path();
  final treeTrunks = Path();
  final zelkovaBase = Path();
  final zelkovaHighlight = Path();
  final ginkgoBase = Path();
  final ginkgoHighlight = Path();
  final cherryBase = Path();
  final cherryHighlight = Path();
  final pineBase = Path();
  final pineTop = Path();

  for (var i = 0; i < terrain.trees.length; i++) {
    final t = p.project(terrain.trees[i].dx, terrain.trees[i].dy);

    // 1. 부드러운 타원형 드롭 섀도우
    treeShadows.addOval(
      Rect.fromCenter(
        center: Offset(t.dx + 1.5, t.dy + 2.0),
        width: 11,
        height: 6,
      ),
    );

    // 2. 나무 기둥 (Trunk)
    treeTrunks.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(t.dx - 1.0, t.dy - 5.5, 2.0, 5.5),
        const Radius.circular(0.8),
      ),
    );

    // 3. 수종별 정갈한 네이버 지도 스타일 캐노피
    if (i % 6 == 0) {
      // 은행나무 (Ginkgo - 화사하고 맑은 골든 옐로우 톤)
      ginkgoBase.addOval(
        Rect.fromCircle(center: Offset(t.dx, t.dy - 6.5), radius: 5.5),
      );
      ginkgoHighlight.addOval(
        Rect.fromCircle(center: Offset(t.dx - 1.5, t.dy - 8.0), radius: 3.2),
      );
    } else if (i % 8 == 0) {
      // 벚나무 / 단풍 (Cherry / Maple - 소프트 코랄 핑크 톤)
      cherryBase.addOval(
        Rect.fromCircle(center: Offset(t.dx, t.dy - 6.5), radius: 5.5),
      );
      cherryHighlight.addOval(
        Rect.fromCircle(center: Offset(t.dx - 1.5, t.dy - 8.0), radius: 3.2),
      );
    } else if (i % 3 == 0) {
      // 소나무 (Pine - 2단 정갈한 상록수 콘)
      pineBase.addPath(
        _poly([
          Offset(t.dx - 5.0, t.dy - 4.5),
          Offset(t.dx + 5.0, t.dy - 4.5),
          Offset(t.dx, t.dy - 9.0),
        ]),
        Offset.zero,
      );
      pineTop.addPath(
        _poly([
          Offset(t.dx - 3.5, t.dy - 8.0),
          Offset(t.dx + 3.5, t.dy - 8.0),
          Offset(t.dx, t.dy - 13.0),
        ]),
        Offset.zero,
      );
    } else {
      // 느티나무 / 활엽수 (Zelkova - 네이버 지도 대표 세이지 그린 돔)
      zelkovaBase.addOval(
        Rect.fromCircle(center: Offset(t.dx, t.dy - 6.5), radius: 5.8),
      );
      zelkovaHighlight.addOval(
        Rect.fromCircle(center: Offset(t.dx - 1.5, t.dy - 8.2), radius: 3.4),
      );
    }
  }

  Path merged(List<List<Offset>> rings) {
    final p = Path();
    for (final r in rings) {
      if (r.length < 3) continue;
      p.addPath(_poly(projPts(r)), Offset.zero);
    }
    return p;
  }

  // 포장면은 바깥 윤곽과 구멍을 한 Path에 담고 evenOdd로 칠한다 —
  // 그래야 길 사이 건물 블록이 뚫린 채로 남는다.
  final pavement = Path()..fillType = PathFillType.evenOdd;
  for (final r in [
    ...terrain.traced.pavementOutlines,
    ...terrain.traced.pavementHoles,
  ]) {
    if (r.length < 3) continue;
    pavement.addPath(_poly(projPts(r)), Offset.zero);
  }

  return IsoTerrain(
    campusOutline: merged(terrain.traced.campusOutline),
    pavement: pavement,
    majorRoads: merged(terrain.traced.majorRoads),
    fieldLines: merged(terrain.traced.fieldLines),
    parkingStalls: _stallPath(terrain.traced, p),
    crosswalkBars: _crosswalkPath(terrain.traced, p),
    pois: [
      for (final poi in terrain.traced.pois)
        MapEntry(poi.kind, p.project(poi.at.dx, poi.at.dy)),
    ],
    greens: merged([
      for (var i = 0; i < terrain.traced.greens.length; i++)
        if (i >= terrain.traced.greensOutside.length ||
            !terrain.traced.greensOutside[i])
          terrain.traced.greens[i],
    ]),
    greensWood: merged([
      for (var i = 0; i < terrain.traced.greens.length; i++)
        if (i < terrain.traced.greensOutside.length &&
            terrain.traced.greensOutside[i])
          terrain.traced.greens[i],
    ]),
    sportsFacilities: merged(terrain.traced.sportsFacilities),
    parking: merged(terrain.traced.parking),
    waterAreas: merged(terrain.traced.waterAreas),
    campusBoundary: _poly(projPts(terrain.campusBoundary)),
    athleticTrack: _poly(projPts(terrain.athleticTrack)),
    athleticPitch: _poly(projPts(terrain.athleticPitch)),
    grandstand: _poly(projPts(terrain.grandstand)),
    pond: _poly(projPts(terrain.pond)),
    pondBridge: _poly(projPts(terrain.pondBridge)),
    centralPlaza: _poly(projPts(terrain.centralPlaza)),
    dormCourtyard: _poly(projPts(terrain.dormCourtyard)),
    basketballCourt: _poly(projPts(terrain.basketballCourt)),
    tennisCourt: _poly(projPts(terrain.tennisCourt)),
    forestAreasCombined: forestCombined,
    contoursCombined: contoursCombined,
    parkingLotsCombined: parkingCombined,
    crosswalkStripesCombined: crosswalkCombined,
    roundaboutIslandsCombined: roundaboutCombined,
    treeShadowsPath: treeShadows,
    treeTrunksPath: treeTrunks,
    treeZelkovaBasePath: zelkovaBase,
    treeZelkovaHighlightPath: zelkovaHighlight,
    treeGinkgoBasePath: ginkgoBase,
    treeGinkgoHighlightPath: ginkgoHighlight,
    treeCherryBasePath: cherryBase,
    treeCherryHighlightPath: cherryHighlight,
    treePineBasePath: pineBase,
    treePineTopPath: pineTop,
  );
}

IsoBuilding buildIso(
  BaseBuilding b,
  IsoProjection p, {
  bool highlighted = false,
  bool isOneRoom = false,
  Color? zoneColor,
  String? displayName,
}) {
  final h = p.heightOf(b);
  final ring = b.ring;

  final topPts = ring.map((v) => p.project(v.dx, v.dy, h)).toList();
  final bottomPts = ring.map((v) => p.project(v.dx, v.dy)).toList();

  final cosR = math.cos(p.rotation);
  final sinR = math.sin(p.rotation);

  final walls = <_Wall>[];
  for (var i = 0; i < ring.length; i++) {
    final j = (i + 1) % ring.length;
    final a = ring[i], c = ring[j];

    final midX = (a.dx + c.dx) / 2;
    final midY = (a.dy + c.dy) / 2;
    final rMidX = midX * cosR - midY * sinR;
    final rMidY = midX * sinR + midY * cosR;
    final d = rMidX + rMidY;

    final dx = c.dx - a.dx;
    final dy = c.dy - a.dy;
    final rdx = (dx * cosR - dy * sinR).abs();
    final rdy = (dx * sinR + dy * cosR).abs();

    walls.add(
      _Wall(
        _poly([topPts[i], topPts[j], bottomPts[j], bottomPts[i]]),
        d,
        rdx < rdy,
      ),
    );
  }
  walls.sort((x, y) => x.depth.compareTo(y.depth));

  final silhouette = Path()..addPath(_poly(topPts), Offset.zero);
  for (final w in walls) {
    silhouette.addPath(w.path, Offset.zero);
  }

  final c = b.center;
  final topCenter = p.project(c.dx, c.dy, h);

  // 네이버 지도 스타일 핀/라벨 (White Pill + Dark Font)
  TextPainter? cachedBadge;
  // 교내는 대장의 공식 명칭을, 교외는 호출부가 정해 준 이름([displayName])을
  // 쓴다. 예전엔 조건에 `b.isCampus`가 걸려 있어서 **교외 건물은 이름이
  // 있어도 이름표가 아예 안 만들어졌다** — 자취방 탭이 학생 제보로 모은
  // 이름이 정작 지도에서만 사라지고 있었다.
  final labelText = displayName ?? (b.isCampus ? b.officialName : null);
  if (highlighted || (labelText != null && labelText.isNotEmpty)) {
    cachedBadge = TextPainter(
      text: TextSpan(
        text: labelText ?? '',
        style: TextStyle(
          color: highlighted ? Colors.white : const Color(0xFF222831),
          fontSize: highlighted ? 10.5 : 9.0,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          // Canvas 텍스트는 테마를 안 타서 지정 안 하면 여기만 기본 글씨체가 된다.
          fontFamily: KnueTokens.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  return IsoBuilding(
    building: b,
    top: _poly(topPts),
    walls: walls,
    silhouette: silhouette,
    topCenter: topCenter,
    highlighted: highlighted,
    isOneRoom: isOneRoom,
    zoneColor: zoneColor,
    displayName: labelText,
    cachedBadgePainter: cachedBadge,
  );
}

List<IsoBuilding> layoutBuildings(
  Iterable<BaseBuilding> buildings,
  IsoProjection p, {
  String? selectedId,
  Set<String> oneRoomIds = const {},
  Map<String, Color> zoneColors = const {},
  Map<String, String> displayNames = const {},
}) {
  final sorted = buildings.toList()
    ..sort((a, b) => p.depthKey(a).compareTo(p.depthKey(b)));
  return sorted
      .map(
        (b) => buildIso(
          b,
          p,
          highlighted: b.id == selectedId,
          isOneRoom: oneRoomIds.contains(b.id),
          zoneColor: zoneColors[b.id],
          displayName: displayNames[b.id],
        ),
      )
      .toList();
}

BaseBuilding? hitTestBuilding(List<IsoBuilding> list, Offset point) {
  for (var i = list.length - 1; i >= 0; i--) {
    if (list[i].silhouette.contains(point)) return list[i].building;
  }
  return null;
}

class CombinedRoads {
  final Path carRoads;
  final Path walkways;
  const CombinedRoads({required this.carRoads, required this.walkways});
  static final empty = CombinedRoads(carRoads: Path(), walkways: Path());
}

CombinedRoads projectRoads(List<BaseRoad> roads, IsoProjection p) {
  final car = Path();
  final walk = Path();
  for (final r in roads) {
    if (r.points.isEmpty) continue;
    final pts = r.points.map((v) => p.project(v.dx, v.dy)).toList();
    final pth = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) {
      pth.lineTo(pt.dx, pt.dy);
    }
    if (r.type == 'walkway') {
      walk.addPath(pth, Offset.zero);
    } else {
      car.addPath(pth, Offset.zero);
    }
  }
  return CombinedRoads(carRoads: car, walkways: walk);
}

/// 굵기별로 묶은 OSM 도로. 같은 굵기끼리 Path 하나로 합쳐 그린다 —
/// 160줄을 따로 그리면 드로우콜이 그만큼 늘어난다.
class IsoOsmRoads {
  /// (종류, 화면 굵기) → 합쳐진 Path. 굵은 길이 뒤에 오도록 정렬돼 있다.
  final List<({String kind, double width, Path path})> lanes;
  const IsoOsmRoads(this.lanes);
  static const empty = IsoOsmRoads([]);
}

IsoOsmRoads projectOsmRoads(List<OsmRoad> roads, IsoProjection p) {
  // 굵기는 실제 폭(m) × 배율이다. 화면 고정 굵기로 그으면 확대했을 때
  // 길만 가늘어져 건물 사이로 실처럼 보인다.
  //
  // 아이소메트릭에서 x축은 그대로, y축은 절반으로 눌린다. 길이 어느 방향을
  // 향하든 굵기가 들쭉날쭉하면 안 되므로 **한 줄에 하나의 굵기**를 쓰고,
  // 눌림의 평균(0.75)을 곱해 대략 맞춘다.
  const squash = 0.75;
  final byKey = <String, ({String kind, double width, Path path})>{};
  for (final r in roads) {
    if (r.points.length < 2) continue;
    final w = (r.widthM * p.scale * squash).clamp(0.8, 60.0);
    // 0.5px 단위로 묶어 Path 수를 줄인다.
    final q = (w * 2).round() / 2;
    final key = '${r.kind}|$q';
    final lane = byKey.putIfAbsent(
      key,
      () => (kind: r.kind, width: q, path: Path()),
    );
    final pts = r.points.map((v) => p.project(v.dx, v.dy)).toList();
    lane.path.moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) {
      lane.path.lineTo(pt.dx, pt.dy);
    }
  }
  final lanes = byKey.values.toList()
    // 굵은 길을 나중에(위에) 그린다 — 좁은 샛길이 큰 길을 덮으면 안 된다.
    ..sort((a, b) => a.width.compareTo(b.width));
  return IsoOsmRoads(lanes);
}

/// 화면 좌표로 옮긴 용도별 바닥면. 용도마다 Path 하나로 합쳐 그린다 —
/// 1,500필지를 따로 그리면 드로우콜이 그만큼 늘어난다.
class IsoLandUse {
  final Map<LandUse, Path> byUse;
  const IsoLandUse(this.byUse);
  static const empty = IsoLandUse({});
}

IsoLandUse projectLandUse(List<BaseLandUse> land, IsoProjection p) {
  final byUse = <LandUse, Path>{};
  for (final l in land) {
    if (l.ring.length < 3) continue;
    final pts = l.ring.map((v) => p.project(v.dx, v.dy)).toList();
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    (byUse[l.use] ??= Path()).addPath(path, Offset.zero);
  }
  return IsoLandUse(byUse);
}

/// 지도 배경(용도가 지정되지 않은 바닥).
///
/// 바닥색은 이 배경과 얼마나 떨어져 있느냐로 읽힌다. 처음엔 라이트를 거의
/// 흰색(#F7F4EE, 휘도 0.906)으로 두는 바람에 농지가 배경과 휘도 0.024밖에
/// 차이 나지 않아 전부 하얗게 뭉갰고, 다크는 거꾸로 임야가 0.0008 차이로
/// 새까맣게 묻혔다. 양쪽 다 가운데로 당겨 잡았다.
Color mapBackgroundColor(bool isDark) =>
    isDark ? const Color(0xFF23262B) : const Color(0xFFF4F1E9);

/// 용도별 바닥색.
///
/// 채도를 낮춰 튀지 않게 하되, **배경과의 휘도 차이**는 확실히 벌린다 —
/// 라이트는 0.09 이상, 다크는 0.02 이상. 그 위에 건물이 올라가므로
/// 바닥이 너무 진하면 건물이 묻힌다.
Color landUseColor(LandUse use, bool isDark) {
  if (isDark) {
    return switch (use) {
      LandUse.campus => const Color(0xFF31462F),
      LandUse.road => const Color(0xFF3A3B42),
      LandUse.water => const Color(0xFF1F4A61),
      LandUse.farm => const Color(0xFF363D2B),
      LandUse.forest => const Color(0xFF2C4430),
      LandUse.park => const Color(0xFF2E4733),
    };
  }
  return switch (use) {
    // 학교용지 — 지도에서 가장 먼저 눈에 들어와야 하므로 가장 또렷하게.
    LandUse.campus => const Color(0xFFCFE3B8),
    LandUse.road => const Color(0xFFE6E1D4),
    LandUse.water => const Color(0xFFAFD3E8),
    LandUse.farm => const Color(0xFFE2E9CC),
    LandUse.forest => const Color(0xFFBBD6A8),
    LandUse.park => const Color(0xFFC8E0BE),
  };
}

Rect boundsOf(List<IsoBuilding> list, CombinedRoads roads) {
  Rect? rect;
  void add(Rect r) => rect = rect == null ? r : rect!.expandToInclude(r);
  for (final b in list) {
    add(b.silhouette.getBounds());
  }
  add(roads.carRoads.getBounds());
  add(roads.walkways.getBounds());
  return rect ?? Rect.zero;
}

/// 네이버 지도(Naver Map) 감성의 정갈하고 맑은 3D 입체 지도 렌더러
class HousingMapPainter extends CustomPainter {
  final List<IsoBuilding> buildings;
  final CombinedRoads roads;
  final IsoTerrain terrain;
  final bool isDark;
  final Offset origin;

  /// 지적 기반 용도별 바닥면. 가장 아래에 깔린다.
  final IsoLandUse landuse;

  /// OSM 도로 중심선(ODbL). 화면에 출처 표기가 있어야 한다.
  final IsoOsmRoads osmRoads;

  /// 교내 건물에 번호를 찍을지. 색을 눈으로 검수할 때 켠다.
  final bool showBuildingNumbers;

  /// 번호 TextPainter 재사용 캐시 — 프레임마다 layout()을 다시 돌리면
  /// 건물 100개분이 통째로 낭비된다.
  static final Map<int, TextPainter> _numberPainters = {};
  static final Map<String, TextPainter> _poiPainters = {};

  /// 지금 확대 배율. 이름표를 화면에서 늘 같은 크기로 그리려고 쓴다
  /// ([_paintLandmarkBadges] 참고). 확대·축소할 때마다 다시 그려야 하므로
  /// [view]를 [repaint]로 넘겨 컨트롤러가 바뀔 때만 갱신되게 한다.
  final TransformationController? view;

  double get viewScale =>
      (view?.value.getMaxScaleOnAxis() ?? 1.0).clamp(0.1, 8.0);

  HousingMapPainter({
    required this.buildings,
    required this.roads,
    required this.terrain,
    required this.isDark,
    required this.origin,
    this.landuse = IsoLandUse.empty,
    this.osmRoads = IsoOsmRoads.empty,
    this.showBuildingNumbers = false,
    this.view,
  }) : super(repaint: view);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);

    // 바닥(지적) → 손으로 만든 지형 → 도로 → 건물 순.
    // 실측 바닥면이 가장 아래에 깔려야 나머지가 그 위에 얹힌 것처럼 보인다.
    _paintLandUse(canvas);
    _paintCampusBoundary(canvas);
    _paintTerrain(canvas);
    // 중심선을 먼저 — 지적 필지가 끊긴 구간(사유지 통과 등)을 메워 길이 이어져
    // 보이게 한다. 그 위에 실제 필지 노면을 덮으면 폭이 정확해진다.
    _paintRoads(canvas);
    _paintRoadSurfaces(canvas);
    // 캡처에서 뽑은 교내 지형은 지적 노면 위에 얹는다 — 부지 안에서는
    // 이쪽이 실제 모양이라 아래 것을 덮어야 한다.
    _paintTracedCampus(canvas);
    _paintCrosswalksAndIslands(canvas);
    for (final b in buildings) {
      _paintBuilding(canvas, b);
    }
    _paintTrees(canvas);
    _paintPois(canvas);
    _paintBuildingNumbers(canvas);
    _paintLandmarkBadges(canvas);

    canvas.restore();
  }

  /// 지적 기반 바닥면. 그리는 순서가 곧 위아래라서, 넓게 깔리는 것부터
  /// 좁고 또렷한 것 순으로 얹는다.
  ///
  /// 도로는 여기서 빠진다 — 노면으로 따로 그려야 골목까지 길로 읽힌다
  /// ([_paintRoadSurfaces]).
  void _paintLandUse(Canvas canvas) {
    const order = [
      LandUse.farm,
      LandUse.forest,
      LandUse.park,
      LandUse.campus,
      LandUse.water,
    ];
    for (final use in order) {
      final path = landuse.byUse[use];
      if (path == null) continue;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = landUseColor(use, isDark),
      );
    }

    // 학교용지에만 얇은 테두리를 둘러 "여기가 교원대 부지"임을 드러낸다.
    // 다른 용도까지 테두리를 치면 지적도처럼 보여 오히려 지저분하다.
    final campus = landuse.byUse[LandUse.campus];
    if (campus != null) {
      canvas.drawPath(
        campus,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = isDark
              ? const Color(0xFF4E7A4C).withValues(alpha: 0.7)
              : const Color(0xFF88AF72).withValues(alpha: 0.8),
      );
    }
  }

  /// 네이버지도 캡처에서 그대로 뽑은 교내 지형.
  ///
  /// 순서가 곧 위아래다: 부지 바탕 → 포장면 → 주차장 → 운동시설 → 잔디 →
  /// 수면 → 테두리. 잔디를 시설보다 위에 얹는 이유는 트랙 안쪽 축구장처럼
  /// 시설 **안에** 들어앉은 초록이 있기 때문이다.
  ///
  /// 바닥 네 종류(녹지·포장·주차·운동시설)는 **명도를 벌려** 칠한다. 비슷한
  /// 밝기로 두면 아이소메트릭에서 건물 그림자에 묻혀 구역이 안 읽힌다.
  void _paintTracedCampus(Canvas canvas) {
    final outline = terrain.campusOutline;
    if (outline.getBounds().isEmpty) return;

    // 학교용지는 **연파랑**으로 칠한다. 네이버가 쓰는 색이기도 하고
    // (212,224,240), 실용적인 이유가 더 크다 — 부지 밖 숲도 연녹색이라
    // 부지까지 초록으로 칠하면 둘이 붙어 보여 경계가 안 읽힌다.
    canvas.drawPath(
      outline,
      Paint()
        ..color = isDark ? const Color(0xFF202A36) : const Color(0xFFDCE6F1),
    );
    canvas.drawPath(
      terrain.pavement,
      Paint()
        ..color = isDark ? const Color(0xFF3E444C) : const Color(0xFFFFFDF8),
    );
    // 국도는 네이버처럼 노랗게 — 간선이 한눈에 잡혀야 길눈이 선다.
    canvas.drawPath(
      terrain.majorRoads,
      Paint()
        ..color = isDark ? const Color(0xFF6B5B28) : const Color(0xFFFAE9A8),
    );
    // 포장면 가장자리 — 길과 부지 바탕이 맞닿는 선을 또렷하게.
    canvas.drawPath(
      terrain.pavement,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFC9C2B0),
    );

    // 주차장 — 포장면보다 한 톤 어둡게 깔고, 주차 구획을 흉내 낸 빗금을 얹는다.
    canvas.drawPath(
      terrain.parking,
      Paint()
        ..color = isDark ? const Color(0xFF4E4736) : const Color(0xFFEDE0C0),
    );
    canvas.drawPath(
      terrain.parkingStalls,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.13)
            : const Color(0xFF9C8A5E).withValues(alpha: 0.38),
    );
    canvas.drawPath(
      terrain.parking,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = isDark
            ? const Color(0xFF8A7C58).withValues(alpha: 0.8)
            : const Color(0xFFBFAC7C),
    );

    canvas.drawPath(
      terrain.sportsFacilities,
      Paint()
        ..color = isDark ? const Color(0xFF4A5059) : const Color(0xFFDCDACF),
    );
    // 부지 밖 숲은 흐리게 — 운동장 잔디와 같은 초록이면 지도가 요란해진다.
    canvas.drawPath(
      terrain.greensWood,
      Paint()
        ..color = isDark ? const Color(0xFF25401F) : const Color(0xFFCFE3B4),
    );
    canvas.drawPath(
      terrain.greens,
      Paint()
        ..color = isDark ? const Color(0xFF2E7034) : const Color(0xFF9ED47E),
    );
    // 축구장 선·트랙 레인 — 운동장이 그냥 초록 판이 아니게 해준다.
    canvas.drawPath(
      terrain.fieldLines,
      Paint()
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.75),
    );
    canvas.drawPath(
      terrain.waterAreas,
      Paint()
        ..color = isDark ? const Color(0xFF1F4A61) : const Color(0xFFAFD3E8),
    );
    canvas.drawPath(
      terrain.crosswalkBars,
      Paint()
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.30)
            : Colors.white.withValues(alpha: 0.95),
    );

    // 부지 테두리 — "여기까지가 교원대"를 한눈에 보이게 하는 선.
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = isDark
            ? const Color(0xFF7CAE6B).withValues(alpha: 0.9)
            : const Color(0xFF5F8A44).withValues(alpha: 0.85),
    );
  }

  void _paintCampusBoundary(Canvas canvas) {
    if (terrain.campusBoundary.getBounds().isEmpty) return;

    // 네이버 지도 특유의 맑고 정갈한 캠퍼스 녹지/학교부지 틴트 (Soft Mint-Sage Tint)
    final campusFill = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark
          ? const Color(0xFF1B2E24).withValues(alpha: 0.60)
          : const Color(0xFFE5F4DC).withValues(alpha: 0.85);
    canvas.drawPath(terrain.campusBoundary, campusFill);

    // 부지 경계 테두리
    final boundaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = isDark
          ? const Color(0xFF2E7D32).withValues(alpha: 0.65)
          : const Color(0xFF90C286).withValues(alpha: 0.70);
    canvas.drawPath(terrain.campusBoundary, boundaryPaint);
  }

  void _paintTerrain(Canvas canvas) {
    // 1. 등고선 (네이버 지도의 미세한 지형 음영선)
    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.06)
          : const Color(0xFFB5A99B).withValues(alpha: 0.25);
    canvas.drawPath(terrain.contoursCombined, contourPaint);

    // 2. 청람동산 구릉지 녹지/숲 (네이버 지도 포레스트 그린)
    final forestPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark
          ? const Color(0xFF162B1D).withValues(alpha: 0.80)
          : const Color(0xFFD3EBCA).withValues(alpha: 0.90);
    canvas.drawPath(terrain.forestAreasCombined, forestPaint);

    // 3. 주차장 (네이버 지도 주차구역)
    final parkingPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark ? const Color(0xFF282C34) : const Color(0xFFEBE8E1);
    final parkingBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = isDark ? Colors.white12 : const Color(0xFFD6D0C5);
    canvas.drawPath(terrain.parkingLotsCombined, parkingPaint);
    canvas.drawPath(terrain.parkingLotsCombined, parkingBorder);

    // 4. 중앙 잔디광장 (네이버 지도 잔디밭 녹지)
    if (!terrain.centralPlaza.getBounds().isEmpty) {
      final plazaPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark
            ? const Color(0xFF23442A).withValues(alpha: 0.85)
            : const Color(0xFFCEECC2).withValues(alpha: 0.95);
      final plazaBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = isDark
            ? const Color(0xFF388E3C).withValues(alpha: 0.3)
            : const Color(0xFFA5D698);
      canvas.drawPath(terrain.centralPlaza, plazaPaint);
      canvas.drawPath(terrain.centralPlaza, plazaBorder);
    }

    // 4-1. 기숙사 중앙 잔디마당
    if (!terrain.dormCourtyard.getBounds().isEmpty) {
      final dormPlazaPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark
            ? const Color(0xFF1E3A24).withValues(alpha: 0.80)
            : const Color(0xFFD8F0CD).withValues(alpha: 0.90);
      canvas.drawPath(terrain.dormCourtyard, dormPlazaPaint);
    }

    // 5. 대운동장 (네이버 지도 체육시설: 브라운 테라코타 트랙 & 산뜻한 잔디)
    if (!terrain.athleticTrack.getBounds().isEmpty) {
      final trackPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF6D3025) : const Color(0xFFDE836D);
      canvas.drawPath(terrain.athleticTrack, trackPaint);

      final pitchPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF1F4826) : const Color(0xFFBCE0A4);
      canvas.drawPath(terrain.athleticPitch, pitchPaint);

      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.65);
      canvas.drawPath(terrain.athleticTrack, linePaint);
      canvas.drawPath(terrain.athleticPitch, linePaint);

      if (!terrain.grandstand.getBounds().isEmpty) {
        final standPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = isDark ? const Color(0xFF3A4750) : const Color(0xFFBAC5CC);
        canvas.drawPath(terrain.grandstand, standPaint);
      }
    }

    // 6. 야외 체육코트 (네이버 지도 코트 블루 & 오렌지)
    if (!terrain.basketballCourt.getBounds().isEmpty) {
      final bballPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF1B4E85) : const Color(0xFF6BA4E8);
      final bballBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.6);
      canvas.drawPath(terrain.basketballCourt, bballPaint);
      canvas.drawPath(terrain.basketballCourt, bballBorder);
    }

    if (!terrain.tennisCourt.getBounds().isEmpty) {
      final courtPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF9E4822) : const Color(0xFFE59C75);
      final courtBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.5);
      canvas.drawPath(terrain.tennisCourt, courtPaint);
      canvas.drawPath(terrain.tennisCourt, courtBorder);
    }

    // 7. 청람지 (네이버 지도 대표 아쿠아 블루 수계)
    if (!terrain.pond.getBounds().isEmpty) {
      final pondPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF0F4C75) : const Color(0xFFCCE4F7);
      final pondBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = isDark ? const Color(0xFF3282B8) : const Color(0xFFA5CFEE);

      canvas.drawPath(terrain.pond, pondPaint);
      canvas.drawPath(terrain.pond, pondBorder);

      // 목교 아치 다리
      if (!terrain.pondBridge.getBounds().isEmpty) {
        final bridgePaint = Paint()
          ..style = PaintingStyle.fill
          ..color = isDark ? const Color(0xFF5D4037) : const Color(0xFFBCAAA4);
        final bridgeRailing = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = isDark ? const Color(0xFF8D6E63) : const Color(0xFF8D6E63);
        canvas.drawPath(terrain.pondBridge, bridgePaint);
        canvas.drawPath(terrain.pondBridge, bridgeRailing);
      }
    }
  }

  /// 지적 '도' 필지를 실제 노면으로 그린다.
  ///
  /// 도로중심선(LT_L_MOCTLINK)에는 큰길 64개(7.4km)밖에 없어서 교내 도로와
  /// 원룸촌 골목이 통째로 빠져 있었다. 반면 지적 도로 필지는 411개 —
  /// 캠퍼스 안 50개, 원룸촌 53개가 들어 있고, **필지 폭이 곧 실제 도로 폭**이라
  /// 큰길·골목 위계가 저절로 생긴다. 도시계획도로(대로/중로/소로) 레이어는
  /// 이 지역에 6건뿐이라 등급 정보로는 쓸 수 없었다.
  void _paintRoadSurfaces(Canvas canvas) {
    final path = landuse.byUse[LandUse.road];
    if (path == null) return;

    // 케이싱을 먼저 두껍게 깔고 그 위에 노면을 얹으면 길 가장자리가 생긴다.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = isDark ? const Color(0xFF14161A) : const Color(0xFFD8D2C6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = landUseColor(LandUse.road, isDark),
    );
  }

  void _paintRoads(Canvas canvas) {
    // 네이버 지도 도로 렌더링 (화이트 노면 + 정갈한 웜그레이 엣지 케이싱)
    // 1. 차도 케이싱 (외곽선)
    final carEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 7.5
      ..color = isDark ? const Color(0xFF282B30) : const Color(0xFFE2DDD5);

    // 2. 차도 노면 (네이버 지도의 밝은 화이트 아스팔트)
    final carSurface = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 5.6
      ..color = isDark ? const Color(0xFF363A42) : const Color(0xFFFFFFFF);

    canvas.drawPath(roads.carRoads, carEdge);
    canvas.drawPath(roads.carRoads, carSurface);

    // 3. 보행로 / 인도 (네이버 지도 인도 블록 톤)
    final walkwayEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 6.5
      ..color = isDark ? const Color(0xFF2D3035) : const Color(0xFFEBE6DC);
    final walkwaySurface = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.8
      ..color = isDark ? const Color(0xFF40454E) : const Color(0xFFFAF7F2);

    canvas.drawPath(roads.walkways, walkwayEdge);
    canvas.drawPath(roads.walkways, walkwaySurface);

    _paintOsmRoads(canvas);
  }

  /// OSM 중심선을 굵기로 그어 도로를 만든다.
  ///
  /// 케이싱(테두리)을 먼저 굵게, 노면을 그 위에 얇게 — 두 번 그으면 길이
  /// 이어지는 곳마다 테두리가 자연스레 이어지고 교차점이 깔끔해진다.
  /// 모든 케이싱을 먼저 다 긋고 노면을 나중에 긋는 이유도 같다. 한 줄씩
  /// 케이싱·노면을 번갈아 그으면 뒤에 그린 케이싱이 앞선 노면을 가로지른다.
  void _paintOsmRoads(Canvas canvas) {
    if (osmRoads.lanes.isEmpty) return;

    Color surfaceOf(String kind) => switch (kind) {
      'major' => isDark ? const Color(0xFF4A423A) : const Color(0xFFFDF6E3),
      'walk' ||
      'path' ||
      'steps' => isDark ? const Color(0xFF40454E) : const Color(0xFFFAF7F2),
      _ => isDark ? const Color(0xFF363A42) : const Color(0xFFFFFFFF),
    };
    final casing = isDark ? const Color(0xFF282B30) : const Color(0xFFE2DDD5);

    Paint stroke(double w, Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w
      ..color = c;

    for (final l in osmRoads.lanes) {
      canvas.drawPath(l.path, stroke(l.width + 1.6, casing));
    }
    for (final l in osmRoads.lanes) {
      canvas.drawPath(l.path, stroke(l.width, surfaceOf(l.kind)));
    }
  }

  void _paintCrosswalksAndIslands(Canvas canvas) {
    final cwPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.butt
      ..color = isDark ? Colors.white38 : const Color(0xFFC7C0B3);
    canvas.drawPath(terrain.crosswalkStripesCombined, cwPaint);

    final islandPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark ? const Color(0xFF23442A) : const Color(0xFFCEECC2);
    final islandBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = isDark ? Colors.white24 : const Color(0xFFA5D698);

    canvas.drawPath(terrain.roundaboutIslandsCombined, islandPaint);
    canvas.drawPath(terrain.roundaboutIslandsCombined, islandBorder);
  }

  void _paintBuilding(Canvas canvas, IsoBuilding b) {
    Color base;
    if (b.highlighted) {
      // 선택 하이라이트: 네이버 그린 포인트
      base = const Color(0xFF03C75A);
    } else if (b.building.isCampus) {
      base = campusUseColor(b.building.use, isDark);
    } else if (b.zoneColor != null) {
      base = b.zoneColor!;
    } else if (b.isOneRoom) {
      base = isDark ? const Color(0xFF275038) : const Color(0xFFDCFCE7);
    } else {
      // 일반 민간 주택 / 상가 건물 (네이버 지도 특유의 깔끔한 화이트-웜그레이)
      base = isDark ? const Color(0xFF2C323B) : const Color(0xFFFFFFFF);
    }

    final topPaint = Paint()..color = base;
    final leftPaint = Paint()..color = _shade(base, 0.08);
    final rightPaint = Paint()..color = _shade(base, 0.16);

    for (final w in b.walls) {
      canvas.drawPath(w.path, w.facingLeft ? leftPaint : rightPaint);
    }
    canvas.drawPath(b.top, topPaint);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = b.highlighted ? 2.0 : 0.6
      ..color = b.highlighted
          ? Colors.white
          : (isDark
                ? Colors.white.withValues(alpha: 0.18)
                : const Color(0xFFD1CBC0));
    canvas.drawPath(b.top, edge);
    if (b.highlighted) {
      canvas.drawPath(b.silhouette, edge);
    }
  }

  void _paintTrees(Canvas canvas) {
    // 1. 네이버 지도 감성의 부드러운 드롭 섀도우
    canvas.drawPath(
      terrain.treeShadowsPath,
      Paint()..color = Colors.black.withValues(alpha: isDark ? 0.25 : 0.09),
    );

    // 2. 나무 원목 줄기
    canvas.drawPath(
      terrain.treeTrunksPath,
      Paint()
        ..color = isDark ? const Color(0xFF4A3B32) : const Color(0xFF9E8E81),
    );

    // 3. 느티나무 / 활엽수 (네이버 지도 세이지 에메랄드)
    canvas.drawPath(
      terrain.treeZelkovaBasePath,
      Paint()
        ..color = isDark ? const Color(0xFF1E4620) : const Color(0xFF66BB6A),
    );
    canvas.drawPath(
      terrain.treeZelkovaHighlightPath,
      Paint()
        ..color = isDark ? const Color(0xFF2E7D32) : const Color(0xFFA5D6A7),
    );

    // 4. 소나무 / 침엽수 (네이버 지도 딥 틸-포레스트)
    canvas.drawPath(
      terrain.treePineBasePath,
      Paint()
        ..color = isDark ? const Color(0xFF13381B) : const Color(0xFF388E3C),
    );
    canvas.drawPath(
      terrain.treePineTopPath,
      Paint()
        ..color = isDark ? const Color(0xFF1E5227) : const Color(0xFF4CAF50),
    );

    // 5. 은행나무 (네이버 지도 웜 골든 앰버)
    canvas.drawPath(
      terrain.treeGinkgoBasePath,
      Paint()
        ..color = isDark ? const Color(0xFFB45309) : const Color(0xFFFBBF24),
    );
    canvas.drawPath(
      terrain.treeGinkgoHighlightPath,
      Paint()
        ..color = isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A),
    );

    // 6. 벚나무 / 단풍 (네이버 지도 파스텔 핑크)
    canvas.drawPath(
      terrain.treeCherryBasePath,
      Paint()
        ..color = isDark ? const Color(0xFF9D174D) : const Color(0xFFF472B6),
    );
    canvas.drawPath(
      terrain.treeCherryHighlightPath,
      Paint()
        ..color = isDark ? const Color(0xFFBE185D) : const Color(0xFFFBCFE8),
    );
  }

  /// 지도 마커 — 버스정류장.
  ///
  /// 캡처의 마커 색에서 위치만 뽑았고(크기는 화면 고정이라 뜻이 없다),
  /// 배지는 여기서 그린다.
  ///
  /// 편의점(C)·주차장(P) 배지는 뺐다. 원룸촌 골목마다 촘촘히 박혀 건물
  /// 이름표를 덮었고, 자취방을 고를 때 먼저 보는 정보가 아니다. 위치
  /// 데이터는 그대로 두었으니 다시 켜려면 여기에 항목만 되살리면 된다.
  void _paintPois(Canvas canvas) {
    if (terrain.pois.isEmpty) return;
    const style = {
      'bus': [Color(0xFF2E86DE), 'B'],
    };
    for (final e in terrain.pois) {
      final st = style[e.key];
      if (st == null) continue;
      final c = e.value;
      canvas.drawCircle(
        c.translate(0, 1),
        5.4,
        Paint()..color = Colors.black.withValues(alpha: 0.18),
      );
      canvas.drawCircle(c, 5.2, Paint()..color = st[0] as Color);
      canvas.drawCircle(
        c,
        5.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Colors.white.withValues(alpha: 0.9),
      );
      final tp = _poiPainters.putIfAbsent(
        e.key,
        () => TextPainter(
          text: TextSpan(
            text: st[1] as String,
            style: TextStyle(
              color: Colors.white,
              fontSize: 6.5,
              fontWeight: FontWeight.w900,
              height: 1.0,
              fontFamily: KnueTokens.fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
    }
  }

  /// 교내 건물 번호. 색이 이상한 동을 사람이 "몇 번"이라고 짚으라고 찍는다.
  /// 지붕 한가운데, 흰 원판 위 짙은 숫자 — 지도 위 어떤 지붕색에도 읽힌다.
  void _paintBuildingNumbers(Canvas canvas) {
    if (!showBuildingNumbers) return;
    final disc = Paint()
      ..color = isDark
          ? const Color(0xFF11151A).withValues(alpha: 0.86)
          : Colors.white.withValues(alpha: 0.92);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = isDark ? Colors.white24 : const Color(0xFF9AA3AD);
    for (final b in buildings) {
      final no = b.building.mapNo;
      if (no == null) continue;
      // 글자색이 테마를 타므로 키에 테마를 섞는다
      final tp = _numberPainters.putIfAbsent(
        no * 2 + (isDark ? 1 : 0),
        () => TextPainter(
          text: TextSpan(
            text: '$no',
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1F2933),
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              height: 1.0,
              fontFamily: KnueTokens.fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      final c = b.topCenter;
      final r = math.max(6.5, tp.width / 2 + 3.5);
      canvas.drawCircle(c, r, disc);
      canvas.drawCircle(c, r, ringPaint);
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
    }
  }

  /// 이름표.
  ///
  /// 원룸촌은 건물이 워낙 붙어 있어서 이름표를 다 그리면 서로 겹쳐 **어느
  /// 쪽도 안 읽힌다** (기본 배율에서 재 보니 후보 97개 중 66쌍이 겹쳤다).
  /// 그래서 두 가지를 한다.
  ///
  /// 1. **화면 고정 크기** — 이름표를 확대 배율의 역수로 되돌려 그린다.
  ///    그냥 두면 확대해도 글씨가 같이 커져 겹침이 영영 안 풀린다. 이렇게
  ///    해야 길 하나를 당겨 볼 때 그 골목 이름이 차례로 드러난다.
  /// 2. **겹치면 건너뛴다** — 중요한 것부터 자리를 잡는다. 선택한 건물 >
  ///    조사해 이름이 붙은 건물 > 큰 건물 순.
  void _paintLandmarkBadges(Canvas canvas) {
    // 캔버스는 InteractiveViewer가 통째로 확대하므로, 여기서 1/배율을 곱해
    // 그리면 화면에서는 늘 같은 크기로 보인다.
    final k = 1.0 / viewScale;

    final ordered =
        buildings.where((b) {
          // 번호를 켜면 이름표는 감춘다. 둘 다 지붕 한가운데 놓여서 겹치면
          // 어느 쪽도 안 읽힌다 — 번호로 짚으려면 이름이 비켜줘야 한다.
          // (선택한 건물은 예외 — 무엇을 골랐는지는 늘 보여야 한다)
          if (showBuildingNumbers && b.building.isCampus && !b.highlighted) {
            return false;
          }
          return b.cachedBadgePainter != null;
        }).toList()..sort((x, y) {
          if (x.highlighted != y.highlighted) return x.highlighted ? -1 : 1;
          final xn = x.building.officialName != null;
          final yn = y.building.officialName != null;
          if (xn != yn) return xn ? -1 : 1;
          return y.building.footprintArea.compareTo(x.building.footprintArea);
        });

    final placed = <Rect>[];
    for (final b in ordered) {
      final tp = b.cachedBadgePainter!;
      final center = b.topCenter;
      final w = (tp.width + 12) * k;
      final h = (tp.height + 6) * k;
      final rect = Rect.fromCenter(
        center: Offset(center.dx, center.dy - 8 * k),
        width: w,
        height: h,
      );
      if (!b.highlighted && placed.any(rect.overlaps)) continue;
      placed.add(rect);

      final badgeRect = RRect.fromRectAndRadius(rect, Radius.circular(10 * k));

      // 네이버 지도 스타일 POI 마커 (White Capsule + Dark Font + Soft Drop Shadow)
      if (b.highlighted) {
        canvas.drawRRect(
          badgeRect,
          Paint()..color = const Color(0xFF03C75A), // Naver Green
        );
        canvas.drawRRect(
          badgeRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = Colors.white,
        );
      } else {
        canvas.drawRRect(
          badgeRect.shift(const Offset(0, 1.5)),
          Paint()..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
        );
        canvas.drawRRect(
          badgeRect,
          Paint()..color = isDark ? const Color(0xFF242830) : Colors.white,
        );
        canvas.drawRRect(
          badgeRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = isDark ? Colors.white12 : const Color(0xFFE2DDD5),
        );
      }

      // 글씨도 같은 비율로 되돌려 그린다. 캐시해 둔 TextPainter를 그대로
      // 쓰려고 캔버스를 잠깐 축소한다(레이아웃을 다시 하지 않는다).
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.scale(k);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  Color _shade(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool shouldRepaint(HousingMapPainter old) =>
      old.buildings != buildings ||
      old.roads != roads ||
      old.terrain != terrain ||
      old.landuse != landuse ||
      old.isDark != isDark ||
      old.origin != origin;
}

/// 교내 건물 지붕 색 — **용도별로 고정**한다.
///
/// 예전엔 이름에 '본부'·'도서관'이 들어있나 훑어서 정했다. 그러다 보니 이름이
/// 안 붙은 동은 전부 기본 회색으로 빠져, 같은 성격의 건물이 서로 다른 색으로
/// 보이는 일이 생겼다. 용도는 campus_building_index.dart에 못박혀 있다.
///
/// 명도는 좁게 잡는다. 지붕이 알록달록하면 지도가 아니라 색표가 된다 —
/// 색은 "이 건물이 무슨 쓰임인가"만 알려주면 된다.
Color campusUseColor(BuildingUse? use, bool isDark) {
  if (isDark) {
    return switch (use) {
      BuildingUse.academic => const Color(0xFF3A4A5C),
      BuildingUse.library => const Color(0xFF473F63),
      BuildingUse.student => const Color(0xFF63482F),
      BuildingUse.dorm => const Color(0xFF2B4457),
      BuildingUse.sports => const Color(0xFF2A4B4C),
      BuildingUse.culture => const Color(0xFF5A3745),
      BuildingUse.training => const Color(0xFF34503F),
      BuildingUse.admin => const Color(0xFF44454F),
      BuildingUse.affiliate => const Color(0xFF4B4A34),
      _ => const Color(0xFF3A3E45),
    };
  }
  return switch (use) {
    BuildingUse.academic => const Color(0xFFECF1F9),
    BuildingUse.library => const Color(0xFFEDE9FA),
    BuildingUse.student => const Color(0xFFFBEEE0),
    BuildingUse.dorm => const Color(0xFFE9F3FA),
    BuildingUse.sports => const Color(0xFFE4F6F2),
    BuildingUse.culture => const Color(0xFFFAEBEF),
    BuildingUse.training => const Color(0xFFEAF5EB),
    BuildingUse.admin => const Color(0xFFF1F1F4),
    BuildingUse.affiliate => const Color(0xFFF6F4E6),
    _ => const Color(0xFFF7F8F9),
  };
}

/// 주차 구획선. 구역마다 잰 빗살 방향·간격으로 선을 긋고 폴리곤 안으로 자른다.
///
/// 선분을 데이터에 수천 개 담는 대신 숫자 두 개(각도·간격)만 들고 있다가
/// 여기서 만들어 쓴다.
Path _stallPath(TracedGround g, IsoProjection p) {
  final path = Path();
  g.parkingStalls.forEach((idx, st) {
    if (idx < 0 || idx >= g.parking.length) return;
    final poly = g.parking[idx];
    if (poly.length < 3) return;
    var mnx = poly.first.dx, mxx = poly.first.dx;
    var mny = poly.first.dy, mxy = poly.first.dy;
    for (final q in poly) {
      mnx = math.min(mnx, q.dx);
      mxx = math.max(mxx, q.dx);
      mny = math.min(mny, q.dy);
      mxy = math.max(mxy, q.dy);
    }
    final cx = (mnx + mxx) / 2, cy = (mny + mxy) / 2;
    final diag = math.sqrt(math.pow(mxx - mnx, 2) + math.pow(mxy - mny, 2));
    final dx = math.cos(st.angle), dy = math.sin(st.angle);
    final nx = -dy, ny = dx; // 빗살에 수직인 축
    final pitch = st.pitch.clamp(1.5, 6.0);
    for (var t = -diag / 2; t <= diag / 2; t += pitch) {
      final ax = cx + nx * t, ay = cy + ny * t;
      // 이 선을 폴리곤 변들과 만나게 해 안쪽 구간만 남긴다
      final hits = <double>[];
      for (var i = 0; i < poly.length; i++) {
        final q = poly[i], r = poly[(i + 1) % poly.length];
        final ex = r.dx - q.dx, ey = r.dy - q.dy;
        final den = dx * ey - dy * ex;
        if (den.abs() < 1e-9) continue;
        final u = ((q.dx - ax) * ey - (q.dy - ay) * ex) / den;
        final v = ((q.dx - ax) * dy - (q.dy - ay) * dx) / den;
        if (v >= 0 && v <= 1) hits.add(u);
      }
      if (hits.length < 2) continue;
      hits.sort();
      for (var k = 0; k + 1 < hits.length; k += 2) {
        if (hits[k + 1] - hits[k] < 1.5) continue;
        final s0 = p.project(ax + dx * hits[k], ay + dy * hits[k]);
        final s1 = p.project(ax + dx * hits[k + 1], ay + dy * hits[k + 1]);
        path
          ..moveTo(s0.dx, s0.dy)
          ..lineTo(s1.dx, s1.dy);
      }
    }
  });
  return path;
}

/// 횡단보도 줄무늬. 긴 축을 따라 흰 막대를 늘어놓는다.
Path _crosswalkPath(TracedGround g, IsoProjection p) {
  final path = Path();
  for (final c in g.crosswalks) {
    final rad = c.angleDeg * math.pi / 180;
    final dx = math.cos(rad), dy = math.sin(rad);
    final nx = -dy, ny = dx;
    const barW = 0.8, gap = 1.4;
    final n = (c.length / (barW + gap)).floor();
    if (n < 2) continue;
    for (var i = 0; i < n; i++) {
      final t = -c.length / 2 + (i + 0.5) * (barW + gap);
      final bx = c.center.dx + dx * t, by = c.center.dy + dy * t;
      final quad = [
        [
          bx - dx * barW / 2 - nx * c.width / 2,
          by - dy * barW / 2 - ny * c.width / 2,
        ],
        [
          bx + dx * barW / 2 - nx * c.width / 2,
          by + dy * barW / 2 - ny * c.width / 2,
        ],
        [
          bx + dx * barW / 2 + nx * c.width / 2,
          by + dy * barW / 2 + ny * c.width / 2,
        ],
        [
          bx - dx * barW / 2 + nx * c.width / 2,
          by - dy * barW / 2 + ny * c.width / 2,
        ],
      ];
      final proj = [for (final q in quad) p.project(q[0], q[1])];
      path
        ..moveTo(proj[0].dx, proj[0].dy)
        ..lineTo(proj[1].dx, proj[1].dy)
        ..lineTo(proj[2].dx, proj[2].dy)
        ..lineTo(proj[3].dx, proj[3].dy)
        ..close();
    }
  }
  return path;
}
