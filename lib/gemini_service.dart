import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 식단 칼로리 어림(Gemini).
///
/// 순서: 메모리 → 기기 저장(한 번 계산한 메뉴는 버튼 없이 바로 띄운다) → Firestore 공용 캐시
/// (모든 사용자 공유) → Gemini. Gemini가 실패하면 메뉴 이름으로 어림한 값에 "(추정)"을 붙인다 —
/// AI 결과처럼 보이면 안 된다(2026-11-26). 추정값은 어디에도 저장하지 않아 다음에 다시 AI를 시도한다.
class GeminiService {
  // .env에서 키를 안전하게 가져오기
  static String get apiKey {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      debugPrint("⚠️ GEMINI_API_KEY가 .env 파일에 설정되지 않았습니다.");
      return "";
    }
    return key;
  }

  /// 앞에서부터 시도한다(Google 모델 문서 기준 2026-11-26). 예전 'gemini-1.5-flash'는 2025-09에
  /// 종료돼 호출이 매번 실패했고, 사용자는 어림값을 AI 결과로 보고 있었다.
  /// - gemini-3.8-flash: 지금 Stable Flash(2026-09 출시, 종료일 없음)
  /// - gemini-flash-latest: 최신 Flash를 가리키는 별칭 — 위 모델이 종료돼도 이름을 안 고쳐도 된다
  /// - gemini-3.5-flash-lite: 예비
  /// gemini-2.5-flash는 2026-12-01 종료 예정이라 넣지 않는다. 모델이 종료되면 여기만 고친다.
  @visibleForTesting
  static const kCalorieModels = [
    'gemini-3.8-flash',
    'gemini-flash-latest',
    'gemini-3.5-flash-lite',
  ];

  /// 이 실행에서 404 등으로 실패한 모델 — 다시 부르지 않는다.
  static final Set<String> _deadModels = {};

  /// Gemini REST(generateContent). 예전엔 google_generative_ai 패키지(0.4.7, 개발 중단)를 썼는데,
  /// 응답에 모르는 값(새 안전 분류·생각 서명 조각 등)이 오면 파싱 예외를 던져 새 모델에서 깨진다.
  /// 글자만 꺼내면 되므로 직접 부른다. 실패하면 상태 코드를 담아 던진다.
  static Future<String> _generate(String model, String prompt) async {
    final uri = Uri.https('generativelanguage.googleapis.com',
        '/v1beta/models/$model:generateContent');
    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              // 음식 이름에 의한 불필요한 필터링 방지
              'safetySettings': [
                for (final c in [
                  'HARM_CATEGORY_HARASSMENT',
                  'HARM_CATEGORY_HATE_SPEECH',
                  'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                  'HARM_CATEGORY_DANGEROUS_CONTENT',
                ])
                  {'category': c, 'threshold': 'BLOCK_NONE'}
              ],
            }))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw GeminiHttpException(res.statusCode, res.body);
    }
    return geminiResponseText(utf8.decode(res.bodyBytes));
  }

  /// 응답 JSON → 첫 후보의 글자 조각을 이은 것. 모르는 필드는 무시한다(순수 함수 — 테스트 대상).
  @visibleForTesting
  static String geminiResponseText(String body) {
    try {
      final json = jsonDecode(body);
      final candidates = (json is Map ? json['candidates'] : null) as List?;
      if (candidates == null || candidates.isEmpty) return '';
      final content = (candidates.first as Map)['content'];
      final parts = (content is Map ? content['parts'] : null) as List?;
      if (parts == null) return '';
      return parts
          .whereType<Map>()
          .where((p) => p['thought'] != true) // 생각 요약 조각은 답이 아니다
          .map((p) => p['text'])
          .whereType<String>()
          .join();
    } catch (_) {
      return '';
    }
  }

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // 인메모리 캐시 (앱 세션 내 중복 조회 방지)
  static final Map<String, String> _cache = {};

  /// 기기에 둔 계산 결과(메뉴 키 → "650~750kcal"). 최근 [_kLocalMax]개만.
  static const _kLocalKey = 'calorie_local_cache_v1';
  static const _kLocalMax = 300;

  /// 어림값 표시. 화면·공유 글에 그대로 나간다.
  static const kEstimateSuffix = ' (추정)';
  static bool isEstimate(String? s) => s != null && s.endsWith(kEstimateSuffix);

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

  /// 칼로리를 셀 메뉴만 — "없음"·"미운영"·"정보가 없습니다" 같은 안내 줄은 뺀다.
  @visibleForTesting
  static List<String> validMenuItems(List<String> menuItems) => menuItems
      .map((e) => e.trim())
      .where((t) =>
          t.isNotEmpty &&
          !t.contains("없음") &&
          !t.contains("미운영") &&
          !t.contains("정보가"))
      .toList();

  /// 메뉴 묶음의 캐시 키. 셀 메뉴가 없으면 null.
  static String? menuKey(List<String> menuItems) {
    final valid = validMenuItems(menuItems);
    return valid.isEmpty ? null : valid.join('|');
  }

  /// 네트워크 없이 — 이미 계산해 둔 값만(메모리·기기). 식단 카드가 열릴 때 버튼 없이 바로 띄운다.
  static Future<String?> cachedCalories(List<String> menuItems) async {
    final key = menuKey(menuItems);
    if (key == null) return null;
    final mem = _cache[key];
    if (mem != null && !isEstimate(mem)) return mem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = _readLocal(prefs)[key];
      if (local != null) _cache[key] = local;
      return local;
    } catch (e) {
      debugPrint('칼로리 기기 캐시 읽기 실패: $e');
      return null;
    }
  }

  static Map<String, String> _readLocal(SharedPreferences prefs) {
    final raw = prefs.getString(_kLocalKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {}; // 깨진 값이면 새로 쌓는다
    }
  }

  static Future<void> _saveLocal(String key, String calories) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _readLocal(prefs)
        ..remove(key)
        ..[key] = calories; // 맨 뒤 = 가장 최근
      while (map.length > _kLocalMax) {
        map.remove(map.keys.first);
      }
      await prefs.setString(_kLocalKey, jsonEncode(map));
    } catch (e) {
      debugPrint('칼로리 기기 캐시 저장 실패: $e');
    }
  }

  // 메뉴 리스트로 칼로리 예상하기
  static Future<String> estimateCalories(List<String> menuItems) async {
    final validItems = validMenuItems(menuItems);
    if (validItems.isEmpty) return "";
    final cacheKey = validItems.join('|');

    // 1. 메모리·기기 (추정값은 다시 AI를 시도한다)
    final cached = await cachedCalories(menuItems);
    if (cached != null && !isEstimate(cached)) return cached;

    // 2. Firestore 캐시 확인 (모든 사용자 공유)
    try {
      final doc = await _firestore
          .collection('calorie_cache')
          .doc(_docKey(cacheKey))
          .get()
          .timeout(const Duration(seconds: 3));
      if (doc.exists) {
        final calories = doc.data()?['calories'] as String?;
        if (calories != null && calories.isNotEmpty && !isEstimate(calories)) {
          _cache[cacheKey] = calories;
          await _saveLocal(cacheKey, calories);
          return calories;
        }
      }
    } catch (e) {
      debugPrint('gemini_service 칼로리 캐시 읽기 실패: $e');
    }

    // 3. Gemini API 호출 (그 메뉴의 첫 사용자만)
    final ai = await _askGemini(validItems);
    if (ai != null) {
      // 4. Firestore에 저장 (이후 사용자들은 여기서 읽음)
      _firestore.collection('calorie_cache').doc(_docKey(cacheKey)).set({
        'calories': ai,
        'menu': cacheKey,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((e) => debugPrint('칼로리 공용 캐시 저장 실패: $e'));
      _cache[cacheKey] = ai;
      await _saveLocal(cacheKey, ai);
      return ai;
    }

    // 실패하면 메뉴 이름으로 어림 — "(추정)"을 붙여 AI 값과 구분하고, 저장하지 않는다.
    final fallback = fallbackCalories(validItems) + kEstimateSuffix;
    _cache[cacheKey] = fallback;
    return fallback;
  }

  /// 모델을 차례로 시도해 "숫자~숫자kcal"을 얻는다. 모두 실패하면 null.
  static Future<String?> _askGemini(List<String> validItems) async {
    if (apiKey.isEmpty) return null;
    final prompt = _buildPrompt(validItems);
    for (final name in kCalorieModels) {
      if (_deadModels.contains(name)) continue;
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final text = await _generate(name, prompt);
          final parsed = parseCalorieRange(text);
          if (parsed != null) return parsed;
        } on GeminiHttpException catch (e) {
          debugPrint("Gemini $name 오류 (시도 $attempt): $e");
          // 없는 모델(404)·잘못된 요청(400)·권한(403)은 다시 해도 같다 — 다음 모델로.
          if (e.status == 400 || e.status == 403 || e.status == 404) {
            _deadModels.add(name);
            break;
          }
        } catch (e) {
          debugPrint("Gemini $name 오류 (시도 $attempt): $e");
        }
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    return null;
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
    숫자에 쉼표를 쓰지 마십시오.
    최대 칼로리는 1000kcal를 넘지 않습니다.
    다른 어떤 설명이나 텍스트도 포함하지 마십시오. 오직 칼로리 범위만 출력하십시오.
    """;
  }

  /// AI 응답 → "650~750kcal". 숫자를 못 찾으면 null(어림값으로 넘어간다).
  /// 쉼표를 먼저 지운다 — "1,050~1,150kcal"을 예전엔 "1~050kcal"로 읽었다.
  /// 한 끼로 말이 안 되는 숫자(100 미만·3000 초과)는 무시한다.
  @visibleForTesting
  static String? parseCalorieRange(String raw) {
    final clean = raw.replaceAll(RegExp(r'(?<=\d),(?=\d{3})'), '');
    final nums = RegExp(r'\d+')
        .allMatches(clean)
        .map((m) => int.parse(m.group(0)!))
        .where((v) => v >= 100 && v <= 3000)
        .toList();
    if (nums.length >= 2) {
      final lo = nums[0] < nums[1] ? nums[0] : nums[1];
      final hi = nums[0] < nums[1] ? nums[1] : nums[0];
      return "$lo~${hi}kcal";
    }
    if (nums.length == 1) return "${nums[0] - 50}~${nums[0] + 50}kcal";
    return null;
  }

  /// 예측 실패나 API 장애 시 메뉴 이름으로 대강 어림한다(표시할 땐 [kEstimateSuffix]를 붙인다).
  @visibleForTesting
  static String fallbackCalories(List<String> validItems) {
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
    return "$startRange~${startRange + 100}kcal";
  }

  static void clearCache() => _cache.clear();
}

/// Gemini가 200이 아닌 응답을 줬을 때. 본문은 앞부분만(키가 섞이지 않게 요청 쪽은 담지 않는다).
class GeminiHttpException implements Exception {
  final int status;
  final String body;
  GeminiHttpException(this.status, this.body);
  @override
  String toString() =>
      'Gemini HTTP $status: ${body.length > 200 ? body.substring(0, 200) : body}';
}
