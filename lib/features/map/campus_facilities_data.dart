import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// 캠퍼스 내·외부 부속시설 분류.
enum FacilityType {
  restaurant,
  cafe,
  convenience,
  bus_stop,
  pc,
  pub,
  atm,
  printer,
  laundry,
  bookstore,
  bank,
  post,
  gym,
  ev,
  parking,
  stage,
  toilet,
  department,
  observatory,
}

extension FacilityTypeExt on FacilityType {
  IconData get icon => switch (this) {
    FacilityType.printer => Icons.print_rounded,
    FacilityType.cafe => Icons.coffee_rounded,
    FacilityType.ev => Icons.ev_station_rounded,
    FacilityType.stage => Icons.theater_comedy_rounded,
    FacilityType.toilet => Icons.wc_rounded,
    FacilityType.convenience => Icons.store_rounded,
    FacilityType.parking => Icons.local_parking_rounded,
    FacilityType.atm => Icons.atm_rounded,
    FacilityType.restaurant => Icons.restaurant_rounded,
    FacilityType.department => Icons.business_center_rounded,
    FacilityType.gym => Icons.fitness_center_rounded,
    FacilityType.bank => Icons.account_balance_rounded,
    FacilityType.post => Icons.mail_rounded,
    FacilityType.bookstore => Icons.menu_book_rounded,
    FacilityType.bus_stop => Icons.directions_bus_rounded,
    FacilityType.pub => Icons.local_bar_rounded,
    FacilityType.pc => Icons.sports_esports_rounded,
    FacilityType.laundry => Icons.local_laundry_service_rounded,
    FacilityType.observatory => Icons.satellite_alt_rounded,
  };

  Color get color => switch (this) {
    FacilityType.printer => const Color(0xFF3949AB),
    FacilityType.cafe => const Color(0xFF6D4C41),
    FacilityType.ev => const Color(0xFF2E7D32),
    FacilityType.stage => const Color(0xFFE64A19),
    FacilityType.toilet => const Color(0xFF00838F),
    FacilityType.convenience => const Color(0xFFC62828),
    FacilityType.parking => const Color(0xFF455A64),
    FacilityType.atm => const Color(0xFF1565C0),
    FacilityType.restaurant => const Color(0xFFF57F17),
    FacilityType.department => const Color(0xFF6A1B9A),
    FacilityType.gym => const Color(0xFFBF360C),
    FacilityType.bank => const Color(0xFF1B5E20),
    FacilityType.post => const Color(0xFFE65100),
    FacilityType.bookstore => const Color(0xFF4A148C),
    FacilityType.bus_stop => const Color(0xFF00ACC1),
    FacilityType.pub => const Color(0xFF8E24AA),
    FacilityType.pc => const Color(0xFF1E88E5),
    FacilityType.laundry => const Color(0xFF00897B),
    FacilityType.observatory => const Color(0xFF5E35B1),
  };

  String get label => switch (this) {
    FacilityType.restaurant => '식당',
    FacilityType.cafe => '카페',
    FacilityType.convenience => '편의점',
    FacilityType.bus_stop => '정류장',
    FacilityType.pc => 'PC방',
    FacilityType.pub => '주점',
    FacilityType.atm => 'ATM',
    FacilityType.printer => '프린터',
    FacilityType.laundry => '빨래방',
    FacilityType.bookstore => '서점',
    FacilityType.bank => '은행',
    FacilityType.post => '우체국',
    FacilityType.gym => '체육관',
    FacilityType.ev => '전기차충전',
    FacilityType.parking => '주차장',
    FacilityType.stage => '공연장',
    FacilityType.toilet => '화장실',
    FacilityType.department => '과사무실',
    FacilityType.observatory => '관측소',
  };

  double get minZoom => switch (this) {
    FacilityType.restaurant ||
    FacilityType.bus_stop ||
    FacilityType.observatory ||
    FacilityType.parking => 15.5,
    FacilityType.cafe ||
    FacilityType.convenience ||
    FacilityType.atm ||
    FacilityType.stage ||
    FacilityType.bank ||
    FacilityType.post ||
    FacilityType.pub ||
    FacilityType.pc ||
    FacilityType.laundry ||
    FacilityType.bookstore => 16.0,
    FacilityType.printer || FacilityType.ev => 16.5,
    FacilityType.toilet ||
    FacilityType.gym ||
    FacilityType.department => 17.0,
  };

  String get category => switch (this) {
    FacilityType.cafe ||
    FacilityType.convenience ||
    FacilityType.restaurant ||
    FacilityType.atm ||
    FacilityType.bank ||
    FacilityType.post ||
    FacilityType.pub ||
    FacilityType.pc ||
    FacilityType.laundry ||
    FacilityType.bookstore => '편의',
    FacilityType.bus_stop || FacilityType.ev || FacilityType.parking => '이동',
    FacilityType.printer ||
    FacilityType.gym ||
    FacilityType.department ||
    FacilityType.observatory => '교육',
    FacilityType.stage || FacilityType.toilet => '시설',
  };
}

class MapFacility {
  final String name;
  final FacilityType type;
  final LatLng position;
  final String? detail;

  /// null이 아니면 개발자 모드로 추가된 위치([AdminMapFacility]의 Firestore
  /// 문서 id) — 코드에 박힌 [kFacilities]와 구분해 삭제 버튼을 보여줄 때 쓴다.
  final String? adminId;

  const MapFacility({
    required this.name,
    required this.type,
    required this.position,
    this.detail,
    this.adminId,
  });
}

final List<MapFacility> kFacilities = [
  const MapFacility(
    name: '연수원 공감 ',
    type: FacilityType.cafe,
    position: LatLng(36.613702, 127.356901),
    detail: '09:00~18:00',
  ),
  const MapFacility(
    name: '도서관 공감',
    type: FacilityType.cafe,
    position: LatLng(36.609039, 127.358218),
    detail: '08:00~20:00',
  ),
  const MapFacility(
    name: '브리드 커피',
    type: FacilityType.cafe,
    position: LatLng(36.6083883, 127.3600495),
    detail: '09:00~18:00',
  ),
  const MapFacility(
    name: 'CU 학생회관',
    type: FacilityType.convenience,
    position: LatLng(36.6084443, 127.3595452),
    detail: '24시간 무인',
  ),
  const MapFacility(
    name: 'CU 다정관',
    type: FacilityType.convenience,
    position: LatLng(36.613345, 127.359776),
    detail: '24시간 무인',
  ),
  const MapFacility(
    name: '교원대 우체국',
    type: FacilityType.post,
    position: LatLng(36.6084174, 127.3594701),
    detail: '09:00~18:00 (주말 휴무)',
  ),
  const MapFacility(
    name: '학생회관 식당',
    type: FacilityType.restaurant,
    position: LatLng(36.6082839, 127.3597920),
    detail: '11:00~14:00 / 17:00~19:00',
  ),
  const MapFacility(
    name: '교내 서점',
    type: FacilityType.bookstore,
    position: LatLng(36.6083582, 127.3595345),
    detail: '09:00~18:00 (주말 휴무)',
  ),
  const MapFacility(
    name: '기숙사 식당',
    type: FacilityType.restaurant,
    position: LatLng(36.612830, 127.360559),
    detail: '07:00~19:00',
  ),
  const MapFacility(
    name: '농협은행 교원대출장소',
    type: FacilityType.bank,
    position: LatLng(36.6084551, 127.3569837),
    detail: '09:00~16:00 (주말 휴무)',
  ),
  const MapFacility(
    name: 'CU 뉴교원대원룸점',
    type: FacilityType.convenience,
    position: LatLng(36.609641, 127.355747),
    detail: '24시간',
  ),
  const MapFacility(
    name: 'CU 한국교원대점',
    type: FacilityType.convenience,
    position: LatLng(36.6071352, 127.3536792),
    detail: '24시간',
  ),
  const MapFacility(
    name: '셀프빨래방',
    type: FacilityType.laundry,
    position: LatLng(36.6093335, 127.3556359),
    detail: '24시간 무인',
  ),
  const MapFacility(
    name: '카페 시즌',
    type: FacilityType.cafe,
    position: LatLng(36.608337, 127.355796),
  ),
  const MapFacility(
    name: '카페 MAY 49-10',
    type: FacilityType.cafe,
    position: LatLng(36.608294, 127.355404),
  ),
  const MapFacility(
    name: '카페 에브리앙',
    type: FacilityType.cafe,
    position: LatLng(36.605542, 127.353762),
  ),
  const MapFacility(
    name: '카페 아도르',
    type: FacilityType.cafe,
    position: LatLng(36.611532, 127.349267),
  ),
  const MapFacility(
    name: '카페 36.5 공감',
    type: FacilityType.cafe,
    position: LatLng(36.617870, 127.356246),
  ),
  const MapFacility(
    name: '디저트 39 한국교원대점',
    type: FacilityType.cafe,
    position: LatLng(36.617172, 127.356144),
  ),
  const MapFacility(
    name: '카페 도란',
    type: FacilityType.cafe,
    position: LatLng(36.616630, 127.356241),
  ),
  const MapFacility(
    name: '카페 에셀',
    type: FacilityType.cafe,
    position: LatLng(36.616565, 127.360463),
  ),
  const MapFacility(
    name: '카페 우즈',
    type: FacilityType.cafe,
    position: LatLng(36.612996, 127.361487),
  ),
  const MapFacility(
    name: '카페 마레',
    type: FacilityType.cafe,
    position: LatLng(36.613771, 127.360892),
  ),
  const MapFacility(
    name: '카페 더 다락',
    type: FacilityType.cafe,
    position: LatLng(36.60099, 127.36287),
  ),
  const MapFacility(
    name: '한국교원대 버스정류장',
    type: FacilityType.bus_stop,
    position: LatLng(36.6084066, 127.3584965),
  ),
  const MapFacility(
    name: '한국교원대 정문 버스정류장',
    type: FacilityType.bus_stop,
    position: LatLng(36.607025, 127.353601),
  ),
  const MapFacility(
    name: '한국교원대 후문 버스정류장',
    type: FacilityType.bus_stop,
    position: LatLng(36.617752, 127.355930),
  ),
  const MapFacility(
    name: '탑연삼거리 버스정류장 (조치원 방면)',
    type: FacilityType.bus_stop,
    position: LatLng(36.623738, 127.359626),
  ),
  const MapFacility(
    name: '탑연삼거리 버스정류장 (청주 방면)',
    type: FacilityType.bus_stop,
    position: LatLng(36.623777, 127.358091),
  ),
  const MapFacility(
    name: '지진파 관측소',
    type: FacilityType.observatory,
    position: LatLng(36.613258, 127.358067),
  ),
  const MapFacility(
    name: '청람 천문대',
    type: FacilityType.observatory,
    position: LatLng(36.606748, 127.360119),
  ),
  const MapFacility(
    name: 'B&W',
    type: FacilityType.pub,
    position: LatLng(36.614150, 127.360720),
  ),
  const MapFacility(
    name: 'BLUR',
    type: FacilityType.pub,
    position: LatLng(36.6071406, 127.3541862),
  ),
  const MapFacility(
    name: '완행열차',
    type: FacilityType.pub,
    position: LatLng(36.607760, 127.353119),
  ),
  const MapFacility(
    name: 'POW PC방',
    type: FacilityType.pc,
    position: LatLng(36.6053847, 127.3539890),
  ),
  const MapFacility(
    name: 'PLAN D',
    type: FacilityType.pub,
    position: LatLng(36.6073462, 127.3536216),
  ),
  const MapFacility(
    name: '땡금이네 실내포차',
    type: FacilityType.pub,
    position: LatLng(36.6097232, 127.3559940),
  ),
];
