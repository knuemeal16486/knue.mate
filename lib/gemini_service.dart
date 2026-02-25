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
    model: 'gemini-2.5-flash',
    apiKey: apiKey,
    // [추가] 음식 이름에 의한 불필요한 필터링 방지
    safetySettings: [
      SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
      SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
      SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
      SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
    ],
  );

  // 캐시를 위한 메모리 저장소
  static final Map<String, String> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  // 메뉴 리스트로 칼로리 예상하기
  static Future<String> estimateCalories(List<String> menuItems) async {
    if (apiKey.isEmpty) return "키 없음";
    if (menuItems.isEmpty) return "";

    // "없음"이나 빈 항목 제거
    final validItems = menuItems.where((item) {
      final trimmed = item.trim();
      return trimmed.isNotEmpty &&
          !trimmed.contains("없음") &&
          !trimmed.contains("미운영") &&
          !trimmed.contains("정보가");
    }).toList();

    if (validItems.isEmpty) return "";

    // 캐시 키 생성
    final cacheKey = validItems.join('|');

    // 캐시 확인 (6시간 유효로 연장)
    if (_cache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null &&
          DateTime.now().difference(timestamp).inHours < 6) {
        return _cache[cacheKey]!;
      }
    }

    final prompt = _buildPrompt(validItems);

    // [개선] 일시적 오류 발생 시 1회 재시도
    int retryCount = 0;
    while (retryCount < 2) {
      try {
        final content = [Content.text(prompt)];
        final response = await _model.generateContent(content);
        final rawText = response.text?.trim() ?? "";

        if (rawText.isEmpty) {
          retryCount++;
          continue;
        }

        final result = _normalizeCalorieResponse(rawText);

        if (result != "측정 불가") {
          // 캐시에 저장
          _cache[cacheKey] = result;
          _cacheTimestamps[cacheKey] = DateTime.now();
        }

        return result;
      } catch (e) {
        retryCount++;
        print("Gemini API 오류 (시도 $retryCount): $e");
        if (retryCount >= 2) break;
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    return "측정 불가";
  }

  static String _buildPrompt(List<String> menuItems) {
    final menuString = menuItems.join(", ");

    return """
    당신은 영양학 전문가입니다. 제공된 메뉴 리스트를 성인 여성이 한 끼 식사로 먹었을 때의 총 칼로리를 추산해 주세요.
    한 끼 식사의 전체 칼로리는 1000kcal를 넘지 않습니다.
    처음 보는 메뉴가 있어도, 이름을 통해 비슷한 음식의 칼로리를 추산해 주세요.
    
    메뉴: $menuString
    
    [출력 타입]
    반드시 '숫자~숫자kcal' 형식으로 응답하십시오. (예: 650~750kcal)
    숫자 범위는 플러스마이너스 20kcal 이내로 하십시오.  
    다른 어떤 설명이나 텍스트도 포함하지 마십시오. 오직 칼로리 범위만 출력하십시오.
    """;
  }

  static String _normalizeCalorieResponse(String rawResponse) {
    // 1. 공백 및 불필요 문자 정리
    String clean = rawResponse.replaceAll(RegExp(r'[*#_]'), '').trim();

    // 2. 숫자 추출 (가장 유연하게)
    final allNumbers = RegExp(
      r'\d+',
    ).allMatches(clean).map((m) => m.group(0)!).toList();

    if (allNumbers.length >= 2) {
      // 숫자 범위인 경우 (예: 600, 700)
      return "${allNumbers[0]}~${allNumbers[1]}kcal";
    } else if (allNumbers.isNotEmpty) {
      // 단일 숫자인 경우 결과 조절
      final val = int.tryParse(allNumbers[0]) ?? 0;
      if (val > 100) return "${val - 50}~${val + 50}kcal";
    }

    return "측정 불가";
  }

  // 캐시 초기화 (선택적)
  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}
