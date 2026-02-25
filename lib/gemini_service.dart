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
    model: 'gemini-2.0-flash',
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
    학식 전문 영양사로서 다음 메뉴의 총 칼로리를 추산해줘.
    
    메뉴: $menuString
    
    [출력 규칙]
    1. 20대 성인 기준 1인분 총 칼로리를 계산할 것.
    2. 반드시 '숫자~숫자kcal' 형식으로만 대답할 것 (예: 600~700kcal).
    3. 다른 미사여구나 설명은 절대 생략할 것.
    4. 정확한 계산이 어려우면 가장 근접한 범위를 제시할 것.
    """;
  }

  static String _normalizeCalorieResponse(String rawResponse) {
    // 1. 불필요한 특수문자 제거 (마크다운 등)
    String clean = rawResponse.replaceAll('*', '').replaceAll('#', '').trim();

    // 2. 숫자~숫자 kcal 패턴 (공백 허용)
    final rangeRegex = RegExp(
      r'(\d+)\s*[~-]\s*(\d+)\s*kcal',
      caseSensitive: false,
    );
    final rangeMatch = rangeRegex.firstMatch(clean);

    if (rangeMatch != null) {
      return "${rangeMatch.group(1)}~${rangeMatch.group(2)}kcal";
    }

    // 3. 단일 숫자 kcal 패턴 -> 범위로 자동 변환
    final singleRegex = RegExp(r'(\d+)\s*kcal', caseSensitive: false);
    final singleMatch = singleRegex.firstMatch(clean);

    if (singleMatch != null) {
      final value = int.tryParse(singleMatch.group(1)!) ?? 0;
      if (value > 0) {
        return "${value - 50}~${value + 50}kcal";
      }
    }

    // 4. 숫자 범위만 있는 경우 (kcal 생략 시)
    final numbersOnlyRegex = RegExp(
      r'(\d+)\s*[~-]\s*(\d+)',
      caseSensitive: false,
    );
    final numbersMatch = numbersOnlyRegex.firstMatch(clean);
    if (numbersMatch != null) {
      return "${numbersMatch.group(1)}~${numbersMatch.group(2)}kcal";
    }

    // 5. 텍스트 안에 숫자가 섞여 있는 경우 최후의 수단으로 숫자들만 추출
    final allNumbers = RegExp(
      r'\d+',
    ).allMatches(clean).map((m) => m.group(0)!).toList();
    if (allNumbers.length >= 2) {
      return "${allNumbers[0]}~${allNumbers[1]}kcal";
    } else if (allNumbers.length == 1) {
      final val = int.tryParse(allNumbers[0]) ?? 0;
      return "${val - 50}~${val + 50}kcal";
    }

    return "측정 불가";
  }

  // 캐시 초기화 (선택적)
  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}
