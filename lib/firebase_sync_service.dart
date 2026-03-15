import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'building_data.dart';
import 'constants.dart';

class FirebaseSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// [건물 정보] 로컬 JSON 데이터를 Firestore로 업로드합니다.
  static Future<void> uploadBuildingsToFirestore() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/buildings/knue_buildings.json',
      );
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final List<dynamic> buildingsJson = jsonData['buildings'];

      final batch = _firestore.batch();
      final collection = _firestore.collection('knue_buildings');

      for (var bJson in buildingsJson) {
        final String name = bJson['name'];
        final docRef = collection.doc(name);
        batch.set(docRef, {
          ...bJson,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      print('FirebaseSyncService: 건물 정보 ${buildingsJson.length}개 Batch 업로드 완료');
    } catch (e) {
      print('FirebaseSyncService: 건물 정보 업로드 실패: $e');
    }
  }

  /// [건물 정보] Firestore에서 데이터를 가져와 BuildingData 리스트를 반환합니다.
  static Future<List<BuildingData>?> fetchBuildingsFromFirestore() async {
    try {
      final snapshot = await _firestore.collection('knue_buildings').get();
      if (snapshot.docs.isEmpty) return null;

      List<BuildingData> firestoreBuildings = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String name = data['name'];
        final List<dynamic> floorsJson = data['floors'] ?? [];

        final List<FloorData> floors = floorsJson.map((fJson) {
          final List<String> rooms = (fJson['facilities'] as List).map((fac) {
            final String? roomNum = fac['room'];
            final String facName = fac['name'] ?? '';
            if (roomNum != null && roomNum.isNotEmpty) {
              return '$roomNum $facName'.trim();
            }
            return facName.trim();
          }).where((s) => s.isNotEmpty).toList();

          return FloorData(floor: fJson['floor'], rooms: rooms);
        }).toList();

        firestoreBuildings.add(BuildingData(
          name: name,
          shortName: '', 
          description: '',
          position: LatLng(36.61, 127.35), 
          color: Colors.grey,
          floors: floors,
        ));
      }
      return firestoreBuildings;
    } catch (e) {
      print('FirebaseSyncService: 건물 정보 가져오기 실패: $e');
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
      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final docId = "${dateStr}_${source.name}";

      await _firestore.collection('daily_meals').doc(docId).set({
        'date': dateStr,
        'source': source.name,
        'meals': mealData['meals'],
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('FirebaseSyncService: 식단 저장 실패: $e');
    }
  }

  /// [식단 정보] Firestore에서 특정 날짜의 식단을 가져옵니다.
  static Future<Map<String, dynamic>?> getMealFromFirestore(
    DateTime date,
    MealSource source,
  ) async {
    try {
      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final docId = "${dateStr}_${source.name}";

      final doc = await _firestore.collection('daily_meals').doc(docId).get();
      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      print('FirebaseSyncService: 식단 가져오기 실패: $e');
    }
    return null;
  }
}
