import 'dart:ui';
import 'housing_iso.dart';
import 'geo_utils.dart';

/// VWorld에서 제공하는 GeoJSON 피처를 앱 내부 모델로 변환하는 유틸리티
class MapDataParser {
  /// 화면 중심 좌표 (대학 중심)와 확대 배율을 사용해 위도/경도를 Offset으로 변환합니다.
  final LatLng mapCenter;
  final double scale;

  const MapDataParser({required this.mapCenter, required this.scale});

  /// 전체 GeoJSON 맵 데이터를 파싱해 건물, 도로, 지형(녹지 등) 리스트를 반환합니다.
  /// 반환 구조: {"buildings": List<BaseBuilding>, "roads": List<BaseRoad>, "terrain": BaseTerrain}
  Map<String, dynamic> parse(Map<String, dynamic> geoJson) {
    final List<BaseBuilding> buildings = [];
    final List<BaseRoad> roads = [];
    final List<Offset> trees = [];
    // Simple terrain placeholder – 실제 구현에서는 녹지·수역 등을 파싱합니다.
    final BaseTerrain terrain = BaseTerrain(trees: trees);

    final features = (geoJson['features'] as List?) ?? [];
    for (final raw in features) {
      final feature = raw as Map<String, dynamic>;
      final properties = feature['properties'] as Map<String, dynamic>? ?? {};
      final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
      final type = geometry['type'] as String? ?? '';

      // 건물 폴리곤
      if (type == 'Polygon' && properties['layer'] == 'bld') {
        final coords = geometry['coordinates'] as List;
        // VWorld는 [ [ [lng, lat], ... ] ] 형태 (외곽선 하나)
        final List<Offset> ring = [];
        for (final point in (coords.first as List)) {
          final lng = (point[0] as num).toDouble();
          final lat = (point[1] as num).toDouble();
          ring.add(latLngToOffset(LatLng(lat, lng), mapCenter, scale));
        }
        final building = BaseBuilding(
          id: properties['fid']?.toString() ?? 'unknown',
          floors: (properties['height'] as num?)?.toInt() ?? 1,
          ring: ring,
          officialName: properties['name']?.toString(),
          road: properties['road_name']?.toString(),
          buildingNo: properties['bldg_no']?.toString(),
          isCampus: true,
        );
        buildings.add(building);
        continue;
      }

      // 도로 라인
      if (type == 'LineString' && properties['layer'] == 'road') {
        final coords = geometry['coordinates'] as List;
        final List<Offset> pts = [];
        for (final point in coords) {
          final lng = (point[0] as num).toDouble();
          final lat = (point[1] as num).toDouble();
          pts.add(latLngToOffset(LatLng(lat, lng), mapCenter, scale));
        }
        final road = BaseRoad(pts, type: _roadTypeFromProps(properties));
        roads.add(road);
        continue;
      }

      // 단순 트리 포인트 (예: 녹지 점 데이터)
      if (type == 'Point' && properties['layer'] == 'tree') {
        final coord = geometry['coordinates'] as List;
        final lng = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();
        trees.add(latLngToOffset(LatLng(lat, lng), mapCenter, scale));
      }
    }
    return {
      'buildings': buildings,
      'roads': roads,
      'terrain': terrain,
    };
  }

  String _roadTypeFromProps(Map<String, dynamic> props) {
    final kind = props['road_type']?.toString().toLowerCase() ?? '';
    if (kind.contains('highway') || kind.contains('major')) return 'major';
    if (kind.contains('campus')) return 'campus_main';
    if (kind.contains('walk') || kind.contains('foot')) return 'walkway';
    return 'campus_sec';
  }
}
