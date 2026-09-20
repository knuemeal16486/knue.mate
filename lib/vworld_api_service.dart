import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'geo_utils.dart';

/// VWorld API 서비스 – 건물, 도로, 녹지, 물 등 GeoJSON 데이터를 가져옴
class VWorldApiService {
  final String apiKey;

  VWorldApiService({required this.apiKey});

  /// radius는 미터 단위, center은 위도/경도 좌표
  Future<Map<String, dynamic>> fetchFeatures({
    required LatLng center,
    required double radius,
  }) async {
    // VWorld는 BBOX 파라미터( minX,minY,maxX,maxY ) 로 영역 지정
    // 위도/경도를 미터로 변환해 BBOX를 만든다.
    final bbox = _bboxFromCenter(center, radius);
    final url = Uri.parse(
        'https://api.vworld.kr/req/data?service=features&request=GetFeature'
        '&key=$apiKey'
        '&bbox=$bbox'
        '&type=ALL' // 모든 레이어 요청 (건물, 도로, 토지, 수역 등)
        '&format=json'
        '&size=5000'); // 최대 5000개 피처
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('VWorld API 호출 실패: ${response.statusCode}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// 위도/경도 중심점과 반경(미터)으로 BBOX 문자열 생성
  String _bboxFromCenter(LatLng center, double radius) {
    // 1° 위도 ≈ 111 km, 1° 경도 ≈ 111 km * cos(lat)
    final degPerMeterLat = 1 / 111320.0; // 대략적인 값
    final degPerMeterLng = 1 / (111320.0 * cosDeg(center.lat));
    final dLat = radius * degPerMeterLat;
    final dLng = radius * degPerMeterLng;
    final minLat = center.lat - dLat;
    final maxLat = center.lat + dLat;
    final minLng = center.lng - dLng;
    final maxLng = center.lng + dLng;
    return '$minLng,$minLat,$maxLng,$maxLat';
  }

  double cosDeg(double degree) => math.cos(degree * math.pi / 180);
}
