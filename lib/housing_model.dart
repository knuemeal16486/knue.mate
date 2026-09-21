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
  darak('다락탑연리', Color(0xFF26A69A));

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

/// 학기 중 기숙사 희망입사 비용. 출처: 학교 공지(1·2학기 다감관 기준).
///
/// ⚠️ 학기마다 바뀌는 값이다. 공지가 갱신되면 여기 숫자를 고쳐야 한다.
const List<DormCost> kDormCosts = [
  DormCost(
    name: '다감관 1인실',
    semesterHousingWon: 2387120,
    semesterMealWon: 1684200, // 2식 420식
    days: 212,
  ),
];
