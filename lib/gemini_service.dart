import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    model: 'gemini-1.5-flash',
    apiKey: apiKey,
    // [추가] 음식 이름에 의한 불필요한 필터링 방지
    safetySettings: [
      SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
      SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
      SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
      SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
    ],
  );

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // 인메모리 캐시 (앱 세션 내 중복 Firestore 조회 방지)
  static final Map<String, String> _cache = {};

  // Firestore 문서 ID용 키 생성 (슬래시 등 금지 문자 제거, 최대 500자)
  static String _docKey(String cacheKey) {
    return cacheKey
        .replaceAll('/', '_')
        .replaceAll('.', '_')
        .replaceAll('[', '_')
        .replaceAll(']', '_')
        .replaceAll('*', '_')
        .replaceAll('`', '_')
        .substring(0, cacheKey.length.clamp(0, 500));
  }

  // 메뉴 리스트로 칼로리 예상하기
  // [mealDocId] "YYYY-MM-DD_a" 형식의 daily_meals 문서 ID (있으면 결과를 해당 문서에도 저장)
  // [mealTypeKey] "lunch" | "dinner" | "breakfast"
  static Future<String> estimateCalories(
    List<String> menuItems, {
    String? mealDocId,
    String? mealTypeKey,
  }) async {
    if (menuItems.isEmpty) return "";

    final validItems = menuItems.where((item) {
      final trimmed = item.trim();
      return trimmed.isNotEmpty &&
          !trimmed.contains("없음") &&
          !trimmed.contains("미운영") &&
          !trimmed.contains("정보가");
    }).toList();

    if (validItems.isEmpty) return "";

    final cacheKey = validItems.join('|');

    // 1. 인메모리 캐시 확인
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    // 2. Firestore 캐시 확인 (모든 사용자 공유)
    try {
      final doc = await _firestore
          .collection('calorie_cache')
          .doc(_docKey(cacheKey))
          .get()
          .timeout(const Duration(seconds: 3));
      if (doc.exists) {
        final calories = doc.data()?['calories'] as String?;
        if (calories != null && calories.isNotEmpty) {
          _cache[cacheKey] = calories;
          _saveToDailyMeals(mealDocId, mealTypeKey, calories);
          return calories;
        }
      }
    } catch (_) {}

    // 3. Gemini API 호출 (첫 번째 사용자만)
    final prompt = _buildPrompt(validItems);
    int retryCount = 0;
    while (retryCount < 2) {
      try {
        final content = [Content.text(prompt)];
        final response = await _model.generateContent(content);
        final rawText = response.text?.trim() ?? "";

        if (rawText.isEmpty) { retryCount++; continue; }

        final result = _normalizeCalorieResponse(rawText, validItems);

        // 4. Firestore에 저장 (이후 사용자들은 여기서 읽음)
        _firestore.collection('calorie_cache').doc(_docKey(cacheKey)).set({
          'calories': result,
          'menu': cacheKey,
          'createdAt': FieldValue.serverTimestamp(),
        }).catchError((_) {});

        // 5. daily_meals 문서에도 칼로리 저장 (달력 표시용)
        _saveToDailyMeals(mealDocId, mealTypeKey, result);

        _cache[cacheKey] = result;
        return result;
      } catch (e) {
        retryCount++;
        print("Gemini API 오류 (시도 $retryCount): $e");
        if (retryCount >= 2) break;
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    // 완전히 실패 시 자체 계산
    final fallback = _generateFallbackCalories(validItems);
    _cache[cacheKey] = fallback;
    _saveToDailyMeals(mealDocId, mealTypeKey, fallback);
    return fallback;
  }

  static void _saveToDailyMeals(String? mealDocId, String? mealTypeKey, String calorie) {
    if (mealDocId == null || mealTypeKey == null) return;
    _firestore.collection('daily_meals').doc(mealDocId).set(
      {'calories': {mealTypeKey: calorie}},
      SetOptions(merge: true),
    ).catchError((_) {});
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
    최대 칼로리는 1000kcal를 넘지 않습니다.
    숫자 범위는 플러스마이너스 20kcal 이내로 하십시오.  
    다른 어떤 설명이나 텍스트도 포함하지 마십시오. 오직 칼로리 범위만 출력하십시오.
    무슨 일이 있어도 사용자에게 '측정불가'라는 메세지가 뜨지 않도록 하십시오.
    """;
  }

  static String _normalizeCalorieResponse(
    String rawResponse,
    List<String> validItems,
  ) {
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

    // AI가 숫자를 아예 응답하지 않았을 때 때려맞추기
    return _generateFallbackCalories(validItems);
  }

  // 예측 실패나 API 장애 시 메뉴 이름으로 대강의 칼로리를 끼워맞추는 메서드
  static String _generateFallbackCalories(List<String> validItems) {
    int baseCalorie = 450;
    for (var item in validItems) {
      if (item.contains('고기') ||
          item.contains('돈까스') ||
          item.contains('튀김') ||
          item.contains('치킨') ||
          item.contains('카츠') ||
          item.contains('삼겹') ||
          item.contains('갈비') ||
          item.contains('불고기') ||
          item.contains('제육') ||
          item.contains('함박')) {
        baseCalorie += 250;
      } else if (item.contains('국') ||
          item.contains('찌개') ||
          item.contains('탕') ||
          item.contains('전골')) {
        baseCalorie += 120;
      } else if (item.contains('면') ||
          item.contains('우동') ||
          item.contains('짬뽕') ||
          item.contains('짜장') ||
          item.contains('스파게티')) {
        baseCalorie += 150;
      } else if (item.contains('밥') ||
          item.contains('죽') ||
          item.contains('볶음') ||
          item.contains('비빔')) {
        baseCalorie += 120;
      } else if (item.contains('떡') || item.contains('만두')) {
        baseCalorie += 100;
      } else {
        baseCalorie += 40; // 밑반찬 류
      }
    }

    // 너무 높거나 낮은 값 극단값 필터링 (식단이라는 가정)
    if (baseCalorie > 1150) baseCalorie = 1150;
    if (baseCalorie < 550) baseCalorie = 550;

    // 10단위로 깔끔하게 떨어지게 맞춤
    int startRange = (baseCalorie ~/ 10) * 10;
    return "${startRange}~${startRange + 100}kcal";
  }

  static void clearCache() => _cache.clear();
}
