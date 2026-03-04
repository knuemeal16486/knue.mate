import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final key =
      "30cd0a0964f70dcbb2c274ae4bb9c44ba1d7ba81515c3c9d68f0e708664da513";
  final uri = Uri.parse(
    "https://apis.data.go.kr/1613000/BusLcInfoInqireService/getRouteAcctoBusLcList?serviceKey=$key&pageNo=1&numOfRows=1&_type=json&cityCode=33010&routeId=CJB270008000",
  );

  try {
    print("Requesting...");
    final res = await http.get(uri).timeout(Duration(seconds: 10));
    print("Status: ${res.statusCode}");
    print("Body: ${utf8.decode(res.bodyBytes)}");
  } catch (e) {
    print("Error: $e");
  }
}
