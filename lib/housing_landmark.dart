import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'housing_model.dart';

// 자취방 지도에 개발자가 직접 찍는 위치: 버스정류장·정문·후문·쪽문.
//
// 예전엔 정문·탑연삼거리 정류장 좌표가 코드에 어림값으로 박혀 있었다
// (CampusLandmark). 찍어 둔 위치가 있으면 도보 거리·등시선이 그걸 쓴다.
// 좌표는 경위도로 저장한다 — 지도 월드 좌표는 원점을 바꾸면 틀어지지만
// 경위도는 캠퍼스맵 탭 같은 다른 지도에서도 그대로 쓸 수 있다.

enum HousingLandmarkKind {
  busStop('버스정류장', Icons.directions_bus_rounded, Color(0xFF2196F3)),
  mainGate('정문', Icons.account_balance_rounded, Color(0xFF3F51B5)),
  backGate('후문', Icons.door_back_door_rounded, Color(0xFF795548)),
  sideGate('쪽문', Icons.door_sliding_rounded, Color(0xFF009688));

  final String label;
  final IconData icon;
  final Color color;
  const HousingLandmarkKind(this.label, this.icon, this.color);

  static HousingLandmarkKind? fromKey(Object? key) {
    for (final k in values) {
      if (k.name == key) return k;
    }
    return null;
  }
}

@immutable
class HousingLandmark {
  final String id;
  final HousingLandmarkKind kind;

  /// 지도에 띄울 이름. 비우면 종류 이름(정문·후문…)을 쓴다.
  final String name;
  final double lon;
  final double lat;

  const HousingLandmark({
    required this.id,
    required this.kind,
    required this.name,
    required this.lon,
    required this.lat,
  });

  factory HousingLandmark.atWorld({
    required String id,
    required HousingLandmarkKind kind,
    required String name,
    required Offset world,
  }) {
    final (lon, lat) = housingWorldToLonLat(world);
    return HousingLandmark(id: id, kind: kind, name: name, lon: lon, lat: lat);
  }

  String get label => name.trim().isEmpty ? kind.label : name.trim();

  /// 지도 월드 좌표(미터).
  Offset get world => lonLatToHousingWorld(lon, lat);

  HousingLandmark copyWith({HousingLandmarkKind? kind, String? name, Offset? world}) {
    final (lon, lat) = world == null ? (this.lon, this.lat) : housingWorldToLonLat(world);
    return HousingLandmark(
      id: id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      lon: lon,
      lat: lat,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'kind': kind.name,
        'name': name.trim(),
        'lon': lon,
        'lat': lat,
      };

  /// 종류나 좌표가 없으면 그릴 수 없으니 null. 순수 함수 — 테스트 대상.
  static HousingLandmark? fromMap(String id, Map<String, dynamic> d) {
    final kind = HousingLandmarkKind.fromKey(d['kind']);
    final lon = d['lon'], lat = d['lat'];
    if (kind == null || lon is! num || lat is! num) return null;
    return HousingLandmark(
      id: id,
      kind: kind,
      name: (d['name'] as String?) ?? '',
      lon: lon.toDouble(),
      lat: lat.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HousingLandmark &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.lon == lon &&
      other.lat == lat;

  @override
  int get hashCode => Object.hash(id, kind, name, lon, lat);
}

/// 찍어 둔 위치 중 코드의 캠퍼스 거점을 대신할 것. 순수 함수 — 테스트 대상.
///  - 정문 → [CampusLandmark.mainGate] (여럿이면 먼저 찍은 것)
///  - 이름에 "탑연"이 든 버스정류장 → [CampusLandmark.topyeonStop]
Map<CampusLandmark, Offset> campusLandmarkOverrides(List<HousingLandmark> placed) {
  final out = <CampusLandmark, Offset>{};
  for (final l in placed) {
    if (l.kind == HousingLandmarkKind.mainGate) {
      out.putIfAbsent(CampusLandmark.mainGate, () => l.world);
    } else if (l.kind == HousingLandmarkKind.busStop && l.label.contains('탑연')) {
      out.putIfAbsent(CampusLandmark.topyeonStop, () => l.world);
    }
  }
  return out;
}

/// 찍은 위치를 Firestore `housing_landmarks`에 둔다. 읽기는 누구나, 쓰기는
/// 관리자만(firestore.rules).
class HousingLandmarkService {
  HousingLandmarkService._();

  static const String collection = 'housing_landmarks';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 실시간으로 받는다. 먼저 찍은 것이 앞에 오게 id(시각) 순으로 정렬한다.
  static Stream<List<HousingLandmark>> watch() =>
      _db.collection(collection).snapshots().map((snap) {
        final list = [
          for (final doc in snap.docs)
            if (HousingLandmark.fromMap(doc.id, doc.data()) case final l?) l,
        ]..sort((a, b) => a.id.compareTo(b.id));
        return list;
      });

  /// 쓰기 한도에 걸리면 끝없이 기다리므로 제한 시간을 둔다(housing_service 참고).
  static Future<void> save(HousingLandmark l) => _db
      .collection(collection)
      .doc(l.id)
      .set(l.toFirestore())
      .timeout(const Duration(seconds: 10));

  static Future<void> delete(String id) => _db
      .collection(collection)
      .doc(id)
      .delete()
      .timeout(const Duration(seconds: 10));
}
