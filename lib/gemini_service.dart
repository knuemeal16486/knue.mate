import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // [수정] 이 줄이 있어야 dotenv 에러가 사라집니다.

class GeminiService {
  // .env에서 키를 가져옴
  static String get apiKey => dotenv.env['GEMINI_API_KEY'] ?? "";

  // 모델 초기화
  static GenerativeModel get _model =>
      GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

  // [기능 1] 메뉴 리스트로 칼로리 예상하기
  static Future<String> estimateCalories(List<String> menuItems) async {
    if (apiKey.isEmpty) return "API키 없음";
    if (menuItems.isEmpty) return "";

    // "없음"이나 빈 항목 제거
    final menuString = menuItems.where((i) => !i.contains("없음")).join(", ");
    if (menuString.isEmpty) return "";

    final prompt =
        """
    너는 대학교 학생 식당의 '전문 영양사'다.
    사용자가 급식 메뉴 리스트를 주면, **20대 성인여성 1인분 배식량**을 기준으로 총 섭취 칼로리(kcal)를 추산해라.
    양은 흔히 단체식당에서 쓰는 철체 식판을 기준으로 한다. 
    
    메뉴: $menuString

    [절대 규칙]
    1. **무조건 답을 내라**: 처음 보거나 생소한 메뉴명이 있어도 절대 '모른다'거나 '정보 부족'이라고 하지 마라. 이름이 가장 비슷한 일반적인 음식으로 가정하고 칼로리를 계산해라.
    2. **단위**: 모든 계산은 10단위로 반올림해라. (예: 723 -> 720)
    3. **출력 형식**: 설명, 인사말, 기호 없이 오직 **"최소값~최대값kcal"** 형태의 문자열 하나만 출력해라. (범위는 ±30kcal 정도로 잡아라)
    4. 식단표 최상단의 메뉴가 주 식사이고, 나머지는 반찬으로, 양은 각각 100그램 정도이다.
    
    [출력 예시]
    850~950kcal
    """;

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text?.trim() ?? "측정불가";
    } catch (e) {
      print("Gemini Error: $e");
      return "측정불가";
    }
  }
}
