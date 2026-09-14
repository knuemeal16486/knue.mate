import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'building_data.dart';
import 'offline_cache.dart';
import 'meal_rating.dart';
import 'constants.dart';
import 'bus_model.dart';

class FirebaseSyncService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// [건물 정보] 로컬 JSON 데이터를 Firestore로 업로드합니다.
  static Future<void> uploadBuildingsToFirestore() async {
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('FirebaseSyncService: Firebase가 초기화되지 않았습니다.');
        return;
      }
      final String jsonString = await rootBundle.loadString(
        'assets/buildings/knue_buildings.json',
      );
      final dynamic decoded = json.decode(jsonString);
      final Map<String, dynamic> jsonData = Map<String, dynamic>.from(decoded);
      final List<dynamic> buildingsJson = jsonData['buildings'] ?? [];

      final batch = _firestore.batch();
      final collection = _firestore.collection('knue_buildings');

      for (var bJson in buildingsJson) {
        if (bJson is! Map) continue;
        final Map<String, dynamic> buildingData = Map<String, dynamic>.from(bJson);
        final String? name = buildingData['name'];
        if (name == null || name.isEmpty) continue;
        final safeDocId = name.replaceAll('/', '_');
        final docRef = collection.doc(safeDocId);
        batch.set(docRef, {
          ...buildingData,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      debugPrint('FirebaseSyncService: 건물 정보 ${buildingsJson.length}개 Batch 업로드 완료');
    } catch (e) {
      debugPrint('FirebaseSyncService: 건물 정보 업로드 실패: $e');
    }
  }

  /// [건물 정보] Firestore에서 데이터를 가져와 BuildingData 리스트를 반환합니다.
  static Future<List<BuildingData>?> fetchBuildingsFromFirestore() async {
    try {
      if (Firebase.apps.isEmpty) return null;
      final snapshot = await _firestore.collection('knue_buildings').get();
      if (snapshot.docs.isEmpty) return null;

      List<BuildingData> firestoreBuildings = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String name = (data['name'] as String?) ?? doc.id;
        final dynamic floorsRaw = data['floors'];
        if (floorsRaw is! List) continue;

        final List<FloorData> floors = [];
        for (var fJson in floorsRaw) {
          if (fJson is! Map) continue;
          final dynamic facList = fJson['facilities'];
          final List<String> rooms = [];
          if (facList is List) {
            for (var fac in facList) {
              if (fac is Map) {
                final String? roomNum = fac['room']?.toString();
                final String facName = fac['name']?.toString() ?? '';
                if (roomNum != null && roomNum.isNotEmpty) {
                  rooms.add('$roomNum $facName'.trim());
                } else if (facName.isNotEmpty) {
                  rooms.add(facName.trim());
                }
              } else if (fac is String && fac.isNotEmpty) {
                rooms.add(fac.trim());
              }
            }
          }

          floors.add(FloorData(floor: fJson['floor'] ?? '1F', rooms: rooms));
        }

        firestoreBuildings.add(
          BuildingData(
            name: name,
            shortName: '',
            description: '',
            position: const LatLng(36.61, 127.35),
            color: Colors.grey,
            floors: floors,
          ),
        );
      }
      return firestoreBuildings;
    } catch (e) {
      debugPrint('FirebaseSyncService: 건물 정보 가져오기 실패: $e');
      return null;
    }
  }

  /// [식단 정보] 특정 날짜의 식단을 Firestore에 저장합니다.
  static Future<void> saveMealToFirestore(
    DateTime date,
    MealSource source,
    Map<String, dynamic> mealData,
  ) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final docId = "${dateStr}_${source.name}";

      await _firestore.collection('daily_meals').doc(docId).set({
        'date': dateStr,
        'source': source.name,
        'meals': mealData['meals'],
        'lastUpdated': FieldValue.serverTimestamp(),
        'cacheVersion': 2,
      });
    } catch (e) {
      debugPrint('FirebaseSyncService: 식단 저장 실패: $e');
    }
  }

  /// 공용 식단 문서를 그대로 믿어도 되는지.
  ///
  /// 지난 날짜의 식단은 더 바뀌지 않으니 언제 저장됐든 그대로 쓴다. 문제는
  /// 오늘 이후다 — 이 문서는 그 날짜를 처음 열어본 사람이 한 번 쓰면 아무도
  /// 다시 쓰지 않는다. 실제로 8월 31일에 저장된 교직원 식당 메뉴가 9월 중순까지
  /// 모든 사용자에게 내려가고 있었다. lastUpdated는 줄곧 저장만 하고 아무도
  /// 읽지 않았다.
  static bool _isMealDocStale(DateTime date, Map<String, dynamic>? data) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target.isBefore(today)) return false;

    final ts = data?['lastUpdated'];
    if (ts is! Timestamp) return true; // 언제 쓴 값인지 모르면 새로 긁는다
    return now.difference(ts.toDate()) > const Duration(hours: 12);
  }

  /// [식단 정보] Firestore에서 특정 날짜의 식단을 가져옵니다.
  static Future<Map<String, dynamic>?> getMealFromFirestore(
    DateTime date,
    MealSource source,
  ) async {
    try {
      if (Firebase.apps.isEmpty) return null;
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final docId = "${dateStr}_${source.name}";

      final doc = await _firestore.collection('daily_meals').doc(docId).get();
      if (doc.exists) {
        final data = doc.data();
        if (_isMealDocStale(date, data)) return null; // 새로 긁어오게 둔다
        return data;
      }
    } catch (e) {
      // 규칙 미배포·네트워크 문제 — 잠시 Firestore를 건너뛰도록 표시한다.
      FirestoreHealth.reportFailure();
      debugPrint('FirebaseSyncService: 식단 가져오기 실패: $e');
    }
    return null;
  }

  // ==================== 버스 시간표 Firebase 연동 ====================

  /// [버스 시간표] 시간표 데이터를 Firestore에 업로드합니다.
  static Future<void> uploadBusTimetableToFirestore(
    String routeNumber,
    bool isOutgoing,
    bool isWeekday,
    List<String> departureTimes,
  ) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final docId =
          "${routeNumber}_${isOutgoing ? 'outgoing' : 'incoming'}_${isWeekday ? 'weekday' : 'holiday'}";

      await _firestore.collection('bus_timetables').doc(docId).set({
        'routeNumber': routeNumber,
        'isOutgoing': isOutgoing,
        'isWeekday': isWeekday,
        'departureTimes': departureTimes,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      debugPrint('FirebaseSyncService: 버스 $routeNumber 시간표 업로드 완료 ($docId)');
    } catch (e) {
      debugPrint('FirebaseSyncService: 버스 시간표 업로드 실패: $e');
    }
  }

  /// [버스 시간표] 전체 시간표 일괄 업로드
  static Future<void> uploadAllBusTimetables(
    Map<String, Map<String, Map<String, List<String>>>> timetables,
  ) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final batch = _firestore.batch();
      final collection = _firestore.collection('bus_timetables');

      for (final routeNumber in timetables.keys) {
        final directions = timetables[routeNumber]!;
        for (final direction in directions.keys) {
          final isOutgoing = direction == 'outgoing';
          final days = directions[direction]!;

          for (final dayType in days.keys) {
            final isWeekday = dayType == 'weekday';
            final times = days[dayType]!;

            final docId = "${routeNumber}_${direction}_$dayType";
            final docRef = collection.doc(docId);

            batch.set(docRef, {
              'routeNumber': routeNumber,
              'isOutgoing': isOutgoing,
              'isWeekday': isWeekday,
              'departureTimes': times,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      await batch.commit();
      debugPrint('FirebaseSyncService: 전체 버스 시간표 업로드 완료');
    } catch (e) {
      debugPrint('FirebaseSyncService: 전체 버스 시간표 업로드 실패: $e');
    }
  }

  /// [버스 시간표] Firestore에서 특정 노선의 시간표 가져오기
  static Future<BusTimetable?> fetchBusTimetable(
    String routeNumber, {
    bool isOutgoing = true,
    bool isWeekday = true,
  }) async {
    try {
      if (Firebase.apps.isEmpty) return null;
      final docId =
          "${routeNumber}_${isOutgoing ? 'outgoing' : 'incoming'}_${isWeekday ? 'weekday' : 'holiday'}";

      final doc = await _firestore
          .collection('bus_timetables')
          .doc(docId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        return BusTimetable.fromJson(data);
      }
    } catch (e) {
      debugPrint('FirebaseSyncService: 버스 시간표 가져오기 실패 ($routeNumber): $e');
    }
    return null;
  }

  /// [버스 시간표] Firestore에서 전체 시간표 가져오기
  static Future<Map<String, List<BusTimetable>>> fetchAllBusTimetables() async {
    try {
      if (Firebase.apps.isEmpty) return {};
      final snapshot = await _firestore.collection('bus_timetables').get();

      final Map<String, List<BusTimetable>> timetables = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final timetable = BusTimetable.fromJson(data);

        if (!timetables.containsKey(timetable.routeNumber)) {
          timetables[timetable.routeNumber] = [];
        }
        timetables[timetable.routeNumber]!.add(timetable);
      }

      return timetables;
    } catch (e) {
      debugPrint('FirebaseSyncService: 전체 버스 시간표 가져오기 실패: $e');
      return {};
    }
  }

  // ==================== 실시간 버스 정보 Firebase 연동 ====================

  /// [실시간 버스] 버스 위치/도착 정보 Firestore에 저장
  static Future<void> saveBusRealtimeData(List<BusSummary> busSummaries) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final summariesJson = busSummaries.map((b) => b.toJson()).toList();

      await _firestore.collection('realtime').doc('bus_locations').set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'summaries': summariesJson,
      });

      debugPrint(
        'FirebaseSyncService: 실시간 버스 데이터 저장 완료 (${busSummaries.length}개 노선)',
      );
    } catch (e) {
      debugPrint('FirebaseSyncService: 실시간 버스 데이터 저장 실패: $e');
    }
  }

  /// [실시간 버스] Firestore에서 실시간 버스 데이터 가져오기
  static Future<List<BusSummary>?> fetchBusRealtimeData() async {
    try {
      if (Firebase.apps.isEmpty) return null;
      final doc = await _firestore
          .collection('realtime')
          .doc('bus_locations')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final List<dynamic>? summaries = data['summaries'];

        if (summaries != null) {
          return summaries
              .map((e) => BusSummary.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('FirebaseSyncService: 실시간 버스 데이터 가져오기 실패: $e');
    }
    return null;
  }

  /// [실시간 버스] 실시간 버스 데이터 스트림 구독
  static Stream<List<BusSummary>?> subscribeBusRealtimeData() {
    if (Firebase.apps.isEmpty) return const Stream.empty();
    return _firestore
        .collection('realtime')
        .doc('bus_locations')
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;

          final data = snapshot.data() as Map<String, dynamic>;
          final List<dynamic>? summaries = data['summaries'];

          if (summaries != null) {
            return summaries
                .map((e) => BusSummary.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          return null;
        });
  }

  /// [실시간 버스] 마지막 업데이트 시간 가져오기
  static Future<DateTime?> getLastBusUpdateTime() async {
    try {
      if (Firebase.apps.isEmpty) return null;
      final doc = await _firestore
          .collection('realtime')
          .doc('bus_locations')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final timestamp = data['lastUpdated'] as Timestamp?;
        return timestamp?.toDate();
      }
    } catch (e) {
      debugPrint('FirebaseSyncService: 마지막 업데이트 시간 가져오기 실패: $e');
    }
    return null;
  }

  // ==================== 버스 정류장 정보 Firebase 연동 ====================

  /// [버스 정류장] Firestore에 정류장 정보 저장
  static Future<void> uploadBusStopsToFirestore(
    List<BusStop> stops,
    String routeNumber,
  ) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final batch = _firestore.batch();
      final collection = _firestore.collection('bus_stops');

      for (final stop in stops) {
        final docRef = collection.doc('${routeNumber}_${stop.nodeId}');
        batch.set(docRef, {
          ...stop.toJson(),
          'routeNumber': routeNumber,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      debugPrint('FirebaseSyncService: 버스 $routeNumber 정류장 ${stops.length}개 업로드 완료');
    } catch (e) {
      debugPrint('FirebaseSyncService: 버스 정류장 업로드 실패: $e');
    }
  }

  /// [버스 정류장] Firestore에서 특정 노선의 정류장 정보 가져오기
  static Future<List<BusStop>> fetchBusStops(String routeNumber) async {
    try {
      if (Firebase.apps.isEmpty) return [];
      final snapshot = await _firestore
          .collection('bus_stops')
          .where('routeNumber', isEqualTo: routeNumber)
          .orderBy('nodeOrd')
          .get();

      return snapshot.docs.map((doc) => BusStop.fromJson(doc.data())).toList();
    } catch (e) {
      debugPrint('FirebaseSyncService: 버스 정류장 가져오기 실패 ($routeNumber): $e');
      return [];
    }
  }

  // ==================== 식단 별점 기능 ====================

  /// [식단 별점] 별점을 Firestore에 저장합니다.
  /// key: "{date}_{source}_{mealType}" (예: "2024-01-15_a_lunch")
  static Future<void> saveMealRating({
    required DateTime date,
    required MealSource source,
    required MealType mealType,
    required double rating,
  }) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final docId = "${dateStr}_${source.name}_${mealType.name}";

      await _firestore.collection('meal_ratings').doc(docId).set({
        'date': dateStr,
        'source': source.name,
        'mealType': mealType.name,
        'rating': rating,
        'ratedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('FirebaseSyncService: 별점 저장 완료 ($docId: $rating)');
    } catch (e) {
      debugPrint('FirebaseSyncService: 별점 저장 실패: $e');
    }
  }

  /// [식단 별점] 한 끼니의 평균 별점·참여자 수·배식 방식 투표를 한 번에 가져온다.
  /// 홈 카드처럼 화면을 막으면 안 되는 곳에서 쓰므로 짧은 타임아웃을 걸고,
  /// Firestore가 이미 실패한 상태면 아예 건너뛴다.
  static Future<MealRatingSummary?> getMealRatingSummary({
    required DateTime date,
    required MealSource source,
    required MealType mealType,
  }) async {
    if (Firebase.apps.isEmpty || !FirestoreHealth.isAvailable) return null;
    try {
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final snap = await _firestore
          .collection('meal_ratings')
          .where('date', isEqualTo: dateStr)
          .where('source', isEqualTo: source.name)
          .where('mealType', isEqualTo: mealType.stdKey)
          .get()
          .timeout(const Duration(seconds: 3));
      FirestoreHealth.reportSuccess();
      return MealRatingSummary.fromDocs(snap.docs.map((d) => d.data()));
    } catch (e) {
      FirestoreHealth.reportFailure();
      debugPrint('FirebaseSyncService: 별점 집계 실패: $e');
      return null;
    }
  }

  /// [식단 별점] Firestore에서 특정 식단의 별점을 가져옵니다.
  static Future<double?> getMealRating({
    required DateTime date,
    required MealSource source,
    required MealType mealType,
  }) async {
    try {
      if (Firebase.apps.isEmpty) return null;
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final docId = "${dateStr}_${source.name}_${mealType.name}";

      final doc = await _firestore.collection('meal_ratings').doc(docId).get();
      if (doc.exists) {
        final data = doc.data();
        return data?['rating']?.toDouble();
      }
    } catch (e) {
      debugPrint('FirebaseSyncService: 별점 가져오기 실패: $e');
    }
    return null;
  }

  /// [식단 별점] 해당 식사가 별점 매기가 가능한 시간인지 확인
  /// 식사 시작시간 ~ 식사 종료 1시간 뒤까지 별점 매기 가능
  static bool canRateMeal(
    MealType mealType,
    DateTime targetDate,
    DateTime now,
  ) {
    // 오늘이 아니면 별점 매기 가능 (과거 날짜도 평가 가능)
    // 오늘이라면 시간 제한 적용
    if (!DateUtils.isSameDay(targetDate, now)) {
      return true;
    }

    // 식사 시간대별 시작 시간과 종료 후 1시간까지
    final times = mealType.timeRange.split("~");
    if (times.length != 2) return false;

    final startStr = times[0].trim().split(":");
    final endStr = times[1].trim().split(":");

    final startHour = int.parse(startStr[0]);
    final startMinute = int.parse(startStr[1]);
    final endHour = int.parse(endStr[0]);
    final endMinute = int.parse(endStr[1]);

    // 식사 시작 시간
    final mealStart = DateTime(
      now.year,
      now.month,
      now.day,
      startHour,
      startMinute,
    );
    // 식사 종료 후 1시간
    final mealEndPlusOne = DateTime(
      now.year,
      now.month,
      now.day,
      endHour,
      endMinute,
    ).add(const Duration(hours: 1));

    // 현재 시간이 식사 시작 후 1시간 뒤까지
    return now.isAfter(mealStart) && now.isBefore(mealEndPlusOne);
  }
}