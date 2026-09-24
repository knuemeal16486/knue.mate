import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'meal_rating.dart';

/// 별점 제출과 "이미 평가함" 로컬/서버 중복 방지를 한 곳에 모은다.
///
/// meal_screen.dart의 식단 상세 카드와 meal_reminder.dart의 "식사하셨나요?"
/// 알림 팝업 둘 다 여기를 통해 제출한다 — 중복 방지 키가 어긋나면 한쪽에서
/// 평가해도 다른 쪽에서 또 평가할 수 있게 된다.
class MealRatingService {
  MealRatingService._();

  static String ratingPath({
    required MealSource source,
    required MealType type,
    required DateTime date,
  }) {
    final dateStr = _dateStr(date);
    return "ratings_${source.name}_${type.stdKey}_$dateStr";
  }

  static String _dateStr(DateTime date) =>
      "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

  /// 이 끼니에 이미 별점을 남겼는지(로컬 기기 기준).
  static Future<bool> alreadyRated({
    required MealSource source,
    required MealType type,
    required DateTime date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final path = ratingPath(source: source, type: type, date: date);
    return prefs.getBool("rated_$path") ?? false;
  }

  /// 결과: null이면 성공, 아니면 사용자에게 보여줄 안내 메시지.
  static Future<String?> submit({
    required MealSource source,
    required MealType type,
    required DateTime date,
    required double rating,
    ServingStyle? style,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final path = ratingPath(source: source, type: type, date: date);
    final localKey = "rated_$path";

    if (prefs.getBool(localKey) ?? false) {
      return "이미 이 식단에 별점을 남기셨어요! ✨";
    }

    String? fingerPrint = prefs.getString('user_fingerprint');
    if (fingerPrint == null) {
      fingerPrint = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString('user_fingerprint', fingerPrint);
    }

    final dateStr = _dateStr(date);

    // 서버 중복 확인은 **보조 수단**이다. 같은 기기의 재투표는 위 로컬
    // 플래그가 이미 막았고, 이 조회가 더 잡아내는 경우는 앱을 지웠다 깔았거나
    // 저장소가 비워진 때뿐이다. 그 드문 경우 때문에 모두를 기다리게 할 이유가
    // 없어서 시간을 끊는다 — 못 물어봤으면 그냥 통과시킨다.
    //
    // 예전엔 시간 제한도 catch도 없었다. 이 조회가 늦어지거나 실패하면
    // (4중 equality라 복합 인덱스에 기대고 있다) 그대로 예외가 위로 튀어,
    // "식사하셨나요?" 팝업의 스피너가 멈추지 않았다.
    try {
      final existing = await FirebaseFirestore.instance
          .collection('meal_ratings')
          .where('fingerPrint', isEqualTo: fingerPrint)
          .where('date', isEqualTo: dateStr)
          .where('source', isEqualTo: source.name)
          .where('mealType', isEqualTo: type.stdKey)
          .get()
          .timeout(const Duration(seconds: 3));

      if (existing.docs.isNotEmpty) {
        await prefs.setBool(localKey, true);
        return "이미 참여하셨습니다. (중복 방지 정책)";
      }
    } on TimeoutException {
      debugPrint('MealRatingService: 중복 확인이 느려 건너뛴다');
    } catch (e) {
      debugPrint('MealRatingService: 중복 확인 실패: $e');
    }

    // 쓰기는 **기다리지 않는다.**
    //
    // Firestore는 로컬 캐시에 먼저 적고 서버에는 알아서 따라 보낸다. 그래서
    // 화면(같은 컬렉션을 보는 StreamBuilder)에는 이미 반영돼 보이고, 신호가
    // 끊겨 있어도 다음에 연결될 때 올라간다. 서버 응답까지 기다리면 그동안
    // 스피너만 도는데, 기다려서 얻는 게 없다.
    final write = FirebaseFirestore.instance.collection('meal_ratings').add({
      'fingerPrint': fingerPrint,
      'date': dateStr,
      'source': source.name,
      'mealType': type.stdKey,
      'rating': rating,
      // 고르지 않았으면 필드 자체를 넣지 않는다 — 집계에서 "무응답"과
      // "빈 문자열 응답"을 구분할 필요가 없어진다.
      if (style != null) 'servingStyle': style.key,
      'createdAt': FieldValue.serverTimestamp(),
    });
    unawaited(
      write.then<void>(
        (_) {},
        onError: (Object e) => debugPrint('MealRatingService: 전송 실패: $e'),
      ),
    );

    await prefs.setBool(localKey, true);
    return null;
  }
}
