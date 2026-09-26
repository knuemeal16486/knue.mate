import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 나만의 원룸 발품 점검표 항목
class HousingInspectionItem {
  final String key;
  final String title;
  final String description;

  const HousingInspectionItem({
    required this.key,
    required this.title,
    required this.description,
  });
}

const List<HousingInspectionItem> kInspectionItems = [
  HousingInspectionItem(
    key: 'water_pressure',
    title: '수압 및 온수 배수 상태',
    description: '싱크대와 화장실 샤워기를 동시에 틀었을 때 수압 저하 및 배수 속도 확인',
  ),
  HousingInspectionItem(
    key: 'sunlight',
    title: '창문 방향 및 채광/환기',
    description: '남향/동향 여부, 창문 바로 앞 건물에 가려 햇빛이나 통풍이 막히지 않는지 확인',
  ),
  HousingInspectionItem(
    key: 'mold_smell',
    title: '곰팡이 흔적 및 배수구 냄새',
    description: '벽지 모서리, 장판 밑, 싱크대 하부장, 화장실 천장 곰팡이 및 하수구 악취 확인',
  ),
  HousingInspectionItem(
    key: 'soundproof',
    title: '벽 두께 및 방음 상태',
    description: '벽을 가볍게 두드렸을 때 석고보드 가벽 소리가 나는지, 복도/옆방 소음 차단 확인',
  ),
  HousingInspectionItem(
    key: 'appliances',
    title: '기본 가전 옵션 청결/작동',
    description: '에어컨 냄새 및 필터 상태, 냉장고 냉기, 세탁기 작동 및 가스레인지/인덕션 화력',
  ),
  HousingInspectionItem(
    key: 'utility_costs',
    title: '관리비 실부담 및 난방 방식',
    description: '도시가스 여부(심야전기/LPG 주의), 관리비에 수도/인터넷/공용전기 포함 항목',
  ),
  HousingInspectionItem(
    key: 'security_parking',
    title: '공동현관 보안/택배/주차',
    description: '공동현관 도어락, CCTV 설치 여부, 택배 보관 장소 및 1층 주차 공간 여유',
  ),
];

/// 건물별 개인 발품 기록 모델
class HousingNoteData {
  final String buildingId;
  final Set<String> checkedKeys;
  final String memo;
  final DateTime updatedAt;

  const HousingNoteData({
    required this.buildingId,
    this.checkedKeys = const {},
    this.memo = '',
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'buildingId': buildingId,
        'checkedKeys': checkedKeys.toList(),
        'memo': memo,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory HousingNoteData.fromJson(Map<String, dynamic> json) {
    return HousingNoteData(
      buildingId: json['buildingId'] as String? ?? '',
      checkedKeys: Set<String>.from(json['checkedKeys'] as List? ?? []),
      memo: json['memo'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 발품 수첩 로컬 저장소 서비스
class HousingNoteService {
  HousingNoteService._();

  static const String _prefix = 'housing_note_';

  static Future<HousingNoteData?> loadNote(String buildingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$buildingId');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return HousingNoteData.fromJson(map);
    } catch (e) {
      debugPrint('HousingNoteService.loadNote 에러: $e');
      return null;
    }
  }

  static Future<bool> saveNote(HousingNoteData note) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(note.toJson());
      return await prefs.setString('$_prefix${note.buildingId}', raw);
    } catch (e) {
      debugPrint('HousingNoteService.saveNote 에러: $e');
      return false;
    }
  }

  static Future<bool> deleteNote(String buildingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove('$_prefix$buildingId');
    } catch (e) {
      debugPrint('HousingNoteService.deleteNote 에러: $e');
      return false;
    }
  }
}
