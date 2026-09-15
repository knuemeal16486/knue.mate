import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:knue_mate/sponsor_model.dart';

Sponsor make({
  SponsorCategory category = SponsorCategory.etc,
  SponsorPlacement placement = SponsorPlacement.all,
  bool isActive = true,
  DateTime? startDate,
  DateTime? endDate,
}) => Sponsor(
      id: 'x',
      title: '제목',
      subtitle: '설명',
      callToAction: '자세히 보기',
      category: category,
      imageUrl: null,
      targetUrl: null,
      placement: placement,
      priority: 0,
      isActive: isActive,
      startDate: startDate,
      endDate: endDate,
    );

void main() {
  group('SponsorCategory', () {
    test('저장값으로 왕복한다', () {
      for (final c in SponsorCategory.values) {
        expect(SponsorCategory.fromKey(c.key), c);
      }
    });

    test('모르는 값은 기타가 된다', () {
      expect(SponsorCategory.fromKey(null), SponsorCategory.etc);
      expect(SponsorCategory.fromKey('없는값'), SponsorCategory.etc);
    });
  });

  group('SponsorPlacement', () {
    test('저장값으로 왕복한다', () {
      for (final p in SponsorPlacement.values) {
        expect(SponsorPlacement.fromKey(p.key), p);
      }
    });

    test('모르는 값은 전체 탭이 된다', () {
      expect(SponsorPlacement.fromKey(null), SponsorPlacement.all);
      expect(SponsorPlacement.fromKey('없는값'), SponsorPlacement.all);
    });
  });

  group('Firestore 직렬화', () {
    test('종료일은 그 날 자정이 아니라 하루가 끝나는 시각으로 저장된다', () {
      // Timestamp를 자정 그대로 저장하면 KnueNativeAdCard._isAdValid가
      // (문자열 날짜와 달리) 보정하지 않아서 종료일 당일 새벽부터 광고가
      // 꺼져버린다. toFirestore가 쓰는 시점에 미리 23:59:59로 굽는다.
      final s = make(endDate: DateTime(2026, 5, 20));
      final data = s.toFirestore();
      final baked = (data['endDate'] as Timestamp).toDate();
      expect(baked, DateTime(2026, 5, 20, 23, 59, 59));
    });

    test('시작일은 그대로 자정으로 저장된다 (그 날 아침부터 유효)', () {
      final s = make(startDate: DateTime(2026, 5, 20));
      final data = s.toFirestore();
      final baked = (data['startDate'] as Timestamp).toDate();
      expect(baked, DateTime(2026, 5, 20));
    });

    test('기간 제한이 없으면 null로 저장된다', () {
      final data = make().toFirestore();
      expect(data['startDate'], isNull);
      expect(data['endDate'], isNull);
    });

    test('Timestamp·문자열 날짜 둘 다 읽는다 (기존 seed 스크립트 호환)', () {
      final fromTimestamp = Sponsor.fromFirestore('a', {
        'title': 't',
        'startDate': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });
      expect(fromTimestamp.startDate, DateTime(2026, 3, 1));

      final fromString = Sponsor.fromFirestore('b', {
        'title': 't',
        'startDate': '2026-03-01',
      });
      expect(fromString.startDate, DateTime(2026, 3, 1));
    });

    test('아이콘 필드로 카테고리를 복원한다', () {
      final s = Sponsor.fromFirestore('a', {'title': 't', 'icon': 'cafe'});
      expect(s.category, SponsorCategory.cafe);
    });
  });

  group('isCurrentlyValid', () {
    final now = DateTime(2026, 5, 20, 12, 0);

    test('비활성이면 기간과 상관없이 무효', () {
      expect(make(isActive: false).isCurrentlyValid(now), isFalse);
    });

    test('기간 제한이 없으면 활성 상태만으로 유효', () {
      expect(make().isCurrentlyValid(now), isTrue);
    });

    test('시작 전에는 무효, 끝난 뒤에는 무효', () {
      final before = make(startDate: DateTime(2026, 6, 1));
      expect(before.isCurrentlyValid(now), isFalse);

      final after = make(
        endDate: DateTime(2026, 5, 19, 23, 59, 59),
      );
      expect(after.isCurrentlyValid(now), isFalse);
    });

    test('기간 안이면 유효', () {
      final within = make(
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 31, 23, 59, 59),
      );
      expect(within.isCurrentlyValid(now), isTrue);
    });
  });
}
