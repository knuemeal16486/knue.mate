// 식단 칼로리(lib/gemini_service.dart) — 2026-11-26 점검.
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/gemini_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseCalorieRange — AI 응답 해석', () {
    test('정상 범위', () {
      expect(GeminiService.parseCalorieRange('650~750kcal'), '650~750kcal');
      expect(GeminiService.parseCalorieRange('**600 ~ 700 kcal**'), '600~700kcal');
    });
    test('쉼표가 있어도 숫자를 자르지 않는다(예전엔 "1~050kcal")', () {
      expect(GeminiService.parseCalorieRange('1,050~1,150kcal'), '1050~1150kcal');
    });
    test('순서가 뒤집혀도 작은 값이 앞', () {
      expect(GeminiService.parseCalorieRange('750~650kcal'), '650~750kcal');
    });
    test('숫자 하나면 ±50', () {
      expect(GeminiService.parseCalorieRange('약 700kcal'), '650~750kcal');
    });
    test('한 끼로 말이 안 되는 숫자는 무시, 못 찾으면 null', () {
      expect(GeminiService.parseCalorieRange('1인분 650~750kcal'), '650~750kcal');
      expect(GeminiService.parseCalorieRange('측정불가'), isNull);
      expect(GeminiService.parseCalorieRange(''), isNull);
    });
  });

  test('안내 줄은 셀 메뉴에서 뺀다', () {
    expect(GeminiService.menuKey(['백미밥', ' 된장국 ', '정보가 없습니다']), '백미밥|된장국');
    expect(GeminiService.menuKey(['미운영']), isNull);
    expect(GeminiService.menuKey(const []), isNull);
  });

  test('AI를 못 부르면 어림값에 "(추정)"을 붙이고, 저장하지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: '', isOptional: true); // 키 없음 = AI 못 부름
    GeminiService.clearCache();
    final r = await GeminiService.estimateCalories(['잡곡밥', '제육볶음', '된장국']);
    expect(GeminiService.isEstimate(r), isTrue);
    expect(r, endsWith('kcal (추정)'));
    // 다음에 카드를 열 때 추정값을 AI 값처럼 바로 띄우지 않는다.
    expect(await GeminiService.cachedCalories(['잡곡밥', '제육볶음', '된장국']), isNull);
  });

  test('한 번 계산해 둔 메뉴는 기기에서 바로 꺼낸다(네트워크 없이)', () async {
    SharedPreferences.setMockInitialValues({
      'calorie_local_cache_v1': jsonEncode({'잡곡밥|제육볶음': '700~800kcal'}),
    });
    GeminiService.clearCache();
    expect(await GeminiService.cachedCalories(['잡곡밥', '제육볶음']), '700~800kcal');
    expect(await GeminiService.estimateCalories(['잡곡밥', '제육볶음']), '700~800kcal');
    expect(await GeminiService.cachedCalories(['잡곡밥', '김치']), isNull);
  });

  group('geminiResponseText — 모르는 필드가 와도 글자만 꺼낸다', () {
    test('보통 응답', () {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '650~750kcal'}
              ],
              'role': 'model'
            },
            'finishReason': 'STOP',
            'safetyRatings': [
              {'category': 'HARM_CATEGORY_CIVIC_INTEGRITY', 'probability': 'NEGLIGIBLE'}
            ],
          }
        ],
        'usageMetadata': {'promptTokenCount': 10, 'thoughtsTokenCount': 30},
        'modelVersion': 'gemini-3.8-flash',
      });
      expect(GeminiService.geminiResponseText(body), '650~750kcal');
    });
    test('생각 조각·서명 조각은 건너뛴다', () {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '메뉴를 보니...', 'thought': true},
                {'thoughtSignature': 'abc'},
                {'text': '700~800kcal', 'thoughtSignature': 'def'},
              ]
            },
            'finishReason': 'NEW_REASON_2026',
          }
        ],
      });
      expect(GeminiService.geminiResponseText(body), '700~800kcal');
    });
    test('후보가 없거나 깨진 응답이면 빈 글자', () {
      expect(GeminiService.geminiResponseText('{"promptFeedback":{"blockReason":"OTHER"}}'), '');
      expect(GeminiService.geminiResponseText('not json'), '');
    });
  });

  test('예전에 종료된 모델 이름을 쓰지 않는다', () {
    expect(GeminiService.kCalorieModels, isNot(contains('gemini-1.5-flash')));
  });
}
