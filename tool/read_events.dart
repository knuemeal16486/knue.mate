import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/knue-mate/databases/(default)/documents/club_events');

  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      print('✅ 성공적으로 데이터를 가져왔습니다.');
      print(response.body);
    } else {
      print('❌ 실패');
      print(response.body);
    }
  } catch (e) {
    print('❌ 에러 발생: $e');
  }
}
