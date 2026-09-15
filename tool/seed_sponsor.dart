import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

/// Firebase Firestore 'sponsors' 컬렉션에 테스트용 제휴 광고를 등록하는 스크립트 예시
/// 실행: flutter run tool/seed_sponsor.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final db = FirebaseFirestore.instance;

  // 예시 1: 식단 탭 전용 식당 제휴 광고
  await db.collection('sponsors').doc('meal_sponsor_example').set({
    'title': "교원대 후문 '청람식당' 10% 할인",
    'subtitle': "학생증 제시 시 전 메뉴 10% 즉시 할인!",
    'callToAction': "위치 & 메뉴 보기",
    'targetUrl': "https://map.naver.com",
    'icon': "restaurant", // restaurant, cafe, bus, school, event, game, discount 등
    // 'imageUrl': "https://...",  // 있으면 아이콘 대신 이 이미지를 정사각으로 보여준다
    'placement': "meal",  // meal, bus, home, settings, all
    'priority': 10,
    'isActive': true,
    'startDate': "2026-03-01",
    'endDate': "2026-12-31",
  });

  // 예시 2: 전체 탭 공통 캠퍼스 이벤트
  await db.collection('sponsors').doc('all_event_example').set({
    'title': "2026 청람 동아리 박람회 & 버스킹",
    'subtitle': "학생회관 앞 광장에서 펼쳐지는 봄맞이 축제!",
    'callToAction': "일정 확인하기",
    'targetUrl': "https://www.knue.ac.kr",
    'icon': "event",
    'placement': "all",
    'priority': 5,
    'isActive': true,
    'startDate': "2026-03-01",
    'endDate': "2026-06-30",
  });

  print("✅ Firestore 'sponsors' 컬렉션에 샘플 제휴 광고가 등록되었습니다.");
}
