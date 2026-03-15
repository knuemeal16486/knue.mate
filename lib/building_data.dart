import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class FloorData {
  final dynamic floor; // int or String
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

  /// 지상층 수만 반환 (floor 값이 양수 int인 층만 계산)
  int get aboveGroundFloorCount {
    int count = 0;
    for (var f in floors) {
      final fv = f.floor;
      if (fv is int && fv > 0) {
        count++;
      } else if (fv is String) {
        final upper = fv.toUpperCase();
        if (upper.endsWith('F')) {
          final prefix = upper.substring(0, upper.length - 1);
          if (int.tryParse(prefix) != null) count++;
        }
      }
    }
    return count;
  }
}

class _BuildingMeta {
  final String shortName;
  final String description;
  final LatLng position;
  final Color color;
  const _BuildingMeta({
    required this.shortName,
    required this.description,
    required this.position,
    required this.color,
  });
}

const Map<String, _BuildingMeta> _kBuildingMetadata = {
  '대학본부': _BuildingMeta(
    shortName: '대학본부',
    description: '행정처·총장실',
    position: LatLng(36.6088450, 127.357247),
    color: Colors.blueGrey,
  ),
  '대학원': _BuildingMeta(
    shortName: '대학원',
    description: '대학원 강의·연구',
    position: LatLng(36.6100459, 127.3578957),
    color: Colors.indigo,
  ),
  '교수회관': _BuildingMeta(
    shortName: '교수회관',
    description: '교수 휴게·회의 공간',
    position: LatLng(36.6106240, 127.3586735),
    color: Colors.brown,
  ),
  '관리동': _BuildingMeta(
    shortName: '관리동',
    description: '사도교육원 식당, 사도교육부',
    position: LatLng(36.6130770, 127.360681),
    color: Colors.grey,
  ),
  '복지관': _BuildingMeta(
    shortName: '복지관',
    description: '체력단련실, 탁구장',
    position: LatLng(36.6131940, 127.359020),
    color: Colors.pink,
  ),
  '다정관': _BuildingMeta(
    shortName: '다정관',
    description: '사도교육원 의무입사자 생활관',
    position: LatLng(36.6134070, 127.359612),
    color: Colors.blue,
  ),
  '다감관': _BuildingMeta(
    shortName: '다감관',
    description: '사도교육원 희망입사자 생활관',
    position: LatLng(36.6140590, 127.360068),
    color: Colors.purple,
  ),
  '종합교육관': _BuildingMeta(
    shortName: '종교관',
    description: '1,2대학 강의실',
    position: LatLng(36.6107112, 127.3609668),
    color: Colors.teal,
  ),
  '인문과학관': _BuildingMeta(
    shortName: '인문과학관',
    description: '1,2대학 강의실',
    position: LatLng(36.6105993, 127.3598135),
    color: Colors.orange,
  ),
  '교양학관': _BuildingMeta(
    shortName: '교양관',
    description: '교직 및 교양 강의실, 초등교육과 심방',
    position: LatLng(36.6095798, 127.3607777),
    color: Colors.amber,
  ),
  '호연관': _BuildingMeta(
    shortName: '호연관',
    description: '집중열람실, 대학원 강의실·연구실',
    position: LatLng(36.6095940, 127.358824),
    color: Colors.brown,
  ),
  '교육연구관': _BuildingMeta(
    shortName: '교육연구관',
    description: '교육 연구동, 강의실',
    position: LatLng(36.6109030, 127.357467),
    color: Colors.cyan,
  ),
  '자연과학관': _BuildingMeta(
    shortName: '자관',
    description: '물리, 화학, 생물, 지구과학 강의실',
    position: LatLng(36.6086658, 127.3616172),
    color: Colors.green,
  ),
  '융합과학관': _BuildingMeta(
    shortName: '융합관',
    description: '컴퓨터, 환경 강의실',
    position: LatLng(36.6093890, 127.361463),
    color: Colors.lightBlue,
  ),
  '응용과학관': _BuildingMeta(
    shortName: '응관',
    description: '수학, 가정, 기술교육과 강의실',
    position: LatLng(36.6082061, 127.3621926),
    color: Colors.lightGreen,
  ),
  '체육관': _BuildingMeta(
    shortName: '체육관',
    description: '체육시설, 체육교육과 강의실',
    position: LatLng(36.6102322, 127.3624675),
    color: Colors.deepOrange,
  ),
  '음악관': _BuildingMeta(
    shortName: '음악관',
    description: '음악교육과 강의실, 연주실',
    position: LatLng(36.6075107, 127.3614496),
    color: Color(0xFF7B1FA2),
  ),
  '미술관': _BuildingMeta(
    shortName: '미술관',
    description: '미술교육과 강의실',
    position: LatLng(36.6079338, 127.3604786),
    color: Color(0xFFE64A19),
  ),
  '미래도서관': _BuildingMeta(
    shortName: '도서관',
    description: '자료실, 멀티미디어실, 하늘정원',
    position: LatLng(36.6090868, 127.3585314),
    color: Colors.deepPurple,
  ),
  '교원문화관': _BuildingMeta(
    shortName: '문화관',
    description: '대형 공연장',
    position: LatLng(36.6078498, 127.3586534),
    color: Colors.red,
  ),
  '교육박물관': _BuildingMeta(
    shortName: '교육박물관',
    description: '교육 역사 전시 및 행사',
    position: LatLng(36.6073352, 127.3572828),
    color: Colors.brown,
  ),
  '제1학생회관': _BuildingMeta(
    shortName: '학생회관',
    description: '교직원식당, 학생지원과, 동아리실, 브리드커피, 교내서점, 우체국',
    position: LatLng(36.6086039, 127.3598275),
    color: Colors.orange,
  ),
  '제2학생회관': _BuildingMeta(
    shortName: '제2학생회관',
    description: '동아리실',
    position: LatLng(36.6081765, 127.3595023),
    color: Colors.amber,
  ),
  '함덕당': _BuildingMeta(
    shortName: '함덕당',
    description: '연수원 기숙사',
    position: LatLng(36.6119620, 127.357349),
    color: Colors.teal,
  ),
  '교원연수관': _BuildingMeta(
    shortName: '연수관',
    description: '종합교육연수원, 영유아교육연수원',
    position: LatLng(36.6126140, 127.357145),
    color: Colors.blueGrey,
  ),
  '연수원 문화관': _BuildingMeta(
    shortName: '연수원문화관',
    description: '연수원 대강당',
    position: LatLng(36.6136010, 127.355852),
    color: Colors.deepPurple,
  ),
  '국제연수관': _BuildingMeta(
    shortName: '국제관',
    description: '국제 연수·교류',
    position: LatLng(36.6137910, 127.356961),
    color: Colors.blue,
  ),
  '함인당': _BuildingMeta(
    shortName: '함인당',
    description: '연수원 기숙사',
    position: LatLng(36.6153606, 127.3555380),
    color: Colors.indigo,
  ),
  '부설고': _BuildingMeta(
    shortName: '부설고',
    description: '한국교원대 부설고등학교',
    position: LatLng(36.6127180, 127.356082),
    color: Colors.green,
  ),
  '부설유치원': _BuildingMeta(
    shortName: '유치원',
    description: '영유아교육연구원, 한국교원대 부설 유치원',
    position: LatLng(36.6059044, 127.3573552),
    color: Colors.pink,
  ),
  '황새생태연구원': _BuildingMeta(
    shortName: '황새공원',
    description: '황새 생태 보전 연구',
    position: LatLng(36.6049560, 127.358783),
    color: Colors.lightGreen,
  ),
  '학군단': _BuildingMeta(
    shortName: '학군단',
    description: '한국교원대 ROTC 제150 학군단',
    position: LatLng(36.6061490, 127.360594),
    color: Colors.green,
  ),
  '교수아파트': _BuildingMeta(
    shortName: '교수APT',
    description: '교직원 주거 시설',
    position: LatLng(36.6122030, 127.352673),
    color: Colors.blueGrey,
  ),
};

List<BuildingData> kBuildings = [];

Future<void> loadBuildingData() async {
  // 1. 모든 메타데이터를 기반으로 기본 건물 리스트 생성 (먼저 모든 건물이 표시되도록 함)
  final List<BuildingData> allBuildings = [];
  _kBuildingMetadata.forEach((name, meta) {
    allBuildings.add(
      BuildingData(
        name: name,
        shortName: meta.shortName,
        description: meta.description,
        position: meta.position,
        color: meta.color,
        floors: [], // 기본값은 층 정보 없음
      ),
    );
  });

  try {
    // 2. JSON 파일 로드
    final String jsonString = await rootBundle.loadString(
      'assets/buildings/knue_buildings.json',
    );
    final Map<String, dynamic> jsonData = json.decode(jsonString);
    final List<dynamic> buildingsJson = jsonData['buildings'];

    // 3. JSON 데이터가 있는 건물에 대해 정보 업데이트
    for (var bJson in buildingsJson) {
      final String name = bJson['name'];

      // JSON의 건물명과 메타데이터의 건물명이 일치하는지 확인
      final int targetIdx = allBuildings.indexWhere((b) => b.name == name);
      if (targetIdx == -1) {
        debugPrint('Metadata not found for building in JSON: $name');
        continue;
      }

      final List<FloorData> floors = (bJson['floors'] as List).map((fJson) {
        final List<String> rooms = (fJson['facilities'] as List)
            .map((fac) {
              final String? roomNum = fac['room'];
              final String facName = fac['name'] ?? '';
              if (roomNum != null && roomNum.isNotEmpty) {
                return '$roomNum $facName'.trim();
              }
              return facName.trim();
            })
            .where((s) => s.isNotEmpty)
            .toList();

        return FloorData(floor: fJson['floor'], rooms: rooms);
      }).toList();

      // 층 정보가 있는 경우 보강
      final meta = allBuildings[targetIdx];
      allBuildings[targetIdx] = BuildingData(
        name: meta.name,
        shortName: meta.shortName,
        description: meta.description,
        position: meta.position,
        color: meta.color,
        floors: floors,
      );
    }

    kBuildings = allBuildings;
    debugPrint(
      'Successfully loaded ${kBuildings.length} buildings (JSON updated: ${buildingsJson.length})',
    );
  } catch (e) {
    debugPrint('Error loading building data: $e');
    // 오류 시에도 메타데이터만으로도 화면 표시는 가능하도록 설정
    if (kBuildings.isEmpty) {
      kBuildings = allBuildings;
    }
  }
}
