import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'geo_utils.dart';

/// VWorld API 서비스 – 국토교통부 공간정보 오픈플랫폼 (건물, 도로, 지적, 지형 데이터)
class VWorldApiService {
  static const String defaultApiKey = '4E4A8E57-990A-4BEE-BD4E-BF0AA63E318B';
  final String apiKey;

  VWorldApiService({String? apiKey}) : apiKey = apiKey ?? defaultApiKey;

  /// 교원대 및 인근 원룸촌 기본 BBOX (EPSG:4326)
  static const String knueBbox = '127.3470,36.6030,127.3670,36.6160';

  /// 특정 VWorld 레이어 데이터 가져오기 (version 2.0)
  Future<List<Map<String, dynamic>>> fetchLayer({
    required String layer,
    String bbox = knueBbox,
    int maxFeatures = 1000,
  }) async {
    try {
      final url = Uri.parse(
        'https://api.vworld.kr/req/data?service=data&request=GetFeature&version=2.0'
        '&data=$layer&format=json&size=${maxFeatures.clamp(1, 1000)}'
        '&geomFilter=BOX($bbox)&crs=EPSG:4326&key=$apiKey',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('VWorld API status error: ${response.statusCode}');
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final resp = json['response'] as Map<String, dynamic>?;
      if (resp?['status'] != 'OK') {
        debugPrint('VWorld $layer error: ${resp?['error']}');
        return const [];
      }
      final features = resp?['result']?['featureCollection']?['features'] as List?;
      return features?.whereType<Map<String, dynamic>>().toList() ?? const [];
    } catch (e) {
      debugPrint('VWorldApiService.fetchLayer($layer) exception: $e');
      return const [];
    }
  }

  /// 도로명주소 건물 데이터 (LT_C_SPBD)
  Future<List<Map<String, dynamic>>> fetchBuildings({String bbox = knueBbox}) =>
      fetchLayer(layer: 'LT_C_SPBD', bbox: bbox);

  /// 도로망 링크 데이터 (LT_L_SPRD 또는 LT_L_MOCTLINK)
  Future<List<Map<String, dynamic>>> fetchRoads({String bbox = knueBbox}) =>
      fetchLayer(layer: 'LT_L_SPRD', bbox: bbox);

  /// 연속지적도 지적 필지 데이터 (LP_PA_CBND_BUBUN)
  Future<List<Map<String, dynamic>>> fetchParcels({String bbox = knueBbox}) =>
      fetchLayer(layer: 'LP_PA_CBND_BUBUN', bbox: bbox);

  /// 중심점(LatLng)과 반경(m)으로 BBOX 문자열 생성
  String bboxFromCenter(LatLng center, double radius) {
    const degPerMeterLat = 1 / 111320.0;
    final degPerMeterLng = 1 / (111320.0 * math.cos(center.lat * math.pi / 180));
    final dLat = radius * degPerMeterLat;
    final dLng = radius * degPerMeterLng;
    return '${center.lng - dLng},${center.lat - dLat},${center.lng + dLng},${center.lat + dLat}';
  }
}

