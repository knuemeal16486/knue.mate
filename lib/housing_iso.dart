import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'housing_model.dart' show IsochroneCenter;
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

  BaseBuilding copyWith({
    String? id,
    int? floors,
    List<Offset>? ring,
    String? officialName,
    String? road,
    String? buildingNo,
    bool? isCampus,
    int? mapNo,
    BuildingUse? use,
  }) =>
      BaseBuilding(
        id: id ?? this.id,
        floors: floors ?? this.floors,
        ring: ring ?? this.ring,
        officialName: officialName ?? this.officialName,
        road: road ?? this.road,
        buildingNo: buildingNo ?? this.buildingNo,
        isCampus: isCampus ?? this.isCampus,
        mapNo: mapNo ?? this.mapNo,
        use: use ?? this.use,
      );

  String get addressLabel {
    if (isCampus) return kCampusAddress;
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

/// 한국교원대학교 캠퍼스 3D 지형 표고 모델 (DEM - Digital Elevation Model)
///
/// 국토교통부 VWorld 지형 표고 및 실제 교원대 캠퍼스 실측 고저차를 반영합니다.
/// 정문 및 월탄리 원룸촌(해발 약 34m, 기준 0m)에서부터
/// 미래도서관(해발 46m, +12m), 학생회관·사범대(해발 52m, +18m),
/// 기숙사 생활관(해발 62m, +28m), 청람동산 정상(해발 82m, +48m)으로
/// 이어지는 실제 언덕 구릉지 지형을 수학적으로 모델링하여
/// 등고선(Contours), 힐쉐이딩(Hillshading), 경사도 랜드마크를 사실적으로 렌더링합니다.
class CampusElevation {
  /// (x, y) 월드 좌표(m)에서의 상대 고도(정문 평지 0m 기준, 단위: m)
  static double elevationAt(double x, double y) {
    // 1. 청람동산 메인 봉우리 (North-East Ridge, 해발 82m -> +48m)
    final dChungramSq = (x - 620) * (x - 620) / (220 * 220) + (y - (-520)) * (y - (-520)) / (180 * 180);
    final chungram = 48.0 * math.exp(-dChungramSq * 1.1);

    // 2. 기숙사 언덕 능선 (함덕당·다정관·다감관 구릉지, 해발 62m -> +28m)
    final dDormSq = (x - 600) * (x - 600) / (200 * 200) + (y - (-300)) * (y - (-300)) / (150 * 150);
    final dormRidge = 28.0 * math.exp(-dDormSq * 1.2);

    // 3. 연수원/후문 구릉지 (North-West Ridge, 해발 58m -> +24m)
    final dTrainSq = (x - 200) * (x - 200) / (160 * 160) + (y - (-450)) * (y - (-450)) / (140 * 140);
    final trainingRidge = 24.0 * math.exp(-dTrainSq * 1.3);

    // 4. 중앙 학술단지 완만한 테라스 (도서관 ~ 본부 ~ 종합교육관, 해발 46m -> +12m)
    final dAcademicSq = (x - 300) * (x - 300) / (320 * 320) + (y - 50) * (y - 50) / (220 * 220);
    final academic = 13.0 * math.exp(-dAcademicSq * 0.9);

    // 5. 대운동장 평탄화 보정 (인위적 조성 평지: +5m)
    final distTrack = math.sqrt((x - 450) * (x - 450) + (y - 320) * (y - 320));
    final fieldMask = (1.0 - (distTrack / 120.0)).clamp(0.0, 1.0);

    var elev = math.max(chungram, math.max(dormRidge, math.max(trainingRidge, academic)));
    if (fieldMask > 0) {
      elev = elev * (1.0 - fieldMask * 0.7) + 5.0 * (fieldMask * 0.7);
    }

    return elev.clamp(0.0, 50.0);
  }

  /// 특정 영역의 2.5D 등고선 폴리라인 생성 (5m 간격)
  static Map<int, List<List<Offset>>> generateContourLevels({
    double minX = -120,
    double maxX = 850,
    double minY = -650,
    double maxY = 500,
    double stepM = 40.0,
  }) {
    const levels = [5, 10, 15, 20, 25, 30, 35, 40, 45];
    final contoursByLevel = <int, List<List<Offset>>>{
      for (final lvl in levels) lvl: [],
    };

    final nx = ((maxX - minX) / stepM).ceil();
    final ny = ((maxY - minY) / stepM).ceil();
    final grid = List.generate(ny + 1, (j) {
      final y = minY + j * stepM;
      return List.generate(nx + 1, (i) {
        final x = minX + i * stepM;
        return elevationAt(x, y);
      });
    });

    for (final lvl in levels) {
      final target = lvl.toDouble();
      for (var j = 0; j < ny; j++) {
        for (var i = 0; i < nx; i++) {
          final v0 = grid[j][i];
          final v1 = grid[j][i + 1];
          final v2 = grid[j + 1][i + 1];
          final v3 = grid[j + 1][i];

          final x0 = minX + i * stepM;
          final x1 = x0 + stepM;
          final y0 = minY + j * stepM;
          final y1 = y0 + stepM;

          final edges = <Offset>[];

          if ((v0 < target && v1 >= target) || (v0 >= target && v1 < target)) {
            final t = (target - v0) / (v1 - v0);
            edges.add(Offset(x0 + t * stepM, y0));
          }
          if ((v1 < target && v2 >= target) || (v1 >= target && v2 < target)) {
            final t = (target - v1) / (v2 - v1);
            edges.add(Offset(x1, y0 + t * stepM));
          }
          if ((v3 < target && v2 >= target) || (v3 >= target && v2 < target)) {
            final t = (target - v3) / (v2 - v3);
            edges.add(Offset(x0 + t * stepM, y1));
          }
          if ((v0 < target && v3 >= target) || (v0 >= target && v3 < target)) {
            final t = (target - v0) / (v3 - v0);
            edges.add(Offset(x0, y0 + t * stepM));
          }

          if (edges.length == 2) {
            contoursByLevel[lvl]!.add([edges[0], edges[1]]);
          } else if (edges.length == 4) {
            contoursByLevel[lvl]!.add([edges[0], edges[1]]);
            contoursByLevel[lvl]!.add([edges[2], edges[3]]);
          }
        }
      }
    }

    return contoursByLevel;
  }
}

/// 캠퍼스 주요 언덕길·고도 지형 마커
class CampusSlopeMarker {
  final String title;
  final String elevationText;
  final Offset position;
  final bool isSteep; // 급경사 여부
  const CampusSlopeMarker({
    required this.title,
    required this.elevationText,
    required this.position,
    this.isSteep = false,
  });
}

const List<CampusSlopeMarker> kCampusSlopeMarkers = [
  CampusSlopeMarker(
    title: '청람동산 정상',
    elevationText: '해발 82m (최고지대)',
    position: Offset(620, -520),
  ),
  CampusSlopeMarker(
    title: '기숙사 언덕길',
    elevationText: '경사 8.5% (오르막 주의)',
    position: Offset(550, -220),
    isSteep: true,
  ),
  CampusSlopeMarker(
    title: '도서관 오르막길',
    elevationText: '완만한 산책로 경사',
    position: Offset(180, 110),
  ),
  CampusSlopeMarker(
    title: '정문 진입로',
    elevationText: '평지 코스 (자전거 수월)',
    position: Offset(10, 180),
  ),
  CampusSlopeMarker(
    title: '연수원 후문 언덕고개',
    elevationText: '급경사 오르막길',
    position: Offset(170, -380),
    isSteep: true,
  ),
];

class IsoElevationLabel {
  final String text;
  final Offset screenPosition;
  const IsoElevationLabel(this.text, this.screenPosition);
}

/// 교내 건물 주소. 캠퍼스 시설은 모두 한 지번이다.
const String kCampusAddress = '태성탑연로 250';

/// 360도 회전 2.5D 아이소메트릭 투영
class IsoProjection {
  final double scale;
  final double floorHeight;
  final double rotation;

  /// true면 바로 위에서 수직으로 내려다본 평면 시점(북쪽이 위). 높이(z)는
  /// 무시해서 건물은 바닥 모양만, 언덕도 평평하게 보인다.
  final bool topDown;

  const IsoProjection({
    this.scale = 2.0,
    this.floorHeight = 3.0,
    this.rotation = 0.0,
    this.topDown = false,
  });

  /// 평면 시점의 배율. 아이소메트릭 한 칸(대각선 방향 0.5·√2)과 비슷한 크기로
  /// 맞춰 시점을 바꿔도 지도가 갑자기 커지거나 작아지지 않게 한다.
  static const double _topDownK = 0.7071;

  Offset project(double x, double y, [double z = 0]) {
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    final rx = x * cosR - y * sinR;
    final ry = x * sinR + y * cosR;
    if (topDown) return Offset(rx * _topDownK * scale, ry * _topDownK * scale);
    return Offset(
      (rx - ry) * 0.5 * scale,
      (rx + ry) * 0.25 * scale - z * scale,
    );
  }

  /// 화면 2.5D 투영 좌표 (sx, sy) → 월드 지상 평면 좌표 (x, y) 역투영
  Offset unproject(double sx, double sy, [double z = 0]) {
    final double rx, ry;
    if (topDown) {
      rx = sx / (_topDownK * scale);
      ry = sy / (_topDownK * scale);
    } else {
      final adjSy = sy + z * scale;
      rx = (sx + 2 * adjSy) / scale;
      ry = (2 * adjSy - sx) / scale;
    }
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    final x = rx * cosR + ry * sinR;
    final y = -rx * sinR + ry * cosR;
    return Offset(x, y);
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

  /// 주차 구획선·횡단보도 줄무늬.
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

  /// 5m 보조 등고선 패스
  final Path contoursCombined;

  /// 10m/20m 주등고선 패스 (선명함)
  final Path majorContours;

  /// 등고선 위 표고 라벨 (예: 40m, 50m)
  final List<IsoElevationLabel> elevationLabels;

  /// 언덕 3D 힐쉐이딩(음영 및 하이라이트) 패스
  final Path hillshadeShadowPath;
  final Path hillshadeHighlightPath;

  /// 언덕길·경사도 랜드마크 뱃지 투영 정보
  final List<MapEntry<CampusSlopeMarker, Offset>> slopeMarkers;

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

  /// 주차장 P 심볼 뱃지 투영 중심점 목록
  final List<Offset> parkingBadgeCenters;

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
    required this.majorContours,
    required this.elevationLabels,
    required this.hillshadeShadowPath,
    required this.hillshadeHighlightPath,
    required this.slopeMarkers,
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
    this.parkingBadgeCenters = const [],
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
    majorContours: Path(),
    elevationLabels: const [],
    hillshadeShadowPath: Path(),
    hillshadeHighlightPath: Path(),
    slopeMarkers: const [],
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
    parkingBadgeCenters: const [],
  );
}

class IsoWall {
  final Path path;
  final double depth;
  final bool facingLeft;

  /// 이 벽에 난 창문들(자취방 건물만). 벽을 그린 **바로 뒤에** 칠해서, 뒤쪽
  /// 벽의 창문은 앞쪽 벽이 자연스럽게 가린다.
  final Path? windows;
  const IsoWall(this.path, this.depth, this.facingLeft, [this.windows]);
}

/// 창문 색: 벽 색보다 아주 조금 밝게(명도 +0.06). 이미 아주 밝은 벽(흰 벽)은
/// 더 밝힐 여지가 없으니 그만큼 어둡게 낸다. 순수 함수 — 테스트 대상.
Color windowColorFor(Color wall) {
  final hsl = HSLColor.fromColor(wall);
  const step = 0.06;
  final l = hsl.lightness + step <= 0.97 ? hsl.lightness + step : hsl.lightness - step;
  return hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
}

/// 벽 한 면의 창문 자리. [t0]~[t1]은 벽 모서리를 따라 0~1, [z0]~[z1]은 벽
/// 아래에서 잰 높이(미터).
typedef WallWindow = ({double t0, double t1, double z0, double z1});

/// 길이 [length]m, [floors]층(한 층 [floorHeight]m) 벽에 낼 창문 자리.
/// 순수 함수 — 테스트 대상.
///
/// 층마다 같은 간격으로 폭 2m 창문을 낸다. 층 높이의 25%~75% 자리에 두어
/// 층 사이 벽이 보이게 하고, 3m보다 짧은 벽(모서리 조각)은 비워 둔다.
/// (처음엔 1.1m 창을 2.6m마다 촘촘히 냈는데 작은 점이 빼곡해 징그러웠다 —
/// 크게, 드문드문.)
List<WallWindow> wallWindows(double length, int floors, double floorHeight) {
  const width = 2.0, pitch = 5.0, minWall = 3.0;
  if (length < minWall || floors < 1 || floorHeight <= 0) return const [];
  final n = ((length - 1.0) / pitch).floor().clamp(1, 1000);
  final half = width / 2 / length;
  return [
    for (var k = 0; k < floors; k++)
      for (var i = 0; i < n; i++)
        (
          t0: (i + 0.5) / n - half,
          t1: (i + 0.5) / n + half,
          z0: k * floorHeight + floorHeight * 0.25,
          z1: k * floorHeight + floorHeight * 0.75,
        ),
  ];
}

class IsoBuilding {
  final BaseBuilding building;
  final Path top;
  final List<IsoWall> walls;
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

Path _dashPath(Path source, double dashLength, double gapLength) {
  final dest = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var draw = true;
    while (distance < metric.length) {
      final len = draw ? dashLength : gapLength;
      if (draw) {
        dest.addPath(
          metric.extractPath(distance, math.min(distance + len, metric.length)),
          Offset.zero,
        );
      }
      distance += len;
      draw = !draw;
    }
  }
  return dest;
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

  // 사용자 요청: 등고선, 힐쉐이딩 및 경사도 표시 제거 (클린 지도 뷰)
  final contoursCombined = Path();
  final majorContours = Path();
  final elevationLabels = <IsoElevationLabel>[];
  final hillshadeShadowPath = Path();
  final hillshadeHighlightPath = Path();
  final slopeMarkers = <MapEntry<CampusSlopeMarker, Offset>>[];

  final parkingCombined = Path();
  for (final pts in terrain.parkingLots) {
    parkingCombined.addPath(_poly(projPts(pts)), Offset.zero);
  }

  // P 마크 제거: 빈 리스트 유지
  final parkingBadges = <Offset>[];

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
    majorContours: majorContours,
    elevationLabels: elevationLabels,
    hillshadeShadowPath: hillshadeShadowPath,
    hillshadeHighlightPath: hillshadeHighlightPath,
    slopeMarkers: slopeMarkers,
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
    parkingBadgeCenters: parkingBadges,
  );
}

/// 건물이 서 있는 지면 높이(언덕 고도). 지붕은 여기에 [IsoProjection.heightOf]를
/// 더한 높이에 그린다.
double buildingBaseZ(BaseBuilding b) {
  final c = b.center;
  return CampusElevation.elevationAt(c.dx, c.dy) * 0.45;
}

IsoBuilding buildIso(
  BaseBuilding b,
  IsoProjection p, {
  bool highlighted = false,
  bool isOneRoom = false,
  Color? zoneColor,
  String? displayName,
  bool? windows,
  bool labels = true,
}) {
  final c = b.center;
  // 실제 언덕 지형 고도(Elevation)를 기저 z축으로 반영하여 언덕 위의 건물들이 입체적으로 솟아오름!
  final baseZ = buildingBaseZ(b);
  final h = p.heightOf(b);
  final ring = b.ring;

  final topPts = ring.map((v) => p.project(v.dx, v.dy, baseZ + h)).toList();
  final bottomPts = ring.map((v) => p.project(v.dx, v.dy, baseZ)).toList();

  final cosR = math.cos(p.rotation);
  final sinR = math.sin(p.rotation);

  // 창문: 기본은 자취방 건물만, [windows]로 건물마다 켜고 끈다(건물 편집의
  // "창문 표시"). 위에서 보기는 높이가 없으니 뺀다. 층 높이는 지도에 그린
  // 높이를 층수로 나눠, 지도 높이를 따로 준 건물도 맞게 나눈다.
  final withWindows =
      (windows ?? (isOneRoom && !b.isCampus)) && !p.topDown && b.floors >= 1;
  final floorH = b.floors >= 1 ? h / b.floors : 0.0;

  final walls = <IsoWall>[];
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

    Path? windows;
    if (withWindows) {
      final spots = wallWindows((c - a).distance, b.floors, floorH);
      if (spots.isNotEmpty) {
        windows = Path();
        Offset at(double t, double z) =>
            p.project(a.dx + dx * t, a.dy + dy * t, baseZ + z);
        for (final w in spots) {
          windows.addPolygon([
            at(w.t0, w.z1),
            at(w.t1, w.z1),
            at(w.t1, w.z0),
            at(w.t0, w.z0),
          ], true);
        }
      }
    }

    walls.add(
      IsoWall(
        _poly([topPts[i], topPts[j], bottomPts[j], bottomPts[i]]),
        d,
        rdx < rdy,
        windows,
      ),
    );
  }
  walls.sort((x, y) => x.depth.compareTo(y.depth));

  final silhouette = Path()..addPath(_poly(topPts), Offset.zero);
  for (final w in walls) {
    silhouette.addPath(w.path, Offset.zero);
  }

  final topCenter = p.project(c.dx, c.dy, baseZ + h);

  // 네이버 지도 스타일 핀/라벨 (White Pill + Dark Font)
  TextPainter? cachedBadge;
  // 교내는 대장의 공식 명칭을, 교외는 호출부가 정해 준 이름([displayName])을
  // 쓴다. 예전엔 조건에 `b.isCampus`가 걸려 있어서 **교외 건물은 이름이
  // 있어도 이름표가 아예 안 만들어졌다** — 자취방 탭이 학생 제보로 모은
  // 이름이 정작 지도에서만 사라지고 있었다.
  // [labels]가 false면(지도의 "이름표" 끄기) 교내 공식 명칭까지 모두 뺀다.
  final labelText = labels ? (displayName ?? (b.isCampus ? b.officialName : null)) : null;
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
  Set<String> highlightedIds = const {},
  Set<String> oneRoomIds = const {},
  Map<String, Color> zoneColors = const {},
  Map<String, String> displayNames = const {},
  Set<String>? windowIds,
  bool showLabels = true,
  Set<String> hiddenLabelIds = const {},
}) {
  final sorted = buildings.toList()
    ..sort((a, b) => p.depthKey(a).compareTo(p.depthKey(b)));
  return sorted
      .map(
        (b) => buildIso(
          b,
          p,
          highlighted: b.id == selectedId || highlightedIds.contains(b.id),
          isOneRoom: oneRoomIds.contains(b.id),
          zoneColor: zoneColors[b.id],
          displayName: displayNames[b.id],
          windows: windowIds?.contains(b.id),
          // 이름표를 숨긴 건물은 교내 공식 명칭으로 대신 달지도 않는다 —
          // 대신 달면 추가 건물이 처음 받은 "신규 원룸"이 떠 버렸다.
          labels: showLabels && !hiddenLabelIds.contains(b.id),
        ),
      )
      .toList();
}

/// 2D 볼록 껍질 (Monotone Chain Convex Hull 알고리즘)
/// 건물 블록들을 하나로 병합할 때 정점들을 매끄러운 외곽선 다각형으로 묶는다.
List<Offset> computeConvexHull(List<Offset> points) {
  if (points.length <= 3) return List.from(points);

  final pts = points.toSet().toList()
    ..sort((a, b) {
      final cmp = a.dx.compareTo(b.dx);
      if (cmp != 0) return cmp;
      return a.dy.compareTo(b.dy);
    });

  if (pts.length <= 3) return pts;

  double crossProduct(Offset o, Offset a, Offset b) {
    return (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  }

  final lower = <Offset>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        crossProduct(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }

  final upper = <Offset>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        crossProduct(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }

  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
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
  // 네이버 지도 위계: 국도(간선)는 시원하게, 차도는 정갈하게, 보행로는 섬세하게
  const squash = 0.75;
  final byKey = <String, ({String kind, double width, Path path})>{};
  for (final r in roads) {
    if (r.points.length < 2) continue;
    double baseW;
    if (r.kind == 'major') {
      baseW = math.max(r.widthM, 8.5);
    } else if (r.kind == 'walk' || r.kind == 'path' || r.kind == 'steps') {
      baseW = math.max(r.widthM, 2.6);
    } else {
      baseW = math.max(r.widthM, 5.2);
    }
    final w = (baseW * p.scale * squash).clamp(1.2, 60.0);
    // 0.5px 단위로 묶어 Path 수를 줄인다.
    final q = (w * 2).round() / 2;
    final key = '${r.kind}|$q';
    final lane = byKey.putIfAbsent(
      key,
      () => (kind: r.kind, width: q, path: Path()),
    );
    // 도로의 각 점에 지반 고도(CampusElevation)를 반영하여 3차원 언덕 경사면을 따라 흐르도록 투영!
    final pts = r.points.map((v) {
      final z = CampusElevation.elevationAt(v.dx, v.dy) * 0.45;
      return p.project(v.dx, v.dy, z);
    }).toList();
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

/// 용도별 바닥색 (지적도 바닥면).
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

  /// 도보 등시선 링 기준점(정문·도서관 같은 거점이나 GPS 내 위치). null이면 그리지 않음.
  final IsochroneCenter? isochroneCenter;

  /// 등시선 링 및 투영 계산용 프로젝션
  final IsoProjection? projection;

  /// 시간별 건물 그림자(화면 좌표 경로, housing_sun.dart). null이면 안 그린다.
  final Path? shadows;

  /// 번호 TextPainter 재사용 캐시 — 프레임마다 layout()을 다시 돌리면
  /// 건물 100개분이 통째로 낭비된다.
  static final Map<int, TextPainter> _numberPainters = {};

  /// 지금 확대 배율. 이름표를 화면에서 늘 같은 크기로 그리려고 쓴다
  /// ([_paintLandmarkBadges] 참고). 확대·축소할 때마다 다시 그려야 하므로
  /// [view]를 [repaint]로 넘겨 컨트롤러가 바뀔 때만 갱신되게 한다.
  final TransformationController? view;

  double get viewScale =>
      (view?.value.getMaxScaleOnAxis() ?? 1.0).clamp(0.1, 8.0);

  /// 원룸 건물 시세 말풍선 맵 (건물 ID -> "300/35")
  final Map<String, String>? priceTags;

  /// 선택된 건물 -> 교원대 정문 도보 경로 가이드 좌표 및 소요 시간
  final Offset? walkGuideStart;
  final Offset? walkGuideEnd;
  final int? walkGuideMinutes;
  final int? walkGuideMeters;

  HousingMapPainter({
    required this.buildings,
    required this.roads,
    required this.terrain,
    required this.isDark,
    required this.origin,
    this.landuse = IsoLandUse.empty,
    this.osmRoads = IsoOsmRoads.empty,
    this.showBuildingNumbers = false,
    this.isochroneCenter,
    this.projection,
    this.view,
    this.shadows,
    this.priceTags,
    this.walkGuideStart,
    this.walkGuideEnd,
    this.walkGuideMinutes,
    this.walkGuideMeters,
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
    // [노이즈 제거] 예전 구형 도로 _paintRoads(canvas)는 매끈한 OSM 도로와 어긋나서 노이즈를 일으키므로 완전 제거!
    // 교외 골목/지적 필지 노면만 유지
    _paintRoadSurfaces(canvas);
    // 캡처에서 뽑은 교내 지형을 얹는다 (노이즈 포장면은 걷어내고 부지 바탕과 시설물만 유지)
    _paintTracedCampus(canvas);
    // 매끈한 3D 고도 반영 OSM 도로 & 인도/보도 분리 렌더링
    _paintOsmRoads(canvas);
    // 주차장 면 및 주차 구획선 (도로와 겹침 없이 선명하게 표시)
    _paintParkingAreasAndStalls(canvas);
    _paintCrosswalksAndIslands(canvas);
    // 도보 등시선 링 (노면 위, 건물 아래에 3D 동심원 배치하여 건물들이 링 위에 입체적으로 솟음)
    if (isochroneCenter != null && projection != null) {
      _paintIsochroneRings(canvas);
    }
    final shadowPath = shadows;
    if (shadowPath != null) {
      // 그림자끼리 겹친 곳이 두 번 어두워지지 않게, 불투명하게 한 층에 모두
      // 칠한 뒤 그 층을 반투명으로 얹는다.
      canvas.saveLayer(
        shadowPath.getBounds(),
        Paint()..color = Colors.black.withValues(alpha: isDark ? 0.38 : 0.2),
      );
      canvas.drawPath(shadowPath, Paint()..color = Colors.black);
      canvas.restore();
    }
    for (final b in buildings) {
      _paintBuilding(canvas, b);
    }
    _paintTrees(canvas);
    _paintBuildingNumbers(canvas);
    _paintLandmarkBadges(canvas);
    // 도보 등시선 뱃지 핀 (건물 위 상단 레이어에 3분/5분/10분 라벨 및 기준점 핀)
    if (isochroneCenter != null && projection != null) {
      _paintIsochroneBadges(canvas);
    }
    // 도보 경로 가이드 (선택된 건물 -> 교원대 정문 점선 경로 및 소요 시간 캡슐)
    if (walkGuideStart != null && walkGuideEnd != null && projection != null) {
      _paintWalkRouteGuide(canvas);
    }
    // 지도 위 말풍선 시세 마커 (Price Tag HUD)
    if (priceTags != null && priceTags!.isNotEmpty) {
      _paintPriceTagHUD(canvas);
    }

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
      // 녹지(공원, 산림, 농지) 구획 경계선
      if (use == LandUse.forest || use == LandUse.park) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..color = isDark
                ? const Color(0xFF28482E).withValues(alpha: 0.6)
                : const Color(0xFF98CB90).withValues(alpha: 0.7),
        );
      }
    }

    // 학교용지에만 얇은 테두리를 둘러 "여기가 교원대 부지"임을 드러낸다.
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
  void _paintTracedCampus(Canvas canvas) {
    final outline = terrain.campusOutline;
    if (outline.getBounds().isEmpty) return;

    // 네이버 지도 시그니처: 학교 부지는 맑고 정갈한 페일 스카이블루 (#DFEAF5)
    canvas.drawPath(
      outline,
      Paint()
        ..color = isDark ? const Color(0xFF1A2636) : const Color(0xFFDFEAF5),
    );

    // 국도는 네이버 지도 고유의 부드럽고 산뜻한 옐로우 (#FFE682)
    canvas.drawPath(
      terrain.majorRoads,
      Paint()
        ..color = isDark ? const Color(0xFF6B5820) : const Color(0xFFFFE682),
    );

    // 체육시설 (대운동장 트랙) — 네이버 지도 실사 샌드베이지 (#E4DFD5)
    canvas.drawPath(
      terrain.sportsFacilities,
      Paint()
        ..color = isDark ? const Color(0xFF383531) : const Color(0xFFE4DFD5),
    );
    // 부지 밖 숲 — 파스텔 포레스트 그린 + 정갈한 녹지 경계선
    canvas.drawPath(
      terrain.greensWood,
      Paint()
        ..color = isDark ? const Color(0xFF1B3120) : const Color(0xFFBDE4B6),
    );
    canvas.drawPath(
      terrain.greensWood,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = isDark ? const Color(0xFF28482E) : const Color(0xFF96CC8D),
    );

    // 교내 잔디 — 네이버 지도 파스텔 연녹색 (#C7E7C2) + 정갈한 녹지 경계선
    canvas.drawPath(
      terrain.greens,
      Paint()
        ..color = isDark ? const Color(0xFF254528) : const Color(0xFFC7E7C2),
    );
    canvas.drawPath(
      terrain.greens,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = isDark ? const Color(0xFF335E37) : const Color(0xFFA0D495),
    );
    // 축구장 선·트랙 레인 — 정갈한 화이트 라인
    canvas.drawPath(
      terrain.fieldLines,
      Paint()
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.30)
            : Colors.white.withValues(alpha: 0.85),
    );
    // 수계 (청람지) — 네이버 지도 시그니처 아쿠아 스카이블루 (#CCE6FA)
    canvas.drawPath(
      terrain.waterAreas,
      Paint()
        ..color = isDark ? const Color(0xFF15334A) : const Color(0xFFCCE6FA),
    );
    canvas.drawPath(
      terrain.crosswalkBars,
      Paint()
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.95),
    );

    // 부지 테두리 — 페일블루 부지와 자연스럽게 분리되는 소프트 블루그레이 외곽선
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = isDark
            ? const Color(0xFF2E4663)
            : const Color(0xFFB5CDE6),
    );
  }

  void _paintCampusBoundary(Canvas canvas) {
    if (terrain.campusBoundary.getBounds().isEmpty) return;

    // 네이버 지도 시그니처 캠퍼스 페일 스카이블루 일체화
    final campusFill = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark
          ? const Color(0xFF1A2636).withValues(alpha: 0.65)
          : const Color(0xFFDFEAF5).withValues(alpha: 0.85);
    canvas.drawPath(terrain.campusBoundary, campusFill);

    // 부지 경계 테두리
    final boundaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = isDark
          ? const Color(0xFF2E4663)
          : const Color(0xFFB5CDE6);
    canvas.drawPath(terrain.campusBoundary, boundaryPaint);
  }

  void _paintTerrain(Canvas canvas) {
    // 2. 청람동산 구릉지 녹지/숲 (네이버 지도 포레스트 그린)
    final forestPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark
          ? const Color(0xFF1B3120).withValues(alpha: 0.85)
          : const Color(0xFFBDE4B6).withValues(alpha: 0.95);
    final forestBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = isDark ? const Color(0xFF28482E) : const Color(0xFF96CC8D);
    canvas.drawPath(terrain.forestAreasCombined, forestPaint);
    canvas.drawPath(terrain.forestAreasCombined, forestBorder);

    // 3. 중앙 잔디광장 (네이버 지도 잔디밭 녹지)
    if (!terrain.centralPlaza.getBounds().isEmpty) {
      final plazaPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark
            ? const Color(0xFF23442A).withValues(alpha: 0.85)
            : const Color(0xFFC7E7C2).withValues(alpha: 0.95);
      final plazaBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = isDark
            ? const Color(0xFF388E3C).withValues(alpha: 0.4)
            : const Color(0xFFA0D495);
      canvas.drawPath(terrain.centralPlaza, plazaPaint);
      canvas.drawPath(terrain.centralPlaza, plazaBorder);
    }

    // 3-1. 기숙사 중앙 잔디마당
    if (!terrain.dormCourtyard.getBounds().isEmpty) {
      final dormPlazaPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark
            ? const Color(0xFF1E3A24).withValues(alpha: 0.85)
            : const Color(0xFFC7E7C2).withValues(alpha: 0.95);
      final dormPlazaBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = isDark
            ? const Color(0xFF335E37)
            : const Color(0xFFA0D495);
      canvas.drawPath(terrain.dormCourtyard, dormPlazaPaint);
      canvas.drawPath(terrain.dormCourtyard, dormPlazaBorder);
    }

    // 5. 대운동장 (네이버 지도 실사: 차분하고 고급스러운 샌드베이지 트랙 & 파스텔 연녹색 필드)
    if (!terrain.athleticTrack.getBounds().isEmpty) {
      final trackPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF383531) : const Color(0xFFE4DFD5);
      canvas.drawPath(terrain.athleticTrack, trackPaint);

      final pitchPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF224424) : const Color(0xFFC6E7C4);
      canvas.drawPath(terrain.athleticPitch, pitchPaint);

      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: isDark ? 0.40 : 0.85);
      canvas.drawPath(terrain.athleticTrack, linePaint);
      canvas.drawPath(terrain.athleticPitch, linePaint);

      if (!terrain.grandstand.getBounds().isEmpty) {
        final standPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = isDark ? const Color(0xFF2E353D) : const Color(0xFFD5D2CA);
        canvas.drawPath(terrain.grandstand, standPaint);
      }
    }

    // 6. 야외 체육코트 (네이버 지도 실사: 파스텔 연두 및 산뜻한 라임 코트)
    if (!terrain.basketballCourt.getBounds().isEmpty) {
      final bballPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF1E3A24) : const Color(0xFFC2E5BD);
      final bballBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: isDark ? 0.4 : 0.8);
      canvas.drawPath(terrain.basketballCourt, bballPaint);
      canvas.drawPath(terrain.basketballCourt, bballBorder);
    }

    if (!terrain.tennisCourt.getBounds().isEmpty) {
      final courtPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF224824) : const Color(0xFFBFE4BE);
      final courtBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: isDark ? 0.4 : 0.8);
      canvas.drawPath(terrain.tennisCourt, courtPaint);
      canvas.drawPath(terrain.tennisCourt, courtBorder);
    }

    // 7. 청람지 (네이버 지도 대표 아쿠아 스카이블루 수계)
    if (!terrain.pond.getBounds().isEmpty) {
      final pondPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isDark ? const Color(0xFF15334A) : const Color(0xFFCCE6FA);
      final pondBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = isDark ? const Color(0xFF265270) : const Color(0xFFA8D4F7);

      canvas.drawPath(terrain.pond, pondPaint);
      canvas.drawPath(terrain.pond, pondBorder);

      // 목교 아치 다리
      if (!terrain.pondBridge.getBounds().isEmpty) {
        final bridgePaint = Paint()
          ..style = PaintingStyle.fill
          ..color = isDark ? const Color(0xFF4A3830) : const Color(0xFFC5B8B0);
        final bridgeRailing = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = isDark ? const Color(0xFF6E554B) : const Color(0xFF9E8D85);
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

    // 네이버 지도 스타일: 소프트 블루그레이 케이싱 위에 순백색 노면
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round
        ..color = isDark ? const Color(0xFF1E242C) : const Color(0xFFCCD7E6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = landUseColor(LandUse.road, isDark),
    );
  }

  /// OSM 도로망 및 인도(보도) 정밀 분리 렌더링.
  ///
  /// - 일반 차도(road):
  ///   양옆으로 정갈한 보도블록(Sidewalk)이 형성되도록 케이싱 위에 보도를 깔고,
  ///   차도와 보도 사이 연석(Curb Line)을 두어 순백색 차도와 확실히 분리!
  /// - 태성탑연로(major):
  ///   네이버 시그니처 옐로우(#FFE682) + 골드 케이싱 + 양옆 보도.
  /// - 보행자 전용 도로(walk, path, steps):
  ///   차도(White)와 완전히 구별되는 산뜻한 보도블록 톤(#E0EFE3) + 중앙 보행 점선(Dash line).
  void _paintOsmRoads(Canvas canvas) {
    if (osmRoads.lanes.isEmpty) return;

    bool isPedestrian(String kind) =>
        kind == 'walk' || kind == 'path' || kind == 'steps';

    Paint stroke(double w, Color c, {StrokeCap cap = StrokeCap.round}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w
      ..color = c;

    // 1단계: 차도 양옆 인도(보도) 베이스 레이어 & 보행로 케이싱
    for (final l in osmRoads.lanes) {
      if (isPedestrian(l.kind)) {
        // 보행로 외곽 케이싱
        canvas.drawPath(
          l.path,
          stroke(
            l.width + 1.6,
            isDark ? const Color(0xFF192A1D) : const Color(0xFFB5CEB9),
          ),
        );
      } else {
        // 차도 외곽의 보도(인도) 바깥 테두리 케이싱
        final outerCasing = isDark ? const Color(0xFF18221B) : const Color(0xFFC0D0C3);
        canvas.drawPath(l.path, stroke(l.width + 5.0, outerCasing));
        // 차도 양옆 보도블록 면 (Sidewalk surface)
        final sidewalkColor = isDark ? const Color(0xFF1E2822) : const Color(0xFFE4ECE6);
        canvas.drawPath(l.path, stroke(l.width + 3.6, sidewalkColor));
      }
    }

    // 2단계: 차도-인도 분리 연석선 (Curb Line) & 보행로 노면
    for (final l in osmRoads.lanes) {
      if (isPedestrian(l.kind)) {
        // 보행로 본면 (차도와 확연히 다른 파스텔 보도블록 톤)
        final walkColor = isDark ? const Color(0xFF223628) : const Color(0xFFE1EFE4);
        canvas.drawPath(l.path, stroke(l.width, walkColor));
      } else {
        // 차도와 보도 사이의 연석 경계선
        final curbColor = isDark ? const Color(0xFF2B3744) : const Color(0xFFB8C8D5);
        canvas.drawPath(l.path, stroke(l.width + 1.0, curbColor));
      }
    }

    // 3단계: 차도 본면 (Carriageway surface)
    for (final l in osmRoads.lanes) {
      if (isPedestrian(l.kind)) continue;
      final surfaceColor = l.kind == 'major'
          ? (isDark ? const Color(0xFF6B5820) : const Color(0xFFFFE682))
          : (isDark ? const Color(0xFF2C323B) : const Color(0xFFFFFFFF));
      canvas.drawPath(l.path, stroke(l.width, surfaceColor));
    }

    // 4단계: 보행자 전용 도로 디테일 (중앙 보행 점선 & 계단 단차)
    for (final l in osmRoads.lanes) {
      if (l.kind == 'steps') {
        final stepDashes = _dashPath(l.path, 1.4, 2.0);
        canvas.drawPath(
          stepDashes,
          stroke(
            l.width * 0.9,
            isDark ? Colors.white24 : const Color(0xFF8FA894),
            cap: StrokeCap.butt,
          ),
        );
      } else if (l.kind == 'walk' || l.kind == 'path') {
        final walkDash = _dashPath(l.path, 2.6, 2.2);
        canvas.drawPath(
          walkDash,
          stroke(
            0.8,
            isDark ? Colors.white24 : Colors.white.withValues(alpha: 0.9),
          ),
        );
      }
    }
  }

  /// 주차장 노면 및 주차 구획선 (도로와 조화롭게 분리되어 한눈에 식별)
  void _paintParkingAreasAndStalls(Canvas canvas) {
    // 1. 주차장 노면 (쿨 블루그레이 아스팔트)
    final parkingFill = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark ? const Color(0xFF202A36) : const Color(0xFFE5EDF5);

    // 2. 주차장 연석 경계 테두리
    final parkingBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round
      ..color = isDark ? const Color(0xFF334252) : const Color(0xFFBACCDD);

    if (!terrain.parking.getBounds().isEmpty) {
      canvas.drawPath(terrain.parking, parkingFill);
      canvas.drawPath(terrain.parking, parkingBorder);
    }
    if (!terrain.parkingLotsCombined.getBounds().isEmpty) {
      canvas.drawPath(terrain.parkingLotsCombined, parkingFill);
      canvas.drawPath(terrain.parkingLotsCombined, parkingBorder);
    }

    // 3. 주차 구획선 (선명한 화이트 실선 1.1dp)
    final stallPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.45)
          : const Color(0xFFFFFFFF);

    if (!terrain.parkingStalls.getBounds().isEmpty) {
      canvas.drawPath(terrain.parkingStalls, stallPaint);
    }
  }

  void _paintCrosswalksAndIslands(Canvas canvas) {
    final cwPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.butt
      ..color = isDark ? Colors.white38 : const Color(0xFFFFFFFF);
    canvas.drawPath(terrain.crosswalkStripesCombined, cwPaint);

    final islandPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isDark ? const Color(0xFF224424) : const Color(0xFFC6E7C4);
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
    } else if (b.zoneColor != null) {
      // 관리자가 칠한 색이 교내 용도 색보다 먼저다. 예전엔 교내 건물이면
      // 용도 색부터 칠해 버려서 다정관 같은 교내 건물은 색을 바꿔도 그대로였다.
      // (교내 건물엔 housingMapStyle이 관리자 색만 넘긴다 — 구역·도로 색은 없다.)
      base = isDark ? _dimForDark(b.zoneColor!) : b.zoneColor!;
    } else if (b.building.isCampus) {
      base = campusUseColor(b.building.use, isDark);
    } else if (b.isOneRoom) {
      // 자취방/원룸 건물: 네이버 지도 실사의 깔끔한 소프트 화이트-민트 틴트
      base = isDark ? const Color(0xFF22352B) : const Color(0xFFFFFFFF);
    } else {
      // 일반 민간 주택 / 상가 건물: 네이버 지도 특유의 정갈한 순백색
      base = isDark ? const Color(0xFF2A3340) : const Color(0xFFFFFFFF);
    }

    final topPaint = Paint()..color = base;

    // 네이버 지도 3D 입체 음영 체계:
    // 북서향 조명에 의한 맑은 쿨 화이트그레이 좌측벽 & 정돈된 소프트 슬레이트그레이 우측벽
    // 색을 정한 건물(선택·구역·관리자 색)은 벽도 그 색으로 — 옥상만 칠하면
    // 회색 상자에 색 뚜껑을 얹은 것처럼 보인다. 벽은 옥상보다 조금씩 어둡게.
    final tinted = b.highlighted || b.zoneColor != null;
    final leftPaint = Paint()
      ..color = tinted
          ? _shade(base, 0.08)
          : (isDark ? const Color(0xFF222933) : const Color(0xFFEFF3F8));
    final rightPaint = Paint()
      ..color = tinted
          ? _shade(base, 0.16)
          : (isDark ? const Color(0xFF191F26) : const Color(0xFFE2E8F0));

    // 창문: 멀리서 보면 점으로 뭉개지고 그리기만 무거우니 어느 정도 확대했을 때만.
    final showWindows = viewScale >= 0.7;
    // 창문 색은 그 벽 색에서 아주 조금만 밝게 — 벽에 녹아들어 가까이 봐야
    // 보일 정도로. (흰 창·불 켜진 창은 너무 튀었다.) 흰 벽처럼 이미 밝은
    // 벽은 더 밝힐 여지가 없어 조금 어둡게 낸다.
    Paint windowPaintFor(Color wall) => Paint()..color = windowColorFor(wall);
    final leftWindow = windowPaintFor(leftPaint.color);
    final rightWindow = windowPaintFor(rightPaint.color);
    for (final w in b.walls) {
      canvas.drawPath(w.path, w.facingLeft ? leftPaint : rightPaint);
      final win = w.windows;
      if (showWindows && win != null) {
        canvas.drawPath(win, w.facingLeft ? leftWindow : rightWindow);
      }
    }
    canvas.drawPath(b.top, topPaint);

    // 네이버 지도 시그니처: 가늘고 섬세한 0.7px 소프트 블루그레이 외곽선 (#B8C8D9)
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = b.highlighted ? 2.0 : 0.7
      ..color = b.highlighted
          ? const Color(0xFF03C75A)
          : (isDark
                ? const Color(0xFF455263)
                : const Color(0xFFB8C8D9));
    canvas.drawPath(b.top, edge);

    // 다층 건물 옥상 파라펫 (네이버 지도처럼 군더더기 없이 단정하고 미세한 0.4px 라인)
    if (b.building.floors >= 2 && !b.highlighted) {
      final parapetPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.4
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFDCE5F0);
      canvas.drawPath(b.top, parapetPaint);
    }

    if (b.highlighted) {
      canvas.drawPath(
        b.silhouette,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = const Color(0xFF03C75A),
      );
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
      // 선택한 건물은 초록 알약 위 흰 글씨라 두 테마 모두 그대로 쓴다.
      final label = b.displayName;
      final tp = (isDark && !b.highlighted && label != null)
          ? _darkBadge(label)
          : b.cachedBadgePainter!;
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

  /// 선택된 건물에서 교원대 정문까지 도보 점선 경로 및 소요 시간 가이드 캡슐
  void _paintWalkRouteGuide(Canvas canvas) {
    if (walkGuideStart == null || walkGuideEnd == null || projection == null) return;
    final k = 1.0 / viewScale;
    final p = projection!;

    final startZ = CampusElevation.elevationAt(walkGuideStart!.dx, walkGuideStart!.dy) * 0.45;
    final startPt = p.project(walkGuideStart!.dx, walkGuideStart!.dy, startZ);

    final endZ = CampusElevation.elevationAt(walkGuideEnd!.dx, walkGuideEnd!.dy) * 0.45;
    final endPt = p.project(walkGuideEnd!.dx, walkGuideEnd!.dy, endZ);

    final diff = endPt - startPt;
    final totalDist = diff.distance;
    if (totalDist < 1.0) return;
    final dir = diff / totalDist;

    // 1. 점선(Dashed Line) 경로 렌더링
    final dashLen = 7.0 * k;
    final gapLen = 4.5 * k;
    final pathPaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..strokeWidth = 2.4 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.45 : 0.18)
      ..strokeWidth = 3.6 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    double d = 0;
    while (d < totalDist) {
      final curStart = startPt + dir * d;
      final curLen = math.min(dashLen, totalDist - d);
      final curEnd = curStart + dir * curLen;
      // 그림자
      canvas.drawLine(curStart + Offset(0, 1.2 * k), curEnd + Offset(0, 1.2 * k), shadowPaint);
      // 점선
      canvas.drawLine(curStart, curEnd, pathPaint);
      d += dashLen + gapLen;
    }

    // 2. 정문 도착점 핀 마커 ("교원대 정문")
    const gatePinColor = Color(0xFF10B981); // Emerald Green
    // 그림자
    canvas.drawOval(
      Rect.fromCenter(center: endPt + Offset(0, 2 * k), width: 14 * k, height: 6 * k),
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
    // 핀 원형
    canvas.drawCircle(endPt, 5.5 * k, Paint()..color = Colors.white);
    canvas.drawCircle(endPt, 4.0 * k, Paint()..color = gatePinColor);

    // 정문 라벨 뱃지
    const gateLabel = '교원대 정문';
    final gateTp = TextPainter(
      text: TextSpan(
        text: gateLabel,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          fontFamily: KnueTokens.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final gateBadgeW = (gateTp.width + 10) * k;
    final gateBadgeH = (gateTp.height + 5) * k;
    final gateBadgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: endPt + Offset(0, -11 * k), width: gateBadgeW, height: gateBadgeH),
      Radius.circular(6 * k),
    );
    canvas.drawRRect(gateBadgeRect, Paint()..color = gatePinColor);
    canvas.drawRRect(
      gateBadgeRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 * k
        ..color = Colors.white.withValues(alpha: 0.8),
    );
    canvas.save();
    canvas.translate(endPt.dx, endPt.dy - 11 * k);
    canvas.scale(k);
    gateTp.paint(canvas, Offset(-gateTp.width / 2, -gateTp.height / 2));
    canvas.restore();

    // 3. 경로 중간 "정문 도보 N분 (000m)" 소요 시간 캡슐 뱃지
    if (walkGuideMinutes != null) {
      final midPt = startPt + dir * (totalDist * 0.48);
      final minutes = walkGuideMinutes!;
      final meters = walkGuideMeters ?? (totalDist * 0.8).round();
      final routeText = '정문 도보 $minutes분 (${meters}m)';

      final routeTp = TextPainter(
        text: TextSpan(
          children: [
            const TextSpan(text: '🚶 ', style: TextStyle(fontSize: 9.5)),
            TextSpan(
              text: routeText,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1E293B),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                fontFamily: KnueTokens.fontFamily,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final routeW = (routeTp.width + 14) * k;
      final routeH = (routeTp.height + 7) * k;
      final routeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: midPt + Offset(0, -10 * k), width: routeW, height: routeH),
        Radius.circular(12 * k),
      );

      // 캡슐 배경 & 그림자
      canvas.drawRRect(
        routeRect.shift(Offset(0, 1.8 * k)),
        Paint()..color = Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
      );
      canvas.drawRRect(
        routeRect,
        Paint()..color = isDark ? const Color(0xFF1E222A) : Colors.white,
      );
      canvas.drawRRect(
        routeRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * k
          ..color = const Color(0xFF007AFF),
      );

      canvas.save();
      canvas.translate(midPt.dx, midPt.dy - 10 * k);
      canvas.scale(k);
      routeTp.paint(canvas, Offset(-routeTp.width / 2, -routeTp.height / 2));
      canvas.restore();
    }
  }

  /// 지도 위 말풍선 시세 마커 (Price Tag HUD)
  void _paintPriceTagHUD(Canvas canvas) {
    if (priceTags == null || priceTags!.isEmpty) return;
    final k = 1.0 / viewScale;

    final targetBuildings = buildings.where((b) {
      if (!priceTags!.containsKey(b.building.id)) return false;
      if (b.building.isCampus) return false;
      return true;
    }).toList();

    // 선택된 건물이 가장 위로 오도록 정렬
    targetBuildings.sort((a, b) {
      if (a.highlighted != b.highlighted) return a.highlighted ? -1 : 1;
      return b.building.footprintArea.compareTo(a.building.footprintArea);
    });

    final placed = <Rect>[];
    for (final b in targetBuildings) {
      final tag = priceTags![b.building.id];
      if (tag == null || tag.isEmpty) continue;

      final isHighlight = b.highlighted;
      final tp = TextPainter(
        text: TextSpan(
          text: tag,
          style: TextStyle(
            color: isHighlight
                ? Colors.white
                : (isDark ? Colors.white : const Color(0xFF0F172A)),
            fontSize: isHighlight ? 9.5 : 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            fontFamily: KnueTokens.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final w = (tp.width + (isHighlight ? 12 : 9)) * k;
      final h = (tp.height + (isHighlight ? 6 : 4.5)) * k;
      final center = b.topCenter;

      // 건물 이름 뱃지가 있으면 그 위(-22k), 없으면 지붕 위(-10k)
      final dyOffset = (b.cachedBadgePainter != null ? -22.0 : -10.0) * k;
      final rect = Rect.fromCenter(
        center: Offset(center.dx, center.dy + dyOffset),
        width: w,
        height: h,
      );

      // 선택된 건물이 아닌 경우 겹치면 패스
      if (!isHighlight && placed.any(rect.overlaps)) continue;
      placed.add(rect);

      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(5 * k));

      if (isHighlight) {
        // 하이라이트 말풍선: 선명한 블루(#007AFF) 알약 태그
        canvas.drawRRect(
          rrect.shift(Offset(0, 1.5 * k)),
          Paint()..color = Colors.black.withValues(alpha: 0.35),
        );
        canvas.drawRRect(
          rrect,
          Paint()..color = const Color(0xFF007AFF),
        );
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 * k
            ..color = Colors.white,
        );
      } else {
        // 일반 말풍선: 정갈한 카드 칩
        canvas.drawRRect(
          rrect.shift(Offset(0, 1.2 * k)),
          Paint()..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
        );
        canvas.drawRRect(
          rrect,
          Paint()..color = isDark ? const Color(0xFF1E2228) : Colors.white,
        );
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8 * k
            ..color = isDark
                ? Colors.white.withValues(alpha: 0.15)
                : const Color(0xFF007AFF).withValues(alpha: 0.35),
        );
      }

      // 글씨 렌더링
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.scale(k);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  /// 다크 모드용으로 색을 가라앉힌다. 색상(hue)은 그대로 둬야 "초록 = 월탄3길"
  /// 같은 뜻이 두 테마에서 똑같이 읽힌다.
  static Color _dimForDark(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness(hsl.lightness.clamp(0.0, 0.36))
        .withSaturation((hsl.saturation * 0.7).clamp(0.0, 1.0))
        .toColor();
  }

  /// 다크 모드 이름표 글씨. 캐시한 TextPainter는 밝은 테마 글자색(짙은
  /// 회색)으로 구워져 있어서, 다크 모드의 짙은 알약 위에 그대로 그리면
  /// **글씨가 안 보였다**(#222831 글자 위에 #242830 바탕). 글자는 같고
  /// 색만 다른 painter를 따로 굽는다.
  static final Map<String, TextPainter> _darkBadgePainters = {};

  static TextPainter _darkBadge(String text) =>
      _darkBadgePainters.putIfAbsent(
        text,
        () => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: const Color(0xFFE8EAED),
              fontSize: 9.0,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              fontFamily: KnueTokens.fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );

  Color _shade(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// 도보 등시선 링 3D 경로 생성 (지형 고도를 반영하여 매끄러운 아이소메트릭 등시선 생성)
  Path _buildIsochroneRingPath(Offset center, double radiusMeters) {
    final path = Path();
    const count = 72;
    for (var i = 0; i <= count; i++) {
      final rad = (i * 2 * math.pi) / count;
      final wx = center.dx + radiusMeters * math.cos(rad);
      final wy = center.dy + radiusMeters * math.sin(rad);
      final elev = CampusElevation.elevationAt(wx, wy) * 0.45;
      final pt = projection!.project(wx, wy, elev);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  /// 도보 등시선 링 (지표면 바닥에 3분 / 5분 / 10분 동심원과 은은한 채색)
  void _paintIsochroneRings(Canvas canvas) {
    if (isochroneCenter == null || projection == null) return;
    final center = isochroneCenter!.position;

    // 10분(약 558m), 5분(약 279m), 3분(약 168m)
    // 외곽부터 채워 안쪽 링이 자연스럽게 중첩되도록 렌더링
    final path10 = _buildIsochroneRingPath(center, 558.0);
    final path5 = _buildIsochroneRingPath(center, 279.0);
    final path3 = _buildIsochroneRingPath(center, 168.0);

    // 1. 내부 은은한 반투명 채우기
    final fill10 = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.03 : 0.025);
    final fill5 = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF007AFF).withValues(alpha: isDark ? 0.045 : 0.035);
    final fill3 = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF03C75A).withValues(alpha: isDark ? 0.065 : 0.05);

    canvas.drawPath(path10, fill10);
    canvas.drawPath(path5, fill5);
    canvas.drawPath(path3, fill3);

    // 2. 등시선 대시 점선 스트로크 테두리
    final stroke10 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.55 : 0.65);
    final stroke5 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF007AFF).withValues(alpha: isDark ? 0.65 : 0.75);
    final stroke3 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF03C75A).withValues(alpha: isDark ? 0.8 : 0.9);

    canvas.drawPath(_dashPath(path10, 5.0, 4.0), stroke10);
    canvas.drawPath(_dashPath(path5, 6.0, 3.5), stroke5);
    canvas.drawPath(_dashPath(path3, 8.0, 3.0), stroke3);

    // 3. 중심점 기준점 펄스 링 (지표면)
    final centerElev = CampusElevation.elevationAt(center.dx, center.dy) * 0.45;
    final centerPt = projection!.project(center.dx, center.dy, centerElev);

    canvas.drawCircle(
      centerPt,
      7.0,
      Paint()..color = const Color(0xFF007AFF).withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      centerPt,
      3.5,
      Paint()..color = const Color(0xFF007AFF),
    );
    canvas.drawCircle(
      centerPt,
      3.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white,
    );
  }

  /// 도보 등시선 뱃지 핀 (건물 상단 레이어에 3분/5분/10분 및 거점명 라벨 노출)
  void _paintIsochroneBadges(Canvas canvas) {
    if (isochroneCenter == null || projection == null) return;
    final k = 1.0 / viewScale;
    final center = isochroneCenter!.position;

    // 1. 기준 거점 핀 뱃지
    final centerElev = CampusElevation.elevationAt(center.dx, center.dy) * 0.45;
    final centerPt = projection!.project(center.dx, center.dy, centerElev);

    final landmarkTp = TextPainter(
      text: TextSpan(
        text: '📍 ${isochroneCenter!.label} 기준 도보권',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          fontFamily: KnueTokens.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final lmWidth = (landmarkTp.width + 14) * k;
    final lmHeight = (landmarkTp.height + 6) * k;
    final lmRect = Rect.fromCenter(
      center: Offset(centerPt.dx, centerPt.dy - 12 * k),
      width: lmWidth,
      height: lmHeight,
    );
    final lmRRect = RRect.fromRectAndRadius(lmRect, Radius.circular(8 * k));

    // 그림자 + 블루 캡슐
    canvas.drawRRect(
      lmRRect.shift(Offset(0, 1.5 * k)),
      Paint()..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.18),
    );
    canvas.drawRRect(
      lmRRect,
      Paint()..color = isDark ? const Color(0xFF1D4ED8) : const Color(0xFF007AFF),
    );
    canvas.drawRRect(
      lmRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * k
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    canvas.save();
    canvas.translate(lmRect.left + 7 * k, lmRect.top + 3 * k);
    canvas.scale(k);
    landmarkTp.paint(canvas, Offset.zero);
    canvas.restore();

    // 2. 링별 도보 뱃지 (남서-남 방향 각도로 배치하여 건물 간섭 최소화)
    final badgeItems = [
      (168.0, '🚶 3분 (약 200m)', const Color(0xFF03C75A)),
      (279.0, '🚶 5분 (약 340m)', const Color(0xFF007AFF)),
      (558.0, '🚶 10분 (약 670m)', const Color(0xFFF59E0B)),
    ];

    const labelAngle = 0.42 * math.pi; // 남동-남 방향
    for (final item in badgeItems) {
      final r = item.$1;
      final text = item.$2;
      final color = item.$3;

      final wx = center.dx + r * math.cos(labelAngle);
      final wy = center.dy + r * math.sin(labelAngle);
      final elev = CampusElevation.elevationAt(wx, wy) * 0.45;
      final pt = projection!.project(wx, wy, elev);

      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            fontFamily: KnueTokens.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final w = (tp.width + 10) * k;
      final h = (tp.height + 4) * k;
      final rect = Rect.fromCenter(
        center: Offset(pt.dx, pt.dy),
        width: w,
        height: h,
      );
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(6 * k));

      canvas.drawRRect(
        rrect.shift(Offset(0, 1.2 * k)),
        Paint()..color = Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = isDark ? color.withValues(alpha: 0.9) : color,
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 * k
          ..color = Colors.white.withValues(alpha: 0.85),
      );

      canvas.save();
      canvas.translate(rect.left + 5 * k, rect.top + 2 * k);
      canvas.scale(k);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(HousingMapPainter old) =>
      old.buildings != buildings ||
      old.roads != roads ||
      old.terrain != terrain ||
      old.landuse != landuse ||
      old.isDark != isDark ||
      old.origin != origin ||
      old.isochroneCenter != isochroneCenter ||
      old.shadows != shadows;
}

/// 교내 건물 지붕 색 (네이버 지도 정밀 매칭: 정갈하고 눈부신 순백색 화이트 #FFFFFF)
Color campusUseColor(BuildingUse? use, bool isDark) {
  if (isDark) {
    return switch (use) {
      BuildingUse.academic => const Color(0xFF2B3542),
      BuildingUse.library => const Color(0xFF2F3748),
      BuildingUse.student => const Color(0xFF333842),
      BuildingUse.dorm => const Color(0xFF28323E),
      BuildingUse.sports => const Color(0xFF273638),
      BuildingUse.culture => const Color(0xFF32303A),
      BuildingUse.training => const Color(0xFF293530),
      BuildingUse.admin => const Color(0xFF2E333C),
      BuildingUse.affiliate => const Color(0xFF303433),
      _ => const Color(0xFF2A3340),
    };
  }
  // 네이버 지도 실사 캡처 그대로: 모든 교내 건물 상판은 티없이 맑고 깨끗한 순백색(#FFFFFF)
  return const Color(0xFFFFFFFF);
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
