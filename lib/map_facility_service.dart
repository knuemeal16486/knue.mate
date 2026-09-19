import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 개발자가 캠퍼스맵에 직접 찍은 위치 한 건. 코드에 박혀 있는 [kFacilities]와
/// 달리 Firestore에 저장되어 앱 업데이트 없이 모든 사용자에게 즉시 반영되고,
/// 지울 수도 있다.
class AdminMapFacility {
  final String id;
  final String name;

  /// [FacilityType.name] 문자열. enum 자체를 저장하면 순서가 바뀔 때 값이
  /// 흔들리므로 이름으로 저장한다.
  final String typeKey;
  final double lat;
  final double lng;
  final String? detail;

  const AdminMapFacility({
    required this.id,
    required this.name,
    required this.typeKey,
    required this.lat,
    required this.lng,
    this.detail,
  });

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'type': typeKey,
        'lat': lat,
        'lng': lng,
        if (detail != null && detail!.isNotEmpty) 'detail': detail,
        'createdAt': FieldValue.serverTimestamp(),
      };

  static AdminMapFacility? fromMap(String id, Map<String, dynamic> d) {
    final name = d['name'];
    final type = d['type'];
    final lat = d['lat'];
    final lng = d['lng'];
    if (name is! String || type is! String || lat is! num || lng is! num) {
      return null;
    }
    return AdminMapFacility(
      id: id,
      name: name,
      typeKey: type,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      detail: d['detail'] as String?,
    );
  }
}

/// 개발자가 캠퍼스맵에 찍은 위치의 저장·조회·삭제.
class MapFacilityService {
  static const String _collection = 'admin_map_facilities';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<List<AdminMapFacility>> fetchAll() async {
    try {
      final snap = await _db
          .collection(_collection)
          .get()
          .timeout(const Duration(seconds: 6));
      return snap.docs
          .map((d) => AdminMapFacility.fromMap(d.id, d.data()))
          .whereType<AdminMapFacility>()
          .toList();
    } catch (e) {
      debugPrint('MapFacilityService.fetchAll error: $e');
      return const [];
    }
  }

  static Future<void> add({
    required String name,
    required String typeKey,
    required double lat,
    required double lng,
    String? detail,
  }) async {
    await _db.collection(_collection).add(
          AdminMapFacility(
            id: '',
            name: name,
            typeKey: typeKey,
            lat: lat,
            lng: lng,
            detail: detail,
          ).toFirestore(),
        );
  }

  static Future<void> delete(String id) async {
    await _db.collection(_collection).doc(id).delete();
  }
}
