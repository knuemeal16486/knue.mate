import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  // .env에서 키를 안전하게 가져오기
  static String get apiKey {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      print("⚠️ GEMINI_API_KEY가 .env 파일에 설정되지 않았습니다.");
      return "";
    }
    return key;
  }

  // 모델 초기화
  static GenerativeModel get _model => GenerativeModel(
    model: 'gemini-2.0-flash', // 최신 안정 버전 사용
    apiKey: apiKey,
  );

  // 캐시를 위한 메모리 저장소
  static final Map<String, String> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  // 메뉴 리스트로 칼로리 예상하기
  static Future<String> estimateCalories(List<String> menuItems) async {
    if (apiKey.isEmpty) return "API 키 필요";
    if (menuItems.isEmpty) return "";

    // "없음"이나 빈 항목 제거
    final validItems = menuItems.where((item) {
      return item.trim().isNotEmpty &&
          !item.contains("없음") &&
          !item.contains("미운영");
    }).toList();

    if (validItems.isEmpty) return "";

    // 캐시 키 생성
    final cacheKey = validItems.join('|');

    // 캐시 확인 (1시간 유효)
    if (_cache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null &&
          DateTime.now().difference(timestamp).inHours < 1) {
        return _cache[cacheKey]!;
      }
    }

    final prompt = _buildPrompt(validItems);

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      final result = _normalizeCalorieResponse(response.text?.trim() ?? "");

      // 캐시에 저장
      _cache[cacheKey] = result;
      _cacheTimestamps[cacheKey] = DateTime.now();

      return result;
    } catch (e) {
      print("Gemini API 오류: $e");
      return "측정불가";
    }
  }

  static String _buildPrompt(List<String> menuItems) {
    final menuString = menuItems.join(", ");

    return """
    너는 대학교 학생 식당의 전문 영양사입니다.
    아래 메뉴를 보고 20대 성인여성 1인분 기준으로 총 섭취 칼로리(kcal)를 추산해주세요.
    
    메뉴: $menuString
    
    [중요 규칙]
    1. 모든 메뉴를 포함해서 계산하세요.
    2. 모르는 메뉴명이 있어도 비슷한 일반 음식으로 가정하고 계산하세요.
    3. 결과는 최소값과 최대값 범위로 표시하세요 (예: 650~750kcal).
    4. 칼로리의 예상 범위는 오차범위 30kcal 안에서 추산하세요.
    5. 설명이나 추가 텍스트 없이 숫자 범위만 출력하세요.
    6. 단위는 항상 "kcal"를 붙이세요.
    
    [출력 예시]
    800~850kcal
    """;
  }

  static String _normalizeCalorieResponse(String rawResponse) {
    if (rawResponse.isEmpty) return "측정불가";

    // 숫자와 kcal 패턴 찾기
    final regex = RegExp(r'(\d+)[~\-](\d+)\s*kcal', caseSensitive: false);
    final match = regex.firstMatch(rawResponse);

    if (match != null) {
      final min = match.group(1);
      final max = match.group(2);
      if (min != null && max != null) {
        return "${min}~${max}kcal";
      }
    }

    // 단일 숫자 찾기
    final singleRegex = RegExp(r'(\d+)\s*kcal', caseSensitive: false);
    final singleMatch = singleRegex.firstMatch(rawResponse);

    if (singleMatch != null) {
      final value = singleMatch.group(1);
      if (value != null) {
        final numValue = int.tryParse(value) ?? 0;
        final min = numValue - 50;
        final max = numValue + 50;
        return "${min}~${max}kcal";
      }
    }

    return "측정불가";
  }

  // 캐시 초기화 (선택적)
  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}
