import 'package:cloud_firestore/cloud_firestore.dart';
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

    final existing = await FirebaseFirestore.instance
        .collection('meal_ratings')
        .where('fingerPrint', isEqualTo: fingerPrint)
        .where('date', isEqualTo: dateStr)
        .where('source', isEqualTo: source.name)
        .where('mealType', isEqualTo: type.stdKey)
        .get();

    if (existing.docs.isNotEmpty) {
      await prefs.setBool(localKey, true);
      return "이미 참여하셨습니다. (중복 방지 정책)";
    }

    await FirebaseFirestore.instance.collection('meal_ratings').add({
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

    await prefs.setBool(localKey, true);
    return null;
  }
}
