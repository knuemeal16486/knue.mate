import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants.dart';

// ─────────────────────────────────────────────────── 데이터 모델 ──

enum FacilityType {
  printer,
  cafe,
  ev,
  stage,
  toilet,
  convenience,
  parking,
  atm,
  restaurant,
  department,
  gym,
  bank,
  post,
  bookstore,
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
  };

  String get label => switch (this) {
    FacilityType.printer => '프린터',
    FacilityType.cafe => '카페',
    FacilityType.ev => '전기차충전',
    FacilityType.stage => '공연장',
    FacilityType.toilet => '화장실',
    FacilityType.convenience => '편의점',
    FacilityType.parking => '주차장',
    FacilityType.atm => 'ATM',
    FacilityType.restaurant => '식당',
    FacilityType.department => '과사무실',
    FacilityType.gym => '체육관',
    FacilityType.bank => '은행',
    FacilityType.post => '우체국',
    FacilityType.bookstore => '서점',
  };

  double get minZoom => switch (this) {
    FacilityType.restaurant ||
    FacilityType.department ||
    FacilityType.parking => 15.5,
    FacilityType.cafe ||
    FacilityType.convenience ||
    FacilityType.atm ||
    FacilityType.stage ||
    FacilityType.bank ||
    FacilityType.post ||
    FacilityType.bookstore => 16.0,
    FacilityType.printer || FacilityType.ev || FacilityType.gym => 16.5,
    FacilityType.toilet => 17.0,
  };

  String get category => switch (this) {
    FacilityType.printer || FacilityType.department || FacilityType.gym => '교육',
    FacilityType.cafe ||
    FacilityType.convenience ||
    FacilityType.restaurant ||
    FacilityType.atm ||
    FacilityType.bank ||
    FacilityType.post ||
    FacilityType.bookstore => '편의',
    FacilityType.ev || FacilityType.parking => '이동',
    FacilityType.stage || FacilityType.toilet => '시설',
  };
}

class MapFacility {
  final String name;
  final FacilityType type;
  final LatLng position;
  final String? detail;
  const MapFacility({
    required this.name,
    required this.type,
    required this.position,
    this.detail,
  });
}

class FloorData {
  final int floor;
  final List<String> rooms;
  const FloorData({required this.floor, required this.rooms});
}

class BuildingData {
  final String name, shortName, description;
  final LatLng position;
  final Color color;
  final List<FloorData> floors;
  const BuildingData({
    required this.name,
    required this.shortName,
    required this.description,
    required this.position,
    required this.color,
    required this.floors,
  });
}

// ─────────────────────────────────────────────────── 정적 데이터 ──

const LatLng _knueCenter = LatLng(36.6093, 127.3585);
const String _trailsKey = 'campus_trails_v2';

// ─────────────────────── 과 사무실 모델 ──

class DeptOffice {
  final String dept;
  final String college;
  final String building;
  final String room;
  final String phone;
  const DeptOffice({
    required this.dept,
    required this.college,
    required this.building,
    required this.room,
    required this.phone,
  });
}

const List<DeptOffice> kDeptOffices = [
  // 제 1대학
  DeptOffice(
    dept: '교육학과',
    college: '제1대학',
    building: '인문과학관',
    room: '337호',
    phone: '043-230-3410',
  ),
  DeptOffice(
    dept: '유아교육과',
    college: '제1대학',
    building: '종합교육관',
    room: '401호',
    phone: '043-230-3411',
  ),
  DeptOffice(
    dept: '초등교육과',
    college: '제1대학',
    building: '종합교육관',
    room: '303호',
    phone: '043-230-3417',
  ),
  DeptOffice(
    dept: '특수교육과',
    college: '제1대학',
    building: '교양학관',
    room: '216호',
    phone: '043-230-3440',
  ),
  // 제 2대학
  DeptOffice(
    dept: '국어교육과',
    college: '제2대학',
    building: '인문과학관',
    room: '223호',
    phone: '043-230-3500',
  ),
  DeptOffice(
    dept: '영어교육과',
    college: '제2대학',
    building: '인문과학관',
    room: '227-1호',
    phone: '043-230-3502',
  ),
  DeptOffice(
    dept: '독어교육과',
    college: '제2대학',
    building: '인문과학관',
    room: '330호',
    phone: '043-230-3503',
  ),
  DeptOffice(
    dept: '불어교육과',
    college: '제2대학',
    building: '인문과학관',
    room: '331호',
    phone: '043-230-3504',
  ),
  DeptOffice(
    dept: '중국어교육과',
    college: '제2대학',
    building: '인문과학관',
    room: '120-1호',
    phone: '043-230-3580',
  ),
  DeptOffice(
    dept: '윤리교육과',
    college: '제2대학',
    building: '종합교육관',
    room: '622호',
    phone: '043-230-3506',
  ),
  DeptOffice(
    dept: '일반사회교육과',
    college: '제2대학',
    building: '종합교육관',
    room: '516호',
    phone: '043-230-3507',
  ),
  DeptOffice(
    dept: '지리교육과',
    college: '제2대학',
    building: '종합교육관',
    room: '108호',
    phone: '043-230-3508',
  ),
  DeptOffice(
    dept: '역사교육과',
    college: '제2대학',
    building: '종합교육관',
    room: '415호',
    phone: '043-230-3509',
  ),
  // 제 3대학
  DeptOffice(
    dept: '수학교육과',
    college: '제3대학',
    building: '응용과학관',
    room: '406호',
    phone: '043-230-3601',
  ),
  DeptOffice(
    dept: '물리교육과',
    college: '제3대학',
    building: '자연과학관',
    room: '417호',
    phone: '043-230-3602',
  ),
  DeptOffice(
    dept: '화학교육과',
    college: '제3대학',
    building: '자연과학관',
    room: '318호',
    phone: '043-230-3604',
  ),
  DeptOffice(
    dept: '생물교육과',
    college: '제3대학',
    building: '자연과학관',
    room: '101호',
    phone: '043-230-3605',
  ),
  DeptOffice(
    dept: '지구과학교육과',
    college: '제3대학',
    building: '자연과학관',
    room: '204호',
    phone: '043-230-3606',
  ),
  DeptOffice(
    dept: '가정교육과',
    college: '제3대학',
    building: '응용과학관',
    room: '301호',
    phone: '043-230-3607',
  ),
  DeptOffice(
    dept: '환경교육과',
    college: '제3대학',
    building: '융합과학관',
    room: '407호',
    phone: '043-230-3608',
  ),
  DeptOffice(
    dept: '기술교육과',
    college: '제3대학',
    building: '융합과학관',
    room: '311호',
    phone: '043-230-3610',
  ),
  DeptOffice(
    dept: '컴퓨터교육과',
    college: '제3대학',
    building: '융합과학관',
    room: '508호',
    phone: '043-230-3611',
  ),
  // 제 4대학
  DeptOffice(
    dept: '음악교육과',
    college: '제4대학',
    building: '음악관',
    room: '202호',
    phone: '043-230-3700',
  ),
  DeptOffice(
    dept: '미술교육과',
    college: '제4대학',
    building: '미술관',
    room: '201호',
    phone: '043-230-3701',
  ),
  DeptOffice(
    dept: '체육교육과',
    college: '제4대학',
    building: '체육관',
    room: '206호',
    phone: '043-230-3702',
  ),
];

final List<BuildingData> kBuildings = [
  // ── 본관·행정 ──
  BuildingData(
    name: '대학본부',
    shortName: '본부',
    description: '행정처·총장실',
    position: const LatLng(36.6088450, 127.357247),
    color: Colors.blueGrey,
    floors: [
      FloorData(floor: 1, rooms: ['안내데스크', '행정처', '회의실']),
      FloorData(floor: 2, rooms: ['교무처', '학생처', '대외협력팀']),
      FloorData(floor: 3, rooms: ['총장실', '부총장실', '비서실']),
    ],
  ),
  BuildingData(
    name: '대학원',
    shortName: '대학원',
    description: '대학원 강의·연구',
    position: const LatLng(36.6100459, 127.3578957),
    color: Colors.indigo,
    floors: [
      FloorData(floor: 1, rooms: ['행정실', '대학원 행정팀']),
      FloorData(floor: 2, rooms: ['대학원 강의실', '연구실']),
      FloorData(floor: 3, rooms: ['대학원 강의실', '세미나실']),
    ],
  ),
  BuildingData(
    name: '교수회관',
    shortName: '교수관',
    description: '교수 휴게·회의 공간',
    position: const LatLng(36.6106240, 127.3586735),
    color: Colors.brown,
    floors: [
      FloorData(floor: 1, rooms: ['라운지', '회의실']),
      FloorData(floor: 2, rooms: ['교수 연구실', '세미나실']),
    ],
  ),
  BuildingData(
    name: '관리동',
    shortName: '관리동',
    description: '시설관리',
    position: const LatLng(36.6130770, 127.360681),
    color: Colors.grey,
    floors: [
      FloorData(floor: 1, rooms: ['시설관리팀', '보안실']),
    ],
  ),
  BuildingData(
    name: '복지관',
    shortName: '복지관',
    description: '학생 복지 시설',
    position: const LatLng(36.6131940, 127.359020),
    color: Colors.pink,
    floors: [
      FloorData(floor: 1, rooms: ['복지행정실', '상담실']),
      FloorData(floor: 2, rooms: ['휴게실', '동아리실']),
    ],
  ),

  // ── 교육관 ──
  BuildingData(
    name: '다정관',
    shortName: '다정관',
    description: '교육대학원·행정학부',
    position: const LatLng(36.6134070, 127.359612),
    color: Colors.blue,
    floors: [
      FloorData(floor: 1, rooms: ['행정실', '강의실 101~104', '화장실']),
      FloorData(floor: 2, rooms: ['강의실 201~206', '교수연구실', '복사실 🖨️']),
      FloorData(floor: 3, rooms: ['강의실 301~308', '세미나실']),
      FloorData(floor: 4, rooms: ['강의실 401~405', '대학원연구실']),
    ],
  ),
  BuildingData(
    name: '다감관',
    shortName: '다감관',
    description: '초등교육·유아교육과',
    position: const LatLng(36.6140590, 127.360068),
    color: Colors.purple,
    floors: [
      FloorData(floor: 1, rooms: ['행정실', '실습실']),
      FloorData(floor: 2, rooms: ['강의실 201~205', '연구실']),
      FloorData(floor: 3, rooms: ['강의실 301~304']),
    ],
  ),
  BuildingData(
    name: '종합교육관',
    shortName: '종합관',
    description: '대형 강의실·공용 시설',
    position: const LatLng(36.6107112, 127.3609668),
    color: Colors.teal,
    floors: [
      FloorData(floor: 1, rooms: ['대형강의실 101', '편의점 🏪', '복사실 🖨️']),
      FloorData(floor: 2, rooms: ['중강의실 201~203']),
      FloorData(floor: 3, rooms: ['소강의실 301~310', '자율학습실']),
      FloorData(floor: 4, rooms: ['컴퓨터실', '멀티미디어실']),
      FloorData(floor: 5, rooms: ['강의실 501~505']),
    ],
  ),
  BuildingData(
    name: '인문과학관',
    shortName: '인문관',
    description: '인문 계열 학과',
    position: const LatLng(36.6105993, 127.3598135),
    color: Colors.orange,
    floors: [
      FloorData(floor: 1, rooms: ['행정실', '강의실 101~103']),
      FloorData(floor: 2, rooms: ['국어교육과', '강의실 201~204']),
      FloorData(floor: 3, rooms: ['영어교육과', '강의실 301~305']),
      FloorData(floor: 4, rooms: ['역사교육과', '강의실 401~403']),
    ],
  ),
  BuildingData(
    name: '교양학관',
    shortName: '교양관',
    description: '교양 강의',
    position: const LatLng(36.6095798, 127.3607777),
    color: Colors.amber,
    floors: [
      FloorData(floor: 1, rooms: ['강의실 101~104']),
      FloorData(floor: 2, rooms: ['강의실 201~205']),
      FloorData(floor: 3, rooms: ['강의실 301~303', '세미나실']),
    ],
  ),
  BuildingData(
    name: '호연관',
    shortName: '호연관',
    description: '강의실·연구실',
    position: const LatLng(36.6095940, 127.358824),
    color: Colors.brown,
    floors: [
      FloorData(floor: 1, rooms: ['강의실 101~105']),
      FloorData(floor: 2, rooms: ['강의실 201~206', '교수연구실']),
      FloorData(floor: 3, rooms: ['세미나실', '복사실 🖨️']),
    ],
  ),
  BuildingData(
    name: '교육연구관',
    shortName: '교연관',
    description: '교육 연구·실험',
    position: const LatLng(36.6109030, 127.357467),
    color: Colors.cyan,
    floors: [
      FloorData(floor: 1, rooms: ['연구실', '실험실']),
      FloorData(floor: 2, rooms: ['연구실', '대학원 강의실']),
      FloorData(floor: 3, rooms: ['연구실', '세미나실']),
    ],
  ),

  // ── 과학관 ──
  BuildingData(
    name: '자연과학관',
    shortName: '자연관',
    description: '자연 계열·실험실',
    position: const LatLng(36.6086658, 127.3616172),
    color: Colors.green,
    floors: [
      FloorData(floor: 1, rooms: ['행정실', '일반화학실험실']),
      FloorData(floor: 2, rooms: ['물리실험실', '화학교육과 강의실']),
      FloorData(floor: 3, rooms: ['생물실험실', '지구과학실험실']),
      FloorData(floor: 4, rooms: ['물리교육과 연구실', '강의실 401~404', '복사실 🖨️']),
    ],
  ),
  BuildingData(
    name: '융합과학관',
    shortName: '융합관',
    description: '융합 교육',
    position: const LatLng(36.6093890, 127.361463),
    color: Colors.lightBlue,
    floors: [
      FloorData(floor: 1, rooms: ['강의실 101~103']),
      FloorData(floor: 2, rooms: ['실험실', '연구실']),
      FloorData(floor: 3, rooms: ['대학원 강의실']),
    ],
  ),
  BuildingData(
    name: '응용과학관',
    shortName: '응과관',
    description: '응용과학 실험·연구',
    position: const LatLng(36.6082061, 127.3621926),
    color: Colors.lightGreen,
    floors: [
      FloorData(floor: 1, rooms: ['실험실', '행정실']),
      FloorData(floor: 2, rooms: ['연구실', '강의실']),
      FloorData(floor: 3, rooms: ['대학원 연구실']),
    ],
  ),
  BuildingData(
    name: '체육관',
    shortName: '체육관',
    description: '실내 체육 시설',
    position: const LatLng(36.6102322, 127.3624675),
    color: Colors.deepOrange,
    floors: [
      FloorData(floor: 1, rooms: ['체육관 메인홀', '탈의실', '체력단련실 💪']),
      FloorData(floor: 2, rooms: ['관람석', '보조체육관']),
    ],
  ),

  // ── 예체능 ──
  BuildingData(
    name: '음악관',
    shortName: '음악관',
    description: '음악교육과',
    position: const LatLng(36.6075107, 127.3614496),
    color: const Color(0xFF7B1FA2),
    floors: [
      FloorData(floor: 1, rooms: ['행정실', '강의실', '피아노 연습실 🎹']),
      FloorData(floor: 2, rooms: ['강의실', '합창실', '녹음실']),
      FloorData(floor: 3, rooms: ['개인 연습실', '앙상블실']),
    ],
  ),
  BuildingData(
    name: '미술관',
    shortName: '미술관',
    description: '미술교육과',
    position: const LatLng(36.6079338, 127.3604786),
    color: const Color(0xFFE64A19),
    floors: [
      FloorData(floor: 1, rooms: ['전시실', '행정실']),
      FloorData(floor: 2, rooms: ['회화실', '조소실']),
      FloorData(floor: 3, rooms: ['디자인실', '공예실']),
    ],
  ),

  // ── 도서관·문화 ──
  BuildingData(
    name: '미래도서관',
    shortName: '도서관',
    description: '도서관·열람실·미디어센터',
    position: const LatLng(36.6090868, 127.3585314),
    color: Colors.deepPurple,
    floors: [
      FloorData(floor: 1, rooms: ['대출반납', '일반자료실', '카페 ☕']),
      FloorData(floor: 2, rooms: ['참고자료실', '전자자료실', '복사실 🖨️']),
      FloorData(floor: 3, rooms: ['제1열람실', '제2열람실', '스터디룸']),
      FloorData(floor: 4, rooms: ['제3열람실', '그룹학습실']),
    ],
  ),
  BuildingData(
    name: '교원문화관',
    shortName: '문화관',
    description: '공연장·문화 공간',
    position: const LatLng(36.6078498, 127.3586534),
    color: Colors.red,
    floors: [
      FloorData(floor: 1, rooms: ['로비', '티켓박스']),
      FloorData(floor: 2, rooms: ['대공연장 🎭 (700석)']),
      FloorData(floor: 3, rooms: ['소공연장 (100석)', '연습실']),
    ],
  ),
  BuildingData(
    name: '교육박물관',
    shortName: '박물관',
    description: '교육 역사 전시',
    position: const LatLng(36.6073352, 127.3572828),
    color: Colors.brown,
    floors: [
      FloorData(floor: 1, rooms: ['상설전시실', '안내데스크']),
      FloorData(floor: 2, rooms: ['기획전시실', '수장고']),
    ],
  ),

  // ── 학생 생활 ──
  BuildingData(
    name: '학생회관',
    shortName: '학생관',
    description: '학생식당·편의시설',
    position: const LatLng(36.6086039, 127.3598275),
    color: Colors.orange,
    floors: [
      FloorData(floor: 1, rooms: ['학생식당 🍚', '편의점 🏪', 'ATM']),
      FloorData(floor: 2, rooms: ['카페 ☕', '동아리실']),
      FloorData(floor: 3, rooms: ['대강당']),
    ],
  ),
  BuildingData(
    name: '제2학생회관',
    shortName: '2학생관',
    description: '부속 학생 시설',
    position: const LatLng(36.6081765, 127.3595023),
    color: Colors.amber,
    floors: [
      FloorData(floor: 1, rooms: ['학생식당', '매점']),
      FloorData(floor: 2, rooms: ['동아리실', '휴게실']),
    ],
  ),

  // ── 연수원 ──
  BuildingData(
    name: '함덕당',
    shortName: '함덕당',
    description: '교원 연수 강의동',
    position: const LatLng(36.6119620, 127.357349),
    color: Colors.teal,
    floors: [
      FloorData(floor: 1, rooms: ['강의실 A·B']),
      FloorData(floor: 2, rooms: ['강의실 C·D', '토론실']),
    ],
  ),
  BuildingData(
    name: '교원연수관',
    shortName: '연수관',
    description: '교원 연수 숙박',
    position: const LatLng(36.6126140, 127.357145),
    color: Colors.blueGrey,
    floors: [
      FloorData(floor: 1, rooms: ['접수·로비', '식당']),
      FloorData(floor: 2, rooms: ['숙박실']),
      FloorData(floor: 3, rooms: ['숙박실']),
    ],
  ),
  BuildingData(
    name: '연수원 문화관',
    shortName: '연수원문화관',
    description: '연수원 문화·집회 시설',
    position: const LatLng(36.6136010, 127.355852),
    color: Colors.deepPurple,
    floors: [
      FloorData(floor: 1, rooms: ['대강당', '로비']),
      FloorData(floor: 2, rooms: ['소강당', '전시실']),
    ],
  ),
  BuildingData(
    name: '국제연수관',
    shortName: '국제관',
    description: '국제 연수·교류',
    position: const LatLng(36.6137910, 127.356961),
    color: Colors.blue,
    floors: [
      FloorData(floor: 1, rooms: ['로비', '세미나실']),
      FloorData(floor: 2, rooms: ['강의실', '숙박시설']),
      FloorData(floor: 3, rooms: ['숙박시설', '루프탑']),
    ],
  ),
  BuildingData(
    name: '함인당',
    shortName: '함인당',
    description: '대형 강의·집회 시설',
    position: const LatLng(36.6153606, 127.3555380),
    color: Colors.indigo,
    floors: [
      FloorData(floor: 1, rooms: ['대강당 (1,000석)', '로비']),
      FloorData(floor: 2, rooms: ['관람석 2층']),
    ],
  ),

  // ── 부속 기관 ──
  BuildingData(
    name: '부설고',
    shortName: '부설고',
    description: '부속 고등학교',
    position: const LatLng(36.6127180, 127.356082),
    color: Colors.green,
    floors: [
      FloorData(floor: 1, rooms: ['행정실', '교무실']),
      FloorData(floor: 2, rooms: ['강의실']),
      FloorData(floor: 3, rooms: ['강의실', '도서관']),
    ],
  ),
  BuildingData(
    name: '부설유치원',
    shortName: '유치원',
    description: '부속 유치원',
    position: const LatLng(36.6059044, 127.3573552),
    color: Colors.pink,
    floors: [
      FloorData(floor: 1, rooms: ['교실', '놀이실', '원장실']),
    ],
  ),
  BuildingData(
    name: '황새생태연구원',
    shortName: '황새원',
    description: '황새 생태 보전 연구',
    position: const LatLng(36.6049560, 127.358783),
    color: Colors.lightGreen,
    floors: [
      FloorData(floor: 1, rooms: ['연구실', '전시실', '황새 사육장 🐦']),
    ],
  ),
  BuildingData(
    name: '학군단',
    shortName: '학군단',
    description: 'ROTC 학군단',
    position: const LatLng(36.6061490, 127.360594),
    color: Colors.green,
    floors: [
      FloorData(floor: 1, rooms: ['행정실', '훈련장']),
    ],
  ),
  BuildingData(
    name: '교수아파트',
    shortName: '교수APT',
    description: '교원 주거 시설',
    position: const LatLng(36.6122030, 127.352673),
    color: Colors.blueGrey,
    floors: [
      FloorData(floor: 1, rooms: ['공동현관', '관리실']),
    ],
  ),
];

final List<MapFacility> kFacilities = [
  // 사용자 제공 실제 좌표
  const MapFacility(
    name: '카페 공감 2',
    type: FacilityType.cafe,
    position: LatLng(36.613702, 127.356901),
    detail: '09:00~18:00',
  ),
  const MapFacility(
    name: '카페 공감 3',
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
    detail: '24시간',
  ),
  const MapFacility(
    name: 'CU 다정관',
    type: FacilityType.convenience,
    position: LatLng(36.613345, 127.359776),
    detail: '08:00~22:00',
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
];
// ─────────────────────────────────────────────────── 메인 위젯 ──

class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key});
  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final TabController _tabController;

  final Set<FacilityType> _activeFilters = {
    FacilityType.cafe,
    FacilityType.restaurant,
    FacilityType.convenience,
    FacilityType.atm,
    FacilityType.bank,
    FacilityType.post,
    FacilityType.bookstore,
  };

  bool _trailMode = false;
  bool _showBuildings = true;
  bool _searchOpen = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final List<LatLng> _trailPoints = [];
  List<List<LatLng>> _savedTrails = [];
  int? _selectedTrailIdx;
  List<String> _trailNames = [];

  // 건물/시설 순서 상태 (null이면 기본 순서)
  late List<int> _buildingOrder;
  late List<int> _facilityOrder;

  // 숨김 목록
  final Set<int> _hiddenBuildingIdx = {};
  final Set<int> _hiddenFacilityIdx = {};

  // 날씨
  String? _weatherTemp;
  String? _weatherIcon;
  double _currentZoom = 16.0;

  // 위치 관련
  Position? _userPosition;
  StreamSubscription<Position>? _locSub;
  AnimationController? _zoomAnim;
  bool _locationPermGranted = false; // ignore: unused_field

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _tabController = TabController(length: 4, vsync: this);
    _buildingOrder = List.generate(kBuildings.length, (i) => i);
    _facilityOrder = List.generate(kFacilities.length, (i) => i);
    _loadTrails();
    _startLocationTracking();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=36.6093&longitude=127.3585&current_weather=true&timezone=Asia%2FSeoul',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final j = json.decode(res.body) as Map;
        final cw = j['current_weather'] as Map;
        final temp = (cw['temperature'] as num).round();
        final wcode = cw['weathercode'] as int;
        if (!mounted) return;
        setState(() {
          _weatherTemp = '${temp}°';
          _weatherIcon = _weatherCodeToEmoji(wcode);
        });
      }
    } catch (_) {}
  }

  String _weatherCodeToEmoji(int code) {
    if (code == 0) return '☀️';
    if (code <= 3) return '🌤️';
    if (code <= 49) return '🌫️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '❄️';
    if (code <= 82) return '🌦️';
    if (code <= 99) return '⛈️';
    return '🌡️';
  }

  Future<void> _startLocationTracking() async {
    try {
      var status = await Geolocator.checkPermission();
      if (status == LocationPermission.denied) {
        status = await Geolocator.requestPermission();
      }
      if (status == LocationPermission.deniedForever) return;
      if (!mounted) return;
      setState(() => _locationPermGranted = true);
      _locSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((pos) {
            if (mounted) setState(() => _userPosition = pos);
          });
    } catch (_) {}
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _zoomAnim?.dispose();
    _mapController.dispose();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // 정된 줌 애니메이션
  void _animatedZoom(double target) {
    final begin = _currentZoom;
    final end = target.clamp(14.0, 19.0);
    _zoomAnim?.dispose();
    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    final anim = CurvedAnimation(
      parent: _zoomAnim!,
      curve: Curves.easeOutCubic,
    );
    anim.addListener(() {
      final z = begin + (end - begin) * anim.value;
      _mapController.move(_mapController.camera.center, z);
    });
    _zoomAnim!.forward();
  }

  void _animatedMove(LatLng target, double zoom) {
    final latB = _mapController.camera.center.latitude;
    final lngB = _mapController.camera.center.longitude;
    final zoomB = _currentZoom;
    _zoomAnim?.dispose();
    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    final anim = CurvedAnimation(
      parent: _zoomAnim!,
      curve: Curves.easeOutCubic,
    );
    anim.addListener(() {
      final t = anim.value;
      _mapController.move(
        LatLng(
          latB + (target.latitude - latB) * t,
          lngB + (target.longitude - lngB) * t,
        ),
        zoomB + (zoom - zoomB) * t,
      );
    });
    _zoomAnim!.forward();
  }

  // ─── 산책로 영구 저장/불러오기 ───

  Future<void> _loadTrails() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_trailsKey) ?? [];
    final names = prefs.getStringList('${_trailsKey}_names') ?? [];
    if (!mounted) return;
    setState(() {
      _savedTrails = data.map((item) {
        final pts = json.decode(item) as List;
        return pts
            .map<LatLng>((p) => LatLng(p[0] as double, p[1] as double))
            .toList();
      }).toList();
      _trailNames = List.generate(
        _savedTrails.length,
        (i) => i < names.length ? names[i] : '산책로 ${i + 1}',
      );
    });
  }

  Future<void> _persistTrails() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _savedTrails
        .map(
          (trail) =>
              json.encode(trail.map((p) => [p.latitude, p.longitude]).toList()),
        )
        .toList();
    await prefs.setStringList(_trailsKey, data);
    await prefs.setStringList('${_trailsKey}_names', _trailNames);
  }

  Future<void> _deleteTrail(int idx) async {
    setState(() => _savedTrails.removeAt(idx));
    await _persistTrails();
  }

  void _saveTrail() {
    if (_trailPoints.length < 2) return;
    setState(() {
      _savedTrails.add(List.from(_trailPoints));
      _trailPoints.clear();
      _trailMode = false;
    });
    _persistTrails();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '🥾 산책로가 저장되었습니다!',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _shareTrail(int idx, String name, List<LatLng> points) {
    final sb = StringBuffer();
    sb.writeln('📍 산책로: $name');
    sb.writeln('경유지 ${points.length}개');
    sb.writeln();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      sb.writeln(
        '${i + 1}. ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
      );
    }
    sb.writeln();
    sb.writeln('── 한국교원대학교 캠퍼스맵 앱에서 공유 ──');
    SharePlus.instance.share(
      ShareParams(text: sb.toString(), subject: '산책로 공유: $name'),
    );
  }

  // ─── 빌드 ───

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, primary, _) => Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF0D0D0D)
            : const Color(0xFFF4F6FB),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(116),
          child: _buildTopBar(primary, isDark),
        ),
        body: Stack(
          children: [
            TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              controller: _tabController,
              children: [
                _buildMapTab(primary, isDark),
                _buildBuildingTab(primary, isDark),
                _buildTrailTab(primary, isDark),
                _buildDeptOfficeTab(isDark),
              ],
            ),
            if (_searchOpen) _buildSearchOverlay(primary, isDark),
          ],
        ),
      ),
    );
  }

  // ─── iOS 스타일 탑바 ───

  Widget _buildTopBar(Color primary, bool isDark) {
    return ClipRect(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, Color.lerp(primary, Colors.black, 0.18)!],
          ),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                child: Row(
                  children: [
                    _TopBarBtn(
                      icon: Icons.arrow_back_ios_new_rounded,
                      active: false,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const Text(
                      '캠퍼스맵',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const Spacer(),
                    _TopBarBtn(
                      icon: _searchOpen
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      active: _searchOpen,
                      onTap: () => setState(() {
                        _searchOpen = !_searchOpen;
                        if (!_searchOpen) {
                          _searchQuery = '';
                          _searchCtrl.clear();
                        }
                      }),
                    ),
                    _TopBarBtn(
                      icon: _showBuildings
                          ? Icons.location_city_rounded
                          : Icons.location_city_outlined,
                      active: _showBuildings,
                      onTap: () =>
                          setState(() => _showBuildings = !_showBuildings),
                    ),
                    _TopBarBtn(
                      icon: _trailMode
                          ? Icons.edit_off_rounded
                          : Icons.route_rounded,
                      active: _trailMode,
                      activeColor: Colors.amber,
                      onTap: () => setState(() {
                        _trailMode = !_trailMode;
                        if (!_trailMode) _trailPoints.clear();
                      }),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicator: UnderlineTabIndicator(
                  borderSide: const BorderSide(width: 2.5, color: Colors.white),
                  borderRadius: BorderRadius.circular(2),
                  insets: const EdgeInsets.symmetric(horizontal: 30),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withValues(alpha: 0.45),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
                tabAlignment: TabAlignment.start,
                isScrollable: true,
                padding: const EdgeInsets.only(left: 8),
                tabs: const [
                  Tab(text: '지도', height: 34),
                  Tab(text: '건물', height: 34),
                  Tab(text: '산책로', height: 34),
                  Tab(text: '과 사무실', height: 34),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 검색 오버레이 ───

  Widget _buildSearchOverlay(Color primary, bool isDark) {
    final query = _searchQuery.trim();
    final allItems = [
      ...kBuildings.map(
        (b) => _SearchItem(
          name: b.name,
          sub: b.description,
          icon: Icons.business,
          color: b.color,
          onTap: () {
            _searchCtrl.clear();
            setState(() {
              _searchOpen = false;
              _searchQuery = '';
            });
            _tabController.animateTo(0);
            Future.delayed(
              const Duration(milliseconds: 200),
              () => _mapController.move(b.position, 18.0),
            );
            _showBuildingDetail(b);
          },
        ),
      ),
      ...kFacilities.map(
        (f) => _SearchItem(
          name: f.name,
          sub: f.detail ?? f.type.label,
          icon: f.type.icon,
          color: f.type.color,
          onTap: () {
            _searchCtrl.clear();
            setState(() {
              _searchOpen = false;
              _searchQuery = '';
            });
            _tabController.animateTo(0);
            Future.delayed(
              const Duration(milliseconds: 200),
              () => _mapController.move(f.position, 18.5),
            );
            _showFacilityDetail(f);
          },
        ),
      ),
    ];
    final results = query.isEmpty
        ? <_SearchItem>[]
        : allItems
              .where((i) => i.name.contains(query) || i.sub.contains(query))
              .toList();

    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Column(
        children: [
          // 검색창
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: primary),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: '건물, 카페, 식당 등 검색...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.bold,
                      ),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
              ],
            ),
          ),
          // 결과 목록
          if (results.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: results.length > 8 ? 8 : results.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                  itemBuilder: (_, i) {
                    final item = results[i];
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(item.icon, color: item.color, size: 18),
                      ),
                      title: Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        item.sub,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      onTap: item.onTap,
                    );
                  },
                ),
              ),
            )
          else if (query.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '검색 결과가 없습니다',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          // 빈 공간 클릭 시 닫기
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _searchOpen = false;
                  _searchQuery = '';
                  _searchCtrl.clear();
                });
              },
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 지도 탭 ───

  Widget _buildMapTab(Color primary, bool isDark) {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _buildDesktopFallback(primary, isDark);
    }
    final orderedFacilities = _facilityOrder
        .where((i) => !_hiddenFacilityIdx.contains(i))
        .map((i) => kFacilities[i])
        .toList();
    final filtered = orderedFacilities
        .where(
          (f) =>
              _activeFilters.contains(f.type) && _currentZoom >= f.type.minZoom,
        )
        .toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _knueCenter,
            initialZoom: _currentZoom,
            minZoom: 14.0,
            maxZoom: 19.0,
            onTap: _trailMode
                ? (tap, pt) => setState(() => _trailPoints.add(pt))
                : null,
            onMapEvent: (e) {
              if (e is MapEventMove)
                setState(() => _currentZoom = e.camera.zoom);
            },
          ),
          children: [
            TileLayer(
              // Thunderforest CycleMap: 녹지·건물·도로 색 구분 선명
              // ※ 래스터 타일 특성상 서버에 구워진 텍스트는 제거 불가
              urlTemplate: isDark
                  ? 'https://{s}.tile.thunderforest.com/transport-dark/{z}/{x}/{y}.png'
                        '?apikey=${dotenv.get('THUNDERFOREST_KEY', fallback: '')}'
                  : 'https://{s}.tile.thunderforest.com/cycle/{z}/{x}/{y}.png'
                        '?apikey=${dotenv.get('THUNDERFOREST_KEY', fallback: '')}',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.knue.knuemate',
            ),
            // 저장된 산책로
            ..._savedTrails.asMap().entries.map(
              (e) => PolylineLayer(
                polylines: [
                  Polyline(
                    points: e.value,
                    strokeWidth: 4,
                    color: Colors.primaries[e.key % Colors.primaries.length]
                        .withValues(alpha: 0.85),
                  ),
                ],
              ),
            ),
            // 현재 그리는 산책로
            if (_trailPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _trailPoints,
                    strokeWidth: 4,
                    color: Colors.yellowAccent.withValues(alpha: 0.9),
                  ),
                ],
              ),
            // 웨이포인트
            if (_trailMode && _trailPoints.isNotEmpty)
              MarkerLayer(
                markers: _trailPoints
                    .asMap()
                    .entries
                    .map(
                      (e) => Marker(
                        point: e.value,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: e.key == 0 ? Colors.green : Colors.yellow,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            // 건물 마커 (줌 15.5 이상, 토글 켜진 경우)
            if (_showBuildings && _currentZoom >= 15.5)
              MarkerLayer(
                markers: kBuildings.map((b) {
                  final large = _currentZoom >= 17;
                  return Marker(
                    point: b.position,
                    width: large ? 100.0 : 74.0,
                    height: large ? 42.0 : 30.0,
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      onTap: () => _showBuildingDetail(b),
                      child: _MapLabel(
                        text: b.name, // 전체 이름 표시
                        color: b.color,
                        large: large,
                      ),
                    ),
                  );
                }).toList(),
              ),
            // 시설 마커
            if (filtered.isNotEmpty)
              MarkerLayer(
                markers: filtered
                    .map(
                      (f) => Marker(
                        point: f.position,
                        width: 34,
                        height: 34,
                        child: GestureDetector(
                          onTap: () => _showFacilityDetail(f),
                          child: _FacilityPin(type: f.type),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),

        // 날씨 위젯 (좌하단)
        if (_weatherTemp != null)
          Positioned(
            left: 12,
            bottom: _trailMode ? 130 : 24,
            child: GestureDetector(
              onTap: _fetchWeather,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1C1E).withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: isDark
                        ? Colors.white12
                        : Colors.black.withValues(alpha: 0.07),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_weatherIcon!, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 5),
                    Text(
                      _weatherTemp!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 필터 바
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: _buildFilterBar(isDark),
        ),

        // 줌 컨트롤
        Positioned(
          right: 12,
          bottom: _trailMode ? 130 : 24,
          child: _buildZoomControls(primary),
        ),

        // 산책로 패널
        if (_trailMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildTrailPanel(isDark, primary),
          ),
      ],
    );
  }

  // ─── 필터 바 (카테고리) ───

  Widget _buildFilterBar(bool isDark) {
    final categories = {
      '교육': Colors.indigo,
      '편의': Colors.orange,
      '이동': Colors.green,
      '시설': Colors.deepOrange,
    };
    final all = FacilityType.values
        .where((t) => t != FacilityType.toilet)
        .toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // 시설 순서 편집 버튼
          GestureDetector(
            onTap: () => _showFacilityReorderSheet(isDark),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey.shade900.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: isDark
                      ? Colors.white12
                      : Colors.black.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '순서',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 전체 토글
          _FilterChip(
            label: '전체',
            icon: Icons.layers,
            active: _activeFilters.length == all.length,
            color: Colors.blueGrey,
            isDark: isDark,
            onTap: () => setState(() {
              if (_activeFilters.length == all.length)
                _activeFilters.clear();
              else
                _activeFilters.addAll(all);
            }),
          ),
          const SizedBox(width: 6),
          // 카테고리별
          ...categories.entries.expand((cat) {
            final types = all.where((t) => t.category == cat.key).toList();
            final allOn = types.every(_activeFilters.contains);
            return [
              _FilterChip(
                label: cat.key,
                icon: Icons.folder_rounded,
                active: allOn,
                color: cat.value,
                isDark: isDark,
                onTap: () => setState(
                  () => allOn
                      ? types.forEach(_activeFilters.remove)
                      : _activeFilters.addAll(types),
                ),
              ),
              const SizedBox(width: 4),
            ];
          }),
          const SizedBox(width: 4),
          // 개별 타입
          ...all.map(
            (t) => Row(
              children: [
                _FilterChip(
                  label: t.label,
                  icon: t.icon,
                  active: _activeFilters.contains(t),
                  color: t.color,
                  isDark: isDark,
                  small: true,
                  onTap: () => setState(
                    () => _activeFilters.contains(t)
                        ? _activeFilters.remove(t)
                        : _activeFilters.add(t),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFacilityReorderSheet(bool isDark) {
    final primary = themeColor.value;
    final tempOrder = List<int>.from(_facilityOrder);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '시설 마커 순서 편집',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setLocal(
                          () => tempOrder.setAll(
                            0,
                            List.generate(kFacilities.length, (i) => i),
                          ),
                        );
                      },
                      child: Text(
                        '초기화',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _facilityOrder = List.from(tempOrder));
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        '완료',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: tempOrder.length,
                  onReorder: (o, n) {
                    setLocal(() {
                      if (n > o) n--;
                      final item = tempOrder.removeAt(o);
                      tempOrder.insert(n, item);
                    });
                  },
                  itemBuilder: (_, i) {
                    final f = kFacilities[tempOrder[i]];
                    return ListTile(
                      key: ValueKey(tempOrder[i]),
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: f.type.color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(f.type.icon, color: Colors.white, size: 17),
                      ),
                      title: Text(
                        f.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        f.type.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: f.type.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Icon(
                        Icons.drag_handle_rounded,
                        color: isDark ? Colors.white38 : Colors.black26,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 줌 컨트롤 ───

  Widget _buildZoomControls(Color primary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.92);
    final shadow = BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
      blurRadius: 14,
      offset: const Offset(0, 4),
    );
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [shadow],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          _PillZoomBtn(
            icon: Icons.add_rounded,
            onTap: () => _animatedZoom(_currentZoom + 1),
            isDark: isDark,
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
          _PillZoomBtn(
            icon: Icons.remove_rounded,
            onTap: () => _animatedZoom(_currentZoom - 1),
            isDark: isDark,
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
          _PillZoomBtn(
            icon: Icons.my_location_rounded,
            color: _userPosition != null ? Colors.blue : null,
            onTap: () {
              if (_userPosition != null)
                _animatedMove(
                  LatLng(_userPosition!.latitude, _userPosition!.longitude),
                  17.5,
                );
              else
                _animatedMove(_knueCenter, 16.5);
            },
            isDark: isDark,
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
          _PillZoomBtn(
            icon: Icons.school_rounded,
            onTap: () => _animatedMove(_knueCenter, 16.0),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  // ─── 산책로 패널 ───

  Widget _buildTrailPanel(bool isDark, Color primary) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1C1C1E).withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.94),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.route, color: Colors.yellowAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  '산책로 그리기 모드',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_trailPoints.length}개 지점',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '지도를 탭하여 경로를 추가하세요',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _trailPoints.isNotEmpty
                        ? () => setState(() => _trailPoints.removeLast())
                        : null,
                    icon: const Icon(Icons.undo, size: 15),
                    label: const Text(
                      '되돌리기',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _trailPoints.length >= 2 ? _saveTrail : null,
                    icon: const Icon(Icons.save, size: 15),
                    label: const Text(
                      '저장',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ), // Container
    ), // BackdropFilter
  );

  // ─── 건물 안내 탭 ───

  Widget _buildBuildingTab(Color primary, bool isDark) {
    final orderedBuildings = _buildingOrder
        .map((i) => (i, kBuildings[i]))
        .toList();
    final visibleBuildings = orderedBuildings
        .where((e) => !_hiddenBuildingIdx.contains(e.$1))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                '건물 목록',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              if (_hiddenBuildingIdx.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _hiddenBuildingIdx.clear()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '숨김 ${_hiddenBuildingIdx.length}개 해제',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showReorderSheet(isDark, primary),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.swap_vert_rounded, size: 14, color: primary),
                      const SizedBox(width: 4),
                      Text(
                        '순서 편집',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            itemCount: visibleBuildings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final (idx, b) = visibleBuildings[i];
              return Dismissible(
                key: ValueKey(idx),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility_off_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '숨기기',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                confirmDismiss: (_) async {
                  setState(() => _hiddenBuildingIdx.add(idx));
                  return false;
                },
                child: _BuildingCard(
                  building: b,
                  isDark: isDark,
                  onTap: () {
                    _tabController.animateTo(0);
                    Future.delayed(
                      const Duration(milliseconds: 300),
                      () => _mapController.move(b.position, 18.0),
                    );
                    _showBuildingDetail(b);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── 산책로 탭 ───

  double _calcTrailDistance(List<LatLng> pts) {
    double total = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      total += _haversine(pts[i], pts[i + 1]);
    }
    return total;
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final x =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(x));
  }

  String _formatDist(double m) {
    if (m < 1000) return '${m.round()}m';
    return '${(m / 1000).toStringAsFixed(2)}km';
  }

  Widget _buildTrailTab(Color primary, bool isDark) {
    if (_savedTrails.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.route_rounded,
              size: 56,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 12),
            Text(
              '저장된 산책로가 없습니다',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '지도 탭에서 🛤️ 버튼을 눌러 산책로를 그려보세요',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '내 산책로 · ${_savedTrails.length}개',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            itemCount: _savedTrails.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, idx) {
              final trail = _savedTrails[idx];
              final name = idx < _trailNames.length
                  ? _trailNames[idx]
                  : '산책로 ${idx + 1}';
              final dist = _calcTrailDistance(trail);
              final trailColor =
                  Colors.primaries[idx % Colors.primaries.length];
              final isSelected = _selectedTrailIdx == idx;
              final walkMinutes = (dist / 80).ceil();
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTrailIdx = isSelected ? null : idx);
                  _tabController.animateTo(0);
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (trail.isNotEmpty) _animatedMove(trail.first, 16.5);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? trailColor
                          : trailColor.withValues(alpha: 0.25),
                      width: isSelected ? 2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: trailColor.withValues(
                          alpha: isSelected ? 0.18 : 0.06,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: trailColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.hiking_rounded,
                                color: trailColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.straighten_rounded,
                                        size: 13,
                                        color: trailColor,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _formatDist(dist),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: trailColor,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(
                                        Icons.timer_outlined,
                                        size: 13,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '약 $walkMinutes분',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(
                                        Icons.location_on_rounded,
                                        size: 13,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${trail.length}개 지점',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.ios_share_rounded,
                                    size: 18,
                                    color: Colors.blueAccent,
                                  ),
                                  tooltip: '공유',
                                  onPressed: () =>
                                      _shareTrail(idx, name, trail),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                  tooltip: '삭제',
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text(
                                        '산책로 삭제',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      content: Text('"$name"을(를) 삭제할까요?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c),
                                          child: const Text('취소'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(c);
                                            _deleteTrail(idx);
                                          },
                                          child: const Text(
                                            '삭제',
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: trailColor.withValues(alpha: 0.08),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(14),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '지도에서 표시 중 ✓',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: trailColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── 과 사무실 탭 ───

  Widget _buildDeptOfficeTab(bool isDark) {
    final colleges = ['제1대학', '제2대학', '제3대학', '제4대학'];
    final collegeColors = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
    ];
    final collegeIcons = [
      Icons.school_rounded,
      Icons.menu_book_rounded,
      Icons.science_rounded,
      Icons.palette_rounded,
    ];
    String _deptSearch = '';

    return StatefulBuilder(
      builder: (ctx, setLocal) {
        final query = _deptSearch.trim();
        return Column(
          children: [
            // 검색바
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white12
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setLocal(() => _deptSearch = v),
                        decoration: InputDecoration(
                          hintText: '학과 또는 건물명 검색...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 11,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: colleges.length,
                itemBuilder: (ctx, ci) {
                  final college = colleges[ci];
                  final color = collegeColors[ci];
                  final icon = collegeIcons[ci];
                  final depts = kDeptOffices.where((d) {
                    if (d.college != college) return false;
                    if (query.isEmpty) return true;
                    return d.dept.contains(query) || d.building.contains(query);
                  }).toList();
                  if (depts.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(icon, size: 15, color: color),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              college,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${depts.length}개 학과',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...depts.map(
                        (d) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1E2E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: color.withValues(alpha: 0.15),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              14,
                              6,
                              12,
                              6,
                            ),
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  d.dept.substring(0, 1),
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              d.dept,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              '${d.building} ${d.room}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white54 : Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: GestureDetector(
                              onTap: () async {
                                final uri = Uri.parse('tel:${d.phone}');
                                if (await canLaunchUrl(uri)) launchUrl(uri);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.call_rounded,
                                      size: 13,
                                      color: color,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      d.phone.replaceFirst('043-', ''),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            onTap: () {
                              // 건물로 이동
                              final building = kBuildings.firstWhere(
                                (b) => b.name.contains(
                                  d.building
                                      .replaceAll('관', '')
                                      .replaceAll('학관', ''),
                                ),
                                orElse: () => kBuildings.first,
                              );
                              _tabController.animateTo(0);
                              Future.delayed(
                                const Duration(milliseconds: 200),
                                () => _animatedMove(building.position, 18.5),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showReorderSheet(bool isDark, Color primary) {
    final tempOrder = List<int>.from(_buildingOrder);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '건물 순서 편집',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setLocalState(
                          () => tempOrder.setAll(
                            0,
                            List.generate(kBuildings.length, (i) => i),
                          ),
                        );
                      },
                      child: Text(
                        '초기화',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _buildingOrder = List.from(tempOrder));
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        '완료',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: tempOrder.length,
                  onReorder: (oldIdx, newIdx) {
                    setLocalState(() {
                      if (newIdx > oldIdx) newIdx--;
                      final item = tempOrder.removeAt(oldIdx);
                      tempOrder.insert(newIdx, item);
                    });
                  },
                  itemBuilder: (_, i) {
                    final b = kBuildings[tempOrder[i]];
                    return ListTile(
                      key: ValueKey(tempOrder[i]),
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: b.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            b.shortName.length > 2
                                ? b.shortName.substring(0, 2)
                                : b.shortName,
                            style: TextStyle(
                              color: b.color,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        b.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        b.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      trailing: Icon(
                        Icons.drag_handle_rounded,
                        color: isDark ? Colors.white38 : Colors.black26,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrailSection(bool isDark, Color primary) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      Row(
        children: [
          const Icon(Icons.route, size: 18),
          const SizedBox(width: 8),
          Text(
            '저장된 산책로',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ..._savedTrails.asMap().entries.map((e) {
        final idx = e.key;
        final trailColor = Colors.primaries[idx % Colors.primaries.length];
        final isSelected = _selectedTrailIdx == idx;
        final name = idx < _trailNames.length
            ? _trailNames[idx]
            : '산책로 ${idx + 1}';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? trailColor
                  : trailColor.withValues(alpha: 0.3),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: trailColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.hiking, color: trailColor),
                title: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  '${e.value.length}개 경유지',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 공유
                    IconButton(
                      icon: const Icon(
                        Icons.ios_share_rounded,
                        size: 20,
                        color: Colors.blueAccent,
                      ),
                      tooltip: '공유',
                      onPressed: () => _shareTrail(idx, name, e.value),
                    ),
                    // 지도에서 보기
                    IconButton(
                      icon: Icon(
                        Icons.map_outlined,
                        color: isSelected ? trailColor : Colors.grey,
                        size: 20,
                      ),
                      tooltip: '지도에서 보기',
                      onPressed: () {
                        setState(
                          () => _selectedTrailIdx = isSelected ? null : idx,
                        );
                        if (!isSelected) {
                          _tabController.animateTo(0);
                          Future.delayed(const Duration(milliseconds: 200), () {
                            final pts = e.value;
                            if (pts.isNotEmpty) _animatedMove(pts.first, 16.5);
                          });
                        }
                      },
                    ),
                    // 삭제
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      tooltip: '삭제',
                      onPressed: () => showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text(
                            '산책로 삭제',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          content: Text('"$name"을(를) 삭제할까요?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _deleteTrail(idx);
                              },
                              child: const Text(
                                '삭제',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  // 이름 수정
                  final ctrl = TextEditingController(text: name);
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text(
                        '산책로 이름 변경',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: const InputDecoration(hintText: '산책로 이름'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (ctrl.text.trim().isNotEmpty) {
                              setState(() {
                                while (_trailNames.length <= idx)
                                  _trailNames.add(
                                    '산책로 ${_trailNames.length + 1}',
                                  );
                                _trailNames[idx] = ctrl.text.trim();
                              });
                              _persistTrails();
                            }
                          },
                          child: const Text(
                            '확인',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // 선택된 경우 강조 표시
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.circle, color: trailColor, size: 10),
                      const SizedBox(width: 6),
                      Text(
                        '지도에서 하이라이트 중',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: trailColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    ],
  );

  // ─── 바텀시트: 건물 ───

  void _showBuildingDetail(BuildingData b) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 핸들
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 헤더
              Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: b.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          b.shortName.length > 3
                              ? b.shortName.substring(0, 3)
                              : b.shortName,
                          style: TextStyle(
                            color: b.color,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: isDark ? Colors.white : Colors.black87,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            b.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 층별 안내 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: b.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '층별 안내',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  itemCount: b.floors.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final f = b.floors[b.floors.length - 1 - i];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 28,
                            decoration: BoxDecoration(
                              color: b.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${f.floor}F',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: b.color,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              f.rooms.join('  ·  '),
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 바텀시트: 시설 ───

  void _showFacilityDetail(MapFacility f) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 16),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 아이콘 + 이름
              Row(
                children: [
                  const SizedBox(width: 20),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: f.type.color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(f.type.icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white : Colors.black87,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: f.type.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          f.type.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: f.type.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 운영 시간 카드
              if (f.detail != null) ...[
                const SizedBox(height: 14),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        f.detail!,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    color: f.type.color,
                    borderRadius: BorderRadius.circular(14),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _animatedMove(f.position, 18.5);
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.near_me_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '지도에서 보기',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 외부 지도 ───

  // ─── Windows 폴백 ───

  Widget _buildDesktopFallback(Color primary, bool isDark) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.map_rounded, size: 72, color: primary),
        ),
        const SizedBox(height: 24),
        Text(
          '캠퍼스 지도',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '지도는 모바일 앱에서 이용 가능합니다',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '아래 [건물 안내] 탭에서 층별 시설 정보를 확인하세요',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () => _tabController.animateTo(1),
          icon: const Icon(Icons.business),
          label: const Text(
            '건물 안내 보기',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    ),
  );
}

// ───────────────────────────────────────── 지도 레이블 마커 ──
// 건물 이름처럼 생긴 말풍선 라벨 (하단에 작은 삼각형 pointer)

class _MapLabel extends StatelessWidget {
  final String text;
  final Color color;
  final bool large;
  const _MapLabel({
    required this.text,
    required this.color,
    required this.large,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: large ? 10 : 7,
            vertical: large ? 5 : 3,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(large ? 10 : 7),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: large ? 11 : 9,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        CustomPaint(
          painter: _TrianglePainter(color: color),
          size: const Size(8, 5),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────── 시설 핀 마커 ──

class _FacilityPin extends StatelessWidget {
  final FacilityType type;
  const _FacilityPin({required this.type});

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: type.color,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
      boxShadow: [
        BoxShadow(
          color: type.color.withValues(alpha: 0.4),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: Icon(type.icon, color: Colors.white, size: 17),
  );
}

// ─────────────────────────── 필터 칩 ──

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active, isDark;
  final bool small;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.isDark,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: small ? 9 : 11,
        vertical: small ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: active
            ? color
            : (isDark
                  ? Colors.grey.shade900.withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.95)),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.0)
              : (isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.08)),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: small ? 12 : 13,
            color: active ? Colors.white : (isDark ? Colors.white70 : color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: active
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────── 건물 리스트 카드 ──

class _BuildingCard extends StatelessWidget {
  final BuildingData building;
  final bool isDark;
  final VoidCallback onTap;
  const _BuildingCard({
    required this.building,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: building.color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  building.shortName.length > 2
                      ? building.shortName.substring(0, 2)
                      : building.shortName,
                  style: TextStyle(
                    color: building.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    building.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    building.description,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white38 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.layers_rounded,
                        size: 12,
                        color: building.color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${building.floors.length}층',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: building.color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────── 줌/탑바 버튼 ──

class _PillZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;
  const _PillZoomBtn({
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (isDark ? Colors.white70 : Colors.black54);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(icon, color: fg, size: 20),
      ),
    );
  }
}

class _TopBarBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color? activeColor;
  const _TopBarBtn({
    required this.icon,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: active
            ? (activeColor ?? Colors.white).withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 20,
        color: active
            ? (activeColor ?? Colors.white)
            : Colors.white.withValues(alpha: 0.7),
      ),
    ),
  );
}

// ──────────────────────────────────────────────── 검색 모델 ──

class _SearchItem {
  final String name;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SearchItem({
    required this.name,
    required this.sub,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
