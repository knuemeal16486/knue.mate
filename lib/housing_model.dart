import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 자취방 구역. 학생들이 "CU 뒤", "메이 근처"처럼 덩어리로 부르기 때문에
/// 학생회 «교원대 원룸 지도»가 나눠 놓은 구역을 그대로 따른다.
enum HousingZone {
  gateBack('정문상가 뒷편', Color(0xFFEF5350)),
  apartments('수정·서호아파트', Color(0xFF757575)),
  mayToCu('메이–CU 사이', Color(0xFF039BE5)),
  aroundCu('CU 편의점 주변', Color(0xFF43A047)),
  gyowonVilla('교원빌라', Color(0xFFAB47BC)),
  hqPath('대학본부 샛길', Color(0xFF5C6BC0)),
  dreamVilla('드림빌라·만광', Color(0xFFFB8C00)),
  dorm('기숙사', Color(0xFF00897B)),
  backGate('후문', Color(0xFFEC407A)),
  darak('다락탑연리', Color(0xFF26A69A)),

  /// 원룸이 아니라 교내 건물. 교내 건물 정보를 고칠 때 원룸 구역 대신 고른다.
  /// 원룸 구역 칩(지도 위 필터)에는 나오지 않는다.
  campus('캠퍼스 시설', Color(0xFF3F51B5));

  /// 지도 위 구역 칩처럼 "원룸 구역"만 보여줄 곳.
  static List<HousingZone> get housingZones =>
      [for (final z in values) if (z != campus) z];

  final String label;
  final Color color;
  const HousingZone(this.label, this.color);
}

/// 도로명별 건물 색.
///
/// [HousingZone]은 학생들이 부르는 덩어리 이름이라 제보가 붙은 건물에만
/// 달린다. 도로명은 **571동 전부** 갖고 있어서(VWorld 대장) 빈 곳 없이
/// 칠할 수 있다.
///
/// 월탄3길이 사실상 원룸촌 본거리다 — 원룸으로 볼 만한 건물 85동 중
/// 54동(64%)이 이 길에 있다. 초록으로 칠해 그 덩어리가 한눈에 잡히게 한다.
/// 다른 길도 칠하려면 여기 한 줄씩 넣으면 된다.
/// 개발자 모드에서 건물에 칠하는 색. 구역별로 나눠 칠할 수 있게 색상환을
/// 따라 고르게 놓았다(진한 색 옆에 옅은 색을 둬 비슷한 구역끼리 묶기 좋게).
/// 건물 추가·정보 편집·칠하기가 모두 이 목록을 쓴다.
const List<Color> kHousingPalette = [
  Color(0xFFE53935), // 레드
  Color(0xFFE91E63), // 핑크
  Color(0xFFF48FB1), // 연분홍
  Color(0xFF9C27B0), // 퍼플
  Color(0xFFB39DDB), // 라벤더
  Color(0xFF3F51B5), // 인디고
  Color(0xFF2196F3), // 블루
  Color(0xFF90CAF9), // 하늘
  Color(0xFF00BCD4), // 시안
  Color(0xFF009688), // 틸
  Color(0xFF03C75A), // 네이버 그린
  Color(0xFF8BC34A), // 연두
  Color(0xFFCDDC39), // 라임
  Color(0xFFFFEB3B), // 노랑
  Color(0xFFFFC107), // 앰버
  Color(0xFFFF9800), // 오렌지
  Color(0xFFFF5722), // 딥오렌지
  Color(0xFFBCAAA4), // 베이지
  Color(0xFF795548), // 브라운
  Color(0xFF607D8B), // 블루그레이
  Color(0xFF9E9E9E), // 그레이
  Color(0xFF424242), // 다크 차콜
  Color(0xFFFFFFFF), // 흰색
];

/// 색 견본 위 체크 표시 색. 노랑·흰색처럼 밝은 색 위에 흰 체크를 얹으면 안 보인다.
Color paletteCheckColor(Color c) =>
    c.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

const Map<String, Color> kHousingRoadColors = {
  '월탄3길': Color(0xFF7DCB8E),
};

/// 원룸 이름 후보.
///
/// ⚠️ **좌표가 없다.** 건물 모양·위치는 VWorld 실측 데이터(BaseBuilding)에서
/// 오고, 이 목록은 "그 건물이 어느 원룸인지" 이름을 붙일 때 쓰는 사전이다.
///
/// 처음에는 사진을 보고 좌표를 손으로 찍어 넣었는데, VWorld 실측과 대조해 보니
/// 원룸촌 자체가 예상한 곳에서 500m 떨어져 있었다. 추측한 좌표로 지도를 그리면
/// 학생이 엉뚱한 건물을 찾아가게 되므로, 좌표는 실측만 쓰고 이름은 사람이
/// 붙이도록 바꿨다.
class OneRoomName {
  final String id;
  final String name;

  /// 건축물 사용승인 연도. 출처: 충북 부동산정보조회 시스템.
  final int? builtYear;

  final HousingZone zone;

  /// 사진 지도의 괄호 설명(1층 상가 등).
  final String? note;

  const OneRoomName({
    required this.id,
    required this.name,
    required this.zone,
    this.builtYear,
    this.note,
  });
}

OneRoomName _n(
  String id,
  String name,
  HousingZone zone, [
  int? year,
  String? note,
]) =>
    OneRoomName(id: id, name: name, zone: zone, builtYear: year, note: note);

/// 학생회 «교원대 원룸 지도»(2020.05 수정본)에 실린 원룸 목록.
final List<OneRoomName> kOneRoomNames = [
  // 정문상가 뒷편
  _n('daehyeon-a', '대현빌라 A동', HousingZone.gateBack, 2002),
  _n('daehyeon-b', '대현빌라 B동', HousingZone.gateBack, 2002),
  _n('samsung-free', '삼성프리하우스', HousingZone.gateBack, 2008, '대현 C동'),
  _n('dungji', '둥지빌', HousingZone.gateBack, 2010),

  // 수정·서호아파트
  _n('sujeong-101ga', '수정아파트 101-가동', HousingZone.apartments, 1997),
  _n('sujeong-101na', '수정아파트 101-나동', HousingZone.apartments, 1997),
  _n('sujeong-102', '수정아파트 102동', HousingZone.apartments, 1997),
  _n('seoho-101', '서호아파트 101동', HousingZone.apartments, 2001),
  _n('seoho-102', '서호아파트 102동', HousingZone.apartments, 2001),

  // 메이–CU 편의점 사이
  _n('miraero', '미래로빌', HousingZone.mayToCu, 2018),
  _n('haeoreum', '해오름빌', HousingZone.mayToCu, 2017),
  _n('geulmaru', '글마루빌', HousingZone.mayToCu, 2017),
  _n('chaeum', '채움빌', HousingZone.mayToCu, 2017),
  _n('kkumteo', '꿈터빌', HousingZone.mayToCu, 2017),
  _n('yeonheung', '연흥빌', HousingZone.mayToCu, 2016),
  _n('daewon', '대원빌', HousingZone.mayToCu, 2018),
  _n('misoga', '미소가', HousingZone.mayToCu, 2017),
  _n('somang', '소망빌', HousingZone.mayToCu, 2018),
  _n('maple', '메이플빌', HousingZone.mayToCu, 2013),

  // CU 편의점 주변
  _n('dasom', '다솜빌', HousingZone.aroundCu, 2013),
  _n('white', '화이트빌', HousingZone.aroundCu, 2012),
  _n('saeteo', '새터빌', HousingZone.aroundCu, 2011),
  _n('pine', '파인빌', HousingZone.aroundCu, 2012),
  _n('daeseong', '대성빌', HousingZone.aroundCu, 2011),
  _n('eco', '에코빌', HousingZone.aroundCu, 2015),
  _n('thebase', '더베이스', HousingZone.aroundCu, 2015),
  _n('seungbang', '승방빌', HousingZone.aroundCu, 2011),
  _n('edu', '에듀빌', HousingZone.aroundCu, 2011),
  _n('haneulchae', '하늘채', HousingZone.aroundCu, 2015),
  _n('prime', '프라임빌', HousingZone.aroundCu, 2017),
  _n('eoullim', '어울림빌', HousingZone.aroundCu, 2011),
  _n('hanmaeum', '한마음빌', HousingZone.aroundCu, 2011),
  _n('elite', '엘리트빌', HousingZone.aroundCu, 2015),
  _n('winners', '위너스빌', HousingZone.aroundCu, 2017),
  _n('aureum', '아우름빌', HousingZone.aroundCu, 2017),
  _n('deungyongmun', '등용문', HousingZone.aroundCu, 2015),
  _n('greencastle', '그린캐슬', HousingZone.aroundCu, 2015),

  // 교원빌라
  _n('gyowon-a', '교원빌라 A동', HousingZone.gyowonVilla, 2005),
  _n('gyowon-101', '교원빌라 101동', HousingZone.gyowonVilla, 1998),
  _n('gyowon-102', '교원빌라 102동', HousingZone.gyowonVilla, 1998),
  _n('gyowon-103', '교원빌라 103동', HousingZone.gyowonVilla, 1998),
  _n('gyowon-105', '교원빌라 105동', HousingZone.gyowonVilla, 1998),
  _n('gyowon-106', '교원빌라 106동', HousingZone.gyowonVilla, 1998),
  _n('gyowon-107', '교원빌라 107동', HousingZone.gyowonVilla, 1997),
  _n('gyowon-108', '교원빌라 108동', HousingZone.gyowonVilla, 1999),
  _n('gyowon-109', '교원빌라 109동', HousingZone.gyowonVilla, 1998),
  _n('gyowon-110', '교원빌라 110동', HousingZone.gyowonVilla, 1998),
  _n('gyowon-111', '교원빌라 111동', HousingZone.gyowonVilla, 1999),
  _n('gyowon-112', '교원빌라 112동', HousingZone.gyowonVilla, 1999),
  _n('gyowon-113', '교원빌라 113동', HousingZone.gyowonVilla, 2012),
  _n('bogwang', '보광빌', HousingZone.gyowonVilla, 2013),
  _n('yeonsong', '연송빌', HousingZone.gyowonVilla, 2014),
  _n('gukbo', '국보빌', HousingZone.gyowonVilla, 2014),
  _n('bauhaus-a', '바우하우스 A동', HousingZone.gyowonVilla, 2020),
  _n('bauhaus-b', '바우하우스 B동', HousingZone.gyowonVilla, 2020),

  // 대학본부 샛길 주변
  _n('bugwang', '부광빌', HousingZone.hqPath, 2013),
  _n('chorok', '초록빌', HousingZone.hqPath, 2013),
  _n('jayeon', '자연빌', HousingZone.hqPath, 2013),
  _n('wonder', '원더빌', HousingZone.hqPath, 2013, '1층 카페 MAY'),
  _n('gaon', '가온빌', HousingZone.hqPath, 2013, '1층 카페 늘품'),
  _n('haengun', '행운빌', HousingZone.hqPath, 2016),
  _n('cheongram-a', '청람드림빌 A동', HousingZone.hqPath, 2010),
  _n('cheongram-b', '청람드림빌 B동', HousingZone.hqPath, 2010),
  _n('cheongram-c', '청람드림빌 C동', HousingZone.hqPath, 2010),
  _n('cheongram-d', '청람드림빌 D동', HousingZone.hqPath, 2010),

  // 드림빌라·만광 방향
  _n('dream-a', '드림빌라 A동', HousingZone.dreamVilla, 2001),
  _n('dream-b', '드림빌라 B동', HousingZone.dreamVilla, 2001),
  _n('dream-c', '드림빌라 C동', HousingZone.dreamVilla, 2002),
  _n('dream-d', '드림빌라 D동', HousingZone.dreamVilla, 2004),
  _n('dream-e', '드림빌라 E동', HousingZone.dreamVilla, 2004),
  _n('gyowon-haksa', '교원학사', HousingZone.dreamVilla, 2010),
  _n('seonggyungwan', '성균관빌', HousingZone.dreamVilla, 2010),
  _n('green-a', '그린빌라 A동', HousingZone.dreamVilla, 2011),
  _n('green-b', '그린빌라 B동', HousingZone.dreamVilla),
  _n('wonang', '원앙빌라', HousingZone.dreamVilla, 2001),
];

/// 이름으로 빠르게 찾기 위한 색인.
final Map<String, OneRoomName> kOneRoomNameById = {
  for (final n in kOneRoomNames) n.id: n,
};

/// 이름 비교용으로 다듬는다. 띄어쓰기·괄호 설명·끝의 "동"·"빌"을 뗀다 —
/// 개발자 모드에서 붙인 이름은 "어울림"(사전은 "어울림빌"), "청람드림빌 D"
/// (사전은 "…D동"), "가온빌 (늘품)"처럼 조금씩 다르게 적힌다.
String normalizeOneRoomName(String name) {
  var t = name.replaceAll(RegExp(r'\(.*?\)'), '').replaceAll(RegExp(r'\s+'), '');
  // 지도 데이터엔 "대현빌 A"·"둥지빌라"처럼 빌/빌라가 섞여 적혀 있다.
  t = t.replaceAll('빌라', '빌');
  if (t.length > 2 && t.endsWith('동')) t = t.substring(0, t.length - 1);
  if (t.length > 2 && t.endsWith('빌')) t = t.substring(0, t.length - 1);
  return t;
}

final Map<String, OneRoomName> _oneRoomByNormalizedName = {
  for (final n in kOneRoomNames) normalizeOneRoomName(n.name): n,
};

/// 지도 데이터(tool/mapsrc/building_names.json)와 원룸 지도가 같은 건물을
/// 다르게 부르는 경우. 번지·동 번호로 같은 건물임을 맞춰 봤다.
const Map<String, String> _kOneRoomAliases = {
  '프리하우스': '삼성프리하우스', // 월탄3길 11, 대현빌라 바로 옆
  '서호e타운 101동': '서호아파트 101동',
  '서호e타운 102동': '서호아파트 102동',
};

/// 사전 항목과 1:1로 맞출 수는 없지만 연도는 확실한 건물. 원룸 지도의
/// 수정아파트는 "101-가·101-나·102동", 지도 데이터는 "101·102·103동"으로
/// 동 번호 체계가 다르다. 다만 표의 세 동이 모두 1997년이라 연도는 같다.
const Map<String, int> _kExtraBuiltYears = {
  '태암수정아파트 101동': 1997,
  '태암수정아파트 102동': 1997,
  '태암수정아파트 103동': 1997,
};

final Map<String, String> _aliasByNormalizedName = {
  for (final e in _kOneRoomAliases.entries) normalizeOneRoomName(e.key): e.value,
};
final Map<String, int> _extraYearByNormalizedName = {
  for (final e in _kExtraBuiltYears.entries) normalizeOneRoomName(e.key): e.value,
};

/// 이름으로 원룸 사전을 찾는다. 순수 함수 — 테스트 대상.
OneRoomName? oneRoomByName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final key = normalizeOneRoomName(name);
  final direct = _oneRoomByNormalizedName[key];
  if (direct != null) return direct;
  final alias = _aliasByNormalizedName[key];
  return alias == null ? null : _oneRoomByNormalizedName[normalizeOneRoomName(alias)];
}

/// 이름으로 찾은 준공(사용승인) 연도. 출처: 충북 부동산정보조회 시스템
/// (학생회 원룸 지도 2020.05). 수정 문서에 연도를 따로 적지 않았거나 이름이
/// 지도 데이터에만 있는 건물도 연도가 뜨게 한다.
int? builtYearByName(String? name) {
  final found = oneRoomByName(name)?.builtYear;
  if (found != null || name == null) return found;
  return _extraYearByNormalizedName[normalizeOneRoomName(name)];
}

/// 기숙사 한 학기 비용. 자취 시세와 견줄 수 있게 월 단위로 환산해 둔다.
///
/// 자취는 "월세 + 관리비"로 이야기하고 식비는 따로 치므로, 비교할 때는
/// [monthlyHousing](주거비만)을 쓰는 게 맞다. [monthlyWithMeals]는 실제로
/// 한 달에 나가는 총액이 궁금할 때 같이 보여준다.
class DormCost {
  final String name;

  /// 학기 관리비(원) — 기숙사에서 "주거비"에 해당하는 금액.
  final int semesterHousingWon;

  /// 학기 식비(원).
  final int semesterMealWon;

  /// 관리비가 적용되는 일수(예: 212일).
  final int days;

  const DormCost({
    required this.name,
    required this.semesterHousingWon,
    required this.semesterMealWon,
    required this.days,
  });

  int get semesterTotalWon => semesterHousingWon + semesterMealWon;

  /// 하루치 주거비(원).
  double get dailyHousingWon => semesterHousingWon / days;

  /// 월 환산 주거비(만원). 한 달을 30.4일로 본다.
  int get monthlyHousing => (dailyHousingWon * 30.4 / 10000).round();

  /// 월 환산 식비(만원).
  int get monthlyMeal => (semesterMealWon / days * 30.4 / 10000).round();

  /// 월 환산 총액(만원, 식비 포함).
  int get monthlyWithMeals => monthlyHousing + monthlyMeal;
}

/// [kDormCosts]가 어느 학기 값인지. 다감관 카드에 그대로 뜬다.
const kDormCostTerm = '2026-2학기';

/// 학기 중 기숙사 희망입사 비용. 출처: 학교 공지(다감관, [kDormCostTerm]).
///
/// ⚠️ 학기마다 바뀌는 값이다. 공지가 갱신되면 여기 숫자와 [kDormCostTerm]을
/// 같이 고친다.
const List<DormCost> kDormCosts = [
  DormCost(
    name: '다감관 1인실',
    semesterHousingWon: 2387120,
    semesterMealWon: 1684200, // 2식 420식
    days: 212,
  ),
  DormCost(
    name: '다감관 2인실',
    semesterHousingWon: 1350000,
    semesterMealWon: 1684200,
    days: 212,
  ),
];

/// 다감관 건물(A동·B동, 합친 조각 포함)인지. 누르면 [kDormCosts]를 보여준다.
bool isDagamName(String? name) => name?.replaceAll(' ', '').startsWith('다감관') ?? false;

/// 원 → "2,387,120원".
String formatWon(int won) {
  final s = won.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b원';
}

// ── 지도 좌표계 ────────────────────────────────────────────────
// 자취방 지도의 월드 좌표는 이 원점을 기준으로 한 평면 미터다. x는 동쪽,
// y는 **남쪽**이 +다. tool/fetch_osm_roads.js·campus_traced.json과 같은
// 원점·환산값이어야 GPS 위치와 위성영상이 도로·건물과 겹친다.
const double kHousingOriginLon = 127.3544;
const double kHousingOriginLat = 36.6092;
const double _kMetersPerDegLat = 111320;
final double _kMetersPerDegLon =
    111320 * math.cos(kHousingOriginLat * math.pi / 180);

/// 경위도 → 지도 월드 좌표(미터).
Offset lonLatToHousingWorld(double lon, double lat) => Offset(
      (lon - kHousingOriginLon) * _kMetersPerDegLon,
      (kHousingOriginLat - lat) * _kMetersPerDegLat,
    );

/// 지도 월드 좌표(미터) → (경도, 위도).
(double lon, double lat) housingWorldToLonLat(Offset w) => (
      kHousingOriginLon + w.dx / _kMetersPerDegLon,
      kHousingOriginLat - w.dy / _kMetersPerDegLat,
    );

/// 도보 등시선의 기준점. 캠퍼스 거점이거나 GPS로 받은 내 위치다.
@immutable
class IsochroneCenter {
  final String label;
  final Offset position;
  const IsochroneCenter(this.label, this.position);

  IsochroneCenter.landmark(CampusLandmark l) : this(l.label, landmarkPosition(l));

  @override
  bool operator ==(Object other) =>
      other is IsochroneCenter && other.label == label && other.position == position;

  @override
  int get hashCode => Object.hash(label, position);
}

/// 개발자 모드에서 지도에 직접 찍은 거점 위치(housing_landmark.dart가 채운다).
/// 있으면 [CampusLandmark.position]의 어림값 대신 쓴다 — 도보 거리·등시선이
/// 모두 [landmarkPosition]을 거친다.
final ValueNotifier<Map<CampusLandmark, Offset>> kPlacedLandmarkPositions =
    ValueNotifier(const {});

/// 거점의 실제 위치: 찍어 둔 게 있으면 그것, 없으면 코드의 어림값.
Offset landmarkPosition(CampusLandmark l) =>
    kPlacedLandmarkPositions.value[l] ?? l.position;

/// 캠퍼스 주요 거점 위치 (단위: 미터).
enum CampusLandmark {
  mainGate('정문', Offset(-20, 205)),
  library('도서관', Offset(365, 22)),
  studentUnion('학생회관', Offset(499, 97)),
  topyeonStop('탑연삼거리 정류장', Offset(-220, 310));

  final String label;
  final Offset position;
  const CampusLandmark(this.label, this.position);
}

/// 건물 중심점과 캠퍼스 거점 사이 도보 거리(미터).
/// 실제 골목과 보행로는 직선보다 우회하므로 보행 계수(1.2)를 곱한다.
int walkingDistanceMeters(Offset buildingCenter, CampusLandmark landmark) {
  final p = landmarkPosition(landmark);
  final dx = buildingCenter.dx - p.dx;
  final dy = buildingCenter.dy - p.dy;
  final straight = math.sqrt(dx * dx + dy * dy);
  return (straight * 1.2).round();
}

/// 도보 거리(미터) → 예상 도보 소요 시간(분).
/// 평균 보행 속도를 약 67m/분(4km/h)으로 계산한다.
int walkingMinutes(int meters) => (meters / 67).ceil().clamp(1, 60);
