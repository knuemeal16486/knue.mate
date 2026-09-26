import 'housing_service.dart';

/// 직접 물어 모은 원룸 시세 한 줄. 금액은 만원.
///
/// [names]는 **지도에 뜨는 건물 이름**이다(개발자 모드에서 고친 이름 포함,
/// 띄어쓰기는 무시). 동을 가리지 않은 아파트 시세처럼 여러 건물에 똑같이
/// 해당하면 이름을 여럿 적는다.
class HousingSurveyEntry {
  final List<String> names;
  final HousingRoomType? roomType;
  final int deposit;
  final int monthlyRent;

  /// 관리비를 따로 들었을 때만. 대개 월세에 포함이지만 아닐 수도 있어서,
  /// 모르면 null로 둔다(0으로 두면 "관리비 없음"이 된다).
  final int? maintenanceFee;

  const HousingSurveyEntry(
    this.names,
    this.deposit,
    this.monthlyRent, {
    this.roomType = HousingRoomType.oneRoom,
    this.maintenanceFee,
  });
}

/// 시세 조사를 모은 날. 요약의 "최근 제보" 시점으로 쓰인다.
final kHousingSurveyDate = DateTime(2026, 9, 27);

const _oneRoom = HousingRoomType.oneRoom;
const _onePointFive = HousingRoomType.onePointFive;
const _twoRoom = HousingRoomType.twoRoom;

const _taeam = ['태암수정아파트 101동', '태암수정아파트 102동', '태암수정아파트 103동'];

/// 2026-09 직접 물어 모은 시세. 학생 제보와 함께 **시세 평균에** 섞인다.
///
/// 따로 적지 않았으면 원룸이다. 전세는 월세 시세와 섞으면 보증금 평균이
/// 튀어서 [kHousingJeonse]에 따로 둔다.
const kHousingSurvey = <HousingSurveyEntry>[
  HousingSurveyEntry(['청람드림빌 D'], 200, 30),
  HousingSurveyEntry(['국보빌'], 200, 30),
  HousingSurveyEntry(['행운빌'], 200, 60, roomType: _twoRoom),
  HousingSurveyEntry(['위너스빌'], 200, 35),
  // 조사 땐 '삼성프리하우스'라고 들었다. 지도 이름은 프리하우스.
  HousingSurveyEntry(['프리하우스'], 200, 30, maintenanceFee: 1),
  HousingSurveyEntry(['프라임'], 200, 37, roomType: _oneRoom),
  HousingSurveyEntry(['프라임'], 400, 70, roomType: _twoRoom),
  HousingSurveyEntry(['대성빌'], 200, 30),
  // 13평이라 원룸인지 확실치 않아 구조는 비워 둔다.
  HousingSurveyEntry(['서호e타운 101동'], 100, 20, roomType: null),
  HousingSurveyEntry(['태암수정아파트 101동'], 200, 30),
  HousingSurveyEntry(['아우름빌'], 200, 35),
  HousingSurveyEntry(['위너스빌'], 200, 30),
  HousingSurveyEntry(['프라임'], 500, 70, roomType: _twoRoom),
  HousingSurveyEntry(['승방빌'], 200, 30),
  HousingSurveyEntry(['대성빌'], 200, 30),
  HousingSurveyEntry(['청람드림빌 B'], 200, 31),
  HousingSurveyEntry(['초록빌'], 300, 50, roomType: _twoRoom, maintenanceFee: 2),
  HousingSurveyEntry(['미래로빌'], 300, 35, maintenanceFee: 3),
  HousingSurveyEntry(['엘리트빌'], 300, 30),
  HousingSurveyEntry(['더베이스'], 300, 32),
  HousingSurveyEntry(_taeam, 300, 40),
  HousingSurveyEntry(['에듀빌'], 300, 32),
  HousingSurveyEntry(['청람드림빌 A'], 300, 30),
  HousingSurveyEntry(['다솜빌'], 300, 30),
  HousingSurveyEntry(['누리봄'], 300, 33),
  HousingSurveyEntry(['디저트 39'], 300, 38, roomType: _oneRoom),
  HousingSurveyEntry(['디저트 39'], 500, 45, roomType: _onePointFive),
  HousingSurveyEntry(['대성빌'], 200, 30),
  HousingSurveyEntry(['가온빌'], 300, 33),
  HousingSurveyEntry(['미래로빌'], 300, 35),
  HousingSurveyEntry(['성균관'], 300, 32),
  HousingSurveyEntry(['국보빌'], 300, 30),
  HousingSurveyEntry(['청람드림빌 C'], 300, 30),
  HousingSurveyEntry(['더베이스'], 300, 33),
  HousingSurveyEntry(['가온빌'], 300, 33),
  HousingSurveyEntry(['엘리트빌'], 300, 36),
  HousingSurveyEntry(['디저트 39'], 300, 45, roomType: _onePointFive),
  HousingSurveyEntry(['메이플빌'], 500, 45, roomType: _twoRoom),
  HousingSurveyEntry(['자연빌'], 500, 45, roomType: _twoRoom),
  HousingSurveyEntry(['메이플빌'], 500, 50, roomType: _twoRoom),
];

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// 시세 조사를 건물 id별 제보로 바꾼다. [nameById]는 지도에 뜨는 이름이다.
///
/// 이름이 같은 건물이 여럿이면(쪼갠 조각 등) 모두에 붙는다. 지도에 없는
/// 이름은 버린다.
Map<String, List<HousingReport>> housingSurveyReports(
  Map<String, String> nameById, {
  List<HousingSurveyEntry> survey = kHousingSurvey,
}) {
  final idsByName = <String, List<String>>{};
  nameById.forEach((id, name) {
    final n = _norm(name);
    if (n.isNotEmpty) idsByName.putIfAbsent(n, () => []).add(id);
  });
  final out = <String, List<HousingReport>>{};
  for (final e in survey) {
    for (final name in e.names) {
      for (final id in idsByName[_norm(name)] ?? const <String>[]) {
        out.putIfAbsent(id, () => []).add(HousingReport(
              buildingId: id,
              deposit: e.deposit,
              monthlyRent: e.monthlyRent,
              maintenanceFee: e.maintenanceFee,
              roomType: e.roomType,
              features: const [],
              reportedAt: kHousingSurveyDate,
              survey: true,
            ));
      }
    }
  }
  return out;
}

/// 학생 제보와 시세 조사를 합쳐 건물별로 요약한다.
Map<String, HousingSummary> summarizeWithSurvey(
  Map<String, List<HousingReport>> reports,
  Map<String, String> nameById, {
  List<HousingSurveyEntry> survey = kHousingSurvey,
}) {
  final all = <String, List<HousingReport>>{
    for (final e in reports.entries) e.key: [...e.value],
  };
  housingSurveyReports(nameById, survey: survey).forEach((id, rs) {
    all.putIfAbsent(id, () => []).addAll(rs);
  });
  return all.map((id, rs) => MapEntry(id, HousingSummary.from(rs)));
}

/// 아파트 전세 한 건. 금액은 만원. [names]는 그 단지의 **모든 동** —
/// 몇 동인지 모르거나 단지 시세로 보는 게 맞아서, 어느 동을 눌러도 보인다.
class HousingJeonseEntry {
  final List<String> names;
  final int deposit;

  /// "10층", "101동 13평"처럼 들은 그대로의 덧붙임. 없으면 null.
  final String? note;

  const HousingJeonseEntry(this.names, this.deposit, {this.note});
}

const _seoho = ['서호e타운 101동', '서호e타운 102동'];

/// 2026-09 직접 물어 모은 아파트 전세.
const kHousingJeonse = <HousingJeonseEntry>[
  HousingJeonseEntry(_taeam, 3000, note: '10층'),
  HousingJeonseEntry(_taeam, 3000, note: '10층 · 관리비 7~9만원'),
  HousingJeonseEntry(_taeam, 3000, note: '13평'),
  HousingJeonseEntry(_seoho, 2000, note: '101동 13평'),
];

/// 지도에 뜨는 이름이 [name]인 건물의 전세 조사. 띄어쓰기는 무시한다.
List<HousingJeonseEntry> housingJeonseFor(
  String? name, {
  List<HousingJeonseEntry> jeonse = kHousingJeonse,
}) {
  if (name == null) return const [];
  final n = _norm(name);
  return [
    for (final e in jeonse)
      if (e.names.any((x) => _norm(x) == n)) e,
  ];
}
