import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/knue-mate/databases/(default)/documents/club_events');

  final events = [
    {
      "fields": {
        "title": {"stringValue": "한국교원대 동동제 (청람축제)"},
        "clubName": {"stringValue": "총학생회"},
        "startDate": {"timestampValue": "2026-09-17T01:00:00Z"}, // 10:00 KST
        "endDate": {"timestampValue": "2026-09-18T13:00:00Z"}, // 22:00 KST
        "location": {"stringValue": "잔디밭"},
        "description": {"stringValue": "교원대 최고의 축제, 동동제가 잔디밭에서 열립니다!"},
        "isFeatured": {"booleanValue": true},
        "createdAt": {"timestampValue": DateTime.now().toUtc().toIso8601String()},
      }
    },
    {
      "fields": {
        "title": {"stringValue": "미술교육과 졸업전시회"},
        "clubName": {"stringValue": "미술교육과"},
        "startDate": {"timestampValue": "2026-09-17T01:00:00Z"}, // 10:00 KST
        "endDate": {"timestampValue": "2026-09-19T09:00:00Z"}, // 18:00 KST
        "location": {"stringValue": "미술관"},
        "description": {"stringValue": "4년간의 결실을 맺는 미술교육과 졸업전시회입니다. 많은 관람 부탁드립니다."},
        "isFeatured": {"booleanValue": true},
        "createdAt": {"timestampValue": DateTime.now().toUtc().toIso8601String()},
      }
    }
  ];

  for (var body in events) {
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final titleMap = body["fields"] as Map;
        final titleVal = titleMap["title"] as Map;
        print('✅ 성공적으로 예시 행사가 등록되었습니다: ${titleVal["stringValue"]}');
      } else {
        print('❌ 등록 실패');
        print(response.body);
      }
    } catch (e) {
      print('❌ 에러 발생: $e');
    }
  }
}
