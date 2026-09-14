// 이번 배치에서 추가한 순수 로직 검증.
//  - 인사말 무작위 선택
//  - 학사일정 종류 분류
//  - 식단 평가 집계(별점 + 배식 방식 투표)
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/meal_rating.dart';
import 'package:knue_mate/notice_model.dart';

void main() {
  group('인사말', () {
    test('모든 시간대가 문구를 갖고 있고 중복이 없다', () {
      for (final entry in kGreetings.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} 비어있음');
        expect(entry.value.toSet().length, entry.value.length,
            reason: '${entry.key} 안에 중복 문구');
      }
    });

    test('시간대마다 문구가 2개 이상이어서 매번 달라질 여지가 있다', () {
      // 하나뿐이면 "접속할 때마다 다르게"가 성립하지 않는다.
      for (final entry in kGreetings.entries) {
        expect(entry.value.length, greaterThanOrEqualTo(2),
            reason: '${entry.key}는 ${entry.value.length}개뿐');
      }
    });

    test('고른 문구는 그 시간대 풀 안에 있다', () {
      final cases = {
        2: 'dawn',
        8: 'morning',
        12: 'lunch',
        16: 'afternoon',
        20: 'evening',
        23: 'night',
      };
      cases.forEach((hour, slot) {
        for (var seed = 0; seed < 20; seed++) {
          final g = pickGreeting(DateTime(2026, 8, 19, hour),
              random: Random(seed));
          expect(kGreetings[slot]!.contains(g), isTrue,
              reason: '$hour시 → "$g" 가 $slot 풀에 없음');
        }
      });
    });

    test('하루 24시간 어디서든 예외 없이 문구가 나온다', () {
      for (var h = 0; h < 24; h++) {
        expect(pickGreeting(DateTime(2026, 1, 1, h)), isNotEmpty);
      }
    });

    test('여러 번 뽑으면 실제로 서로 다른 문구가 나온다', () {
      final seen = <String>{};
      for (var seed = 0; seed < 50; seed++) {
        seen.add(pickGreeting(DateTime(2026, 8, 19, 16), random: Random(seed)));
      }
      expect(seen.length, greaterThan(1), reason: '늘 같은 문구만 나온다');
    });
  });

  group('학사일정 종류 분류', () {
    test('키워드로 종류를 가려낸다', () {
      expect(AcademicEventKind.of('1학기 기말고사'), AcademicEventKind.exam);
      expect(AcademicEventKind.of('수강신청 기간'), AcademicEventKind.registration);
      expect(AcademicEventKind.of('여름방학 시작'), AcademicEventKind.breakTime);
      expect(AcademicEventKind.of('학위수여식 및 졸업식'), AcademicEventKind.ceremony);
      expect(AcademicEventKind.of('2학기 개강'), AcademicEventKind.term);
    });

    test('어느 키워드에도 안 걸리면 기타로 떨어진다', () {
      expect(AcademicEventKind.of('총장배 바둑대회'), AcademicEventKind.other);
      expect(AcademicEventKind.of(''), AcademicEventKind.other);
    });

    test('더 구체적인 종류가 먼저 잡힌다', () {
      // "기말고사 기간"은 '고사'(시험)이자 '기간'이지만 시험이어야 한다.
      expect(AcademicEventKind.of('기말고사 기간'), AcademicEventKind.exam);
      // "등록금 납부"는 학기가 아니라 수강·등록이어야 한다.
      expect(AcademicEventKind.of('등록금 납부 기간'), AcademicEventKind.registration);
    });

    test('종류마다 잉크 인덱스가 서로 달라 색이 겹치지 않는다', () {
      final idx = AcademicEventKind.values.map((k) => k.inkIndex).toList();
      expect(idx.toSet().length, idx.length);
    });

    test('CalendarEvent가 제목으로 종류를 알려준다', () {
      final e = CalendarEvent(
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 5),
        title: '기말고사',
      );
      expect(e.kind, AcademicEventKind.exam);
    });
  });

  group('식단 평가 집계', () {
    test('평가가 없으면 빈 집계다', () {
      final s = MealRatingSummary.fromDocs(const []);
      expect(s.hasRatings, isFalse);
      expect(s.average, 0);
      expect(s.majorityStyle, isNull);
    });

    test('평균과 참여자 수를 센다', () {
      final s = MealRatingSummary.fromDocs([
        {'rating': 5},
        {'rating': 4},
        {'rating': 3.0},
      ]);
      expect(s.count, 3);
      expect(s.average, closeTo(4.0, 1e-9));
    });

    test('별점이 없는 문서는 평균을 끌어내리지 않는다', () {
      // 배식 방식만 투표한 문서가 섞여도 평균이 0으로 가면 안 된다.
      final s = MealRatingSummary.fromDocs([
        {'rating': 4},
        {'servingStyle': 'self'},
        {'rating': null},
      ]);
      expect(s.count, 1);
      expect(s.average, 4.0);
      expect(s.selfVotes, 1);
    });

    test('배식 방식 투표를 센다', () {
      final s = MealRatingSummary.fromDocs([
        {'rating': 5, 'servingStyle': 'self'},
        {'rating': 4, 'servingStyle': 'self'},
        {'rating': 3, 'servingStyle': 'fixed'},
        {'rating': 2},
      ]);
      expect(s.selfVotes, 2);
      expect(s.fixedVotes, 1);
      expect(s.styleVotes, 3);
      expect(s.majorityStyle, ServingStyle.self);
      expect(s.majorityRatio, closeTo(2 / 3, 1e-9));
    });

    test('표가 같으면 한쪽으로 단정하지 않는다', () {
      final s = MealRatingSummary.fromDocs([
        {'rating': 5, 'servingStyle': 'self'},
        {'rating': 3, 'servingStyle': 'fixed'},
      ]);
      expect(s.majorityStyle, isNull, reason: '동수인데 한쪽을 골랐다');
    });

    test('모르는 servingStyle 값은 무시한다', () {
      final s = MealRatingSummary.fromDocs([
        {'rating': 5, 'servingStyle': 'buffet'}, // 예전/오타 값
        {'rating': 5, 'servingStyle': 'self'},
      ]);
      expect(s.styleVotes, 1);
      expect(s.majorityStyle, ServingStyle.self);
    });

    test('저장 키가 enum 이름 변경에 흔들리지 않게 고정돼 있다', () {
      // Firestore에 이미 쌓인 값이라 함부로 바꾸면 과거 투표가 사라진다.
      expect(ServingStyle.self.key, 'self');
      expect(ServingStyle.fixed.key, 'fixed');
      expect(ServingStyle.fromKey('self'), ServingStyle.self);
      expect(ServingStyle.fromKey(null), isNull);
    });
  });
}
