/// 식단 평가 모델.
///
/// 별점은 Firestore `meal_ratings` 컬렉션에 **사용자 한 명당 문서 하나**로
/// 쌓인다(fingerPrint로 중복 방지). 평균·참여자 수는 그 문서들을 모아 계산한다.
///
/// 여기에는 Firestore를 모르는 순수 로직만 둔다 — 집계 규칙을 화면이나 서비스
/// 코드에 섞지 않고 테스트할 수 있게 하기 위해서다.
library;

/// 메인 반찬(보통 고기)의 배식 방식.
///
/// 같은 메뉴라도 자율배식이면 원하는 만큼 먹을 수 있고 정량배식이면 정해진
/// 양만 나온다. 식당에 가기 전에 가장 궁금해하는 정보라 별점과 함께 투표받는다.
enum ServingStyle {
  /// 원하는 만큼 덜어 먹는 방식.
  self('자율배식', 'self'),

  /// 1인분씩 정해진 양이 나오는 방식.
  fixed('정량배식', 'fixed');

  /// 화면에 보여줄 이름.
  final String label;

  /// Firestore에 저장하는 값. enum 이름을 바꿔도 저장값이 흔들리지 않게 분리한다.
  final String key;

  const ServingStyle(this.label, this.key);

  /// 저장값 → enum. 모르는 값이면 null(투표 안 함).
  static ServingStyle? fromKey(String? key) {
    if (key == null) return null;
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// 한 끼니에 대한 평가 집계.
class MealRatingSummary {
  /// 평균 별점 (참여자가 없으면 0).
  final double average;

  /// 별점 참여자 수.
  final int count;

  /// 자율배식이라고 답한 사람 수.
  final int selfVotes;

  /// 정량배식이라고 답한 사람 수.
  final int fixedVotes;

  const MealRatingSummary({
    required this.average,
    required this.count,
    required this.selfVotes,
    required this.fixedVotes,
  });

  static const empty = MealRatingSummary(
    average: 0,
    count: 0,
    selfVotes: 0,
    fixedVotes: 0,
  );

  bool get hasRatings => count > 0;

  /// 배식 방식 투표 총수.
  int get styleVotes => selfVotes + fixedVotes;

  /// 더 많이 선택된 배식 방식. 표가 없거나 동수면 null —
  /// 동수일 때 한쪽을 고르면 잘못된 정보를 확신처럼 보여주게 된다.
  ServingStyle? get majorityStyle {
    if (styleVotes == 0 || selfVotes == fixedVotes) return null;
    return selfVotes > fixedVotes ? ServingStyle.self : ServingStyle.fixed;
  }

  /// 다수 의견의 비율(0~1). 표가 없으면 0.
  double get majorityRatio {
    if (styleVotes == 0) return 0;
    final top = selfVotes > fixedVotes ? selfVotes : fixedVotes;
    return top / styleVotes;
  }

  /// 평가 문서 묶음에서 집계를 만든다.
  ///
  /// 문서에 `rating`(숫자)과 선택적으로 `servingStyle`(문자열)이 들어 있다.
  /// 별점이 없거나 숫자가 아닌 문서는 평균 계산에서 제외한다 — 예전 스키마나
  /// 배식 방식만 투표한 문서가 섞여도 평균이 0으로 끌려가지 않게 하기 위해서다.
  factory MealRatingSummary.fromDocs(Iterable<Map<String, dynamic>> docs) {
    var sum = 0.0;
    var count = 0;
    var selfVotes = 0;
    var fixedVotes = 0;

    for (final d in docs) {
      final raw = d['rating'];
      if (raw is num) {
        sum += raw.toDouble();
        count++;
      }
      switch (ServingStyle.fromKey(d['servingStyle'] as String?)) {
        case ServingStyle.self:
          selfVotes++;
        case ServingStyle.fixed:
          fixedVotes++;
        case null:
          break;
      }
    }

    return MealRatingSummary(
      average: count == 0 ? 0 : sum / count,
      count: count,
      selfVotes: selfVotes,
      fixedVotes: fixedVotes,
    );
  }
}
