import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

HousingReport _r({
  int deposit = 500,
  int rent = 40,
  int? fee,
  HousingRoomType? roomType,
  List<String> features = const [],
}) =>
    HousingReport(
      buildingId: 'b1',
      deposit: deposit,
      monthlyRent: rent,
      maintenanceFee: fee,
      roomType: roomType,
      features: features,
      reportedAt: DateTime(2026, 9, 1),
    );

void main() {
  group('HousingSummary 집계', () {
    test('관리비는 적어 낸 제보만으로 중앙값을 낸다', () {
      // null을 0으로 치면 중앙값이 아래로 끌려가 "관리비 싼 집"처럼 보인다.
      final s = HousingSummary.from([
        _r(fee: 10),
        _r(fee: null),
        _r(fee: 10),
      ]);
      expect(s.medianMaintenance, 10);
    });

    test('아무도 관리비를 안 적었으면 null이고, 월 부담은 월세만', () {
      final s = HousingSummary.from([_r(rent: 35), _r(rent: 35)]);
      expect(s.medianMaintenance, isNull);
      expect(s.medianMonthlyTotal, 35);
    });

    test('월 부담은 제보마다 더한 뒤 중앙값을 낸다', () {
      final s = HousingSummary.from([_r(rent: 40, fee: 7), _r(rent: 40, fee: 7)]);
      expect(s.medianMonthlyTotal, 47);
    });

    test('두 중앙값을 더하지 않는다 — 모집단이 다르다', () {
      // medianRent는 전체 제보에서, medianMaintenance는 관리비를 적어 낸
      // 제보만에서 나온다. 더하면 5명 중 4명이 40을 내는 건물이 60으로
      // 잡혀 "월 50 이하" 검색에서 빠졌다.
      final s = HousingSummary.from([
        _r(rent: 40),
        _r(rent: 40),
        _r(rent: 40),
        _r(rent: 40),
        _r(rent: 40, fee: 20),
      ]);
      expect(s.medianRent, 40);
      expect(s.medianMaintenance, 20); // 적어 낸 건 한 건뿐
      expect(s.medianMonthlyTotal, 40, reason: '40+20=60이 되면 안 된다');
    });

    test('월 부담 중앙값으로 걸러진다', () {
      final s = HousingSummary.from([
        _r(rent: 40),
        _r(rent: 40),
        _r(rent: 40),
        _r(rent: 40),
        _r(rent: 40, fee: 20),
      ]);
      const f = HousingFilter(maxMonthly: 50, includeMaintenance: true);
      expect(housingMatchesFilter(s, f), isTrue);
    });

    test('방 구조는 다수결이 아니라 나온 것 전부를 들고 있는다', () {
      // 한 건물에 원룸과 2룸이 섞여 있으면 둘 다 후보로 잡혀야 한다.
      final s = HousingSummary.from([
        _r(roomType: HousingRoomType.oneRoom),
        _r(roomType: HousingRoomType.oneRoom),
        _r(roomType: HousingRoomType.twoRoom),
      ]);
      expect(s.roomTypes, {HousingRoomType.oneRoom, HousingRoomType.twoRoom});
    });

    test('allFeatures는 5개를 넘어도 전부 담는다', () {
      // topFeatures(상위 5개)로 거르면 6번째 특징이 조건에 영영 안 걸린다.
      final s = HousingSummary.from([
        _r(features: const ['풀옵션', '엘리베이터', '주차 가능', '베란다', '복층', '도시가스']),
      ]);
      expect(s.topFeatures.length, 5);
      expect(s.allFeatures, contains('도시가스'));
    });
  });

  group('housingMatchesFilter', () {
    HousingSummary sum({
      int? deposit = 500,
      int? rent = 40,
      int? fee,
      Set<HousingRoomType> types = const {},
      Set<String> features = const {},
    }) =>
        HousingSummary(
          reportCount: 3,
          medianDeposit: deposit,
          medianRent: rent,
          medianMaintenance: fee,
          // 제보가 전부 같은 값인 건물을 가정하므로 월 부담 중앙값도
          // 월세+관리비다. 실제 집계는 HousingSummary.from이 제보별로
          // 더한 뒤 중앙값을 낸다.
          medianMonthlyTotal: rent == null ? null : rent + (fee ?? 0),
          roomTypes: types,
          allFeatures: features,
          topFeatures: features.toList(),
          latestReport: DateTime(2026, 9, 1),
        );

    test('제보가 없는 건물은 어떤 조건에도 안 걸린다', () {
      expect(
        housingMatchesFilter(HousingSummary.empty, const HousingFilter()),
        isFalse,
      );
    });

    test('조건이 비면 제보 있는 건물은 모두 통과', () {
      expect(housingMatchesFilter(sum(), const HousingFilter()), isTrue);
    });

    test('방 구조가 하나라도 겹치면 통과', () {
      final s = sum(types: {HousingRoomType.oneRoom, HousingRoomType.twoRoom});
      expect(
        housingMatchesFilter(
          s,
          const HousingFilter(roomTypes: {HousingRoomType.twoRoom}),
        ),
        isTrue,
      );
      expect(
        housingMatchesFilter(
          s,
          const HousingFilter(roomTypes: {HousingRoomType.threeRoomPlus}),
        ),
        isFalse,
      );
    });

    test('방 구조를 아무도 안 적은 건물은 구조 조건에서 제외된다', () {
      expect(
        housingMatchesFilter(
          sum(types: const {}),
          const HousingFilter(roomTypes: {HousingRoomType.oneRoom}),
        ),
        isFalse,
      );
    });

    test('관리비 포함 토글이 결과를 바꾼다', () {
      // 월세 40 + 관리비 10 = 50.
      final s = sum(rent: 40, fee: 10);
      const f = HousingFilter(maxMonthly: 45);
      expect(
        housingMatchesFilter(s, f), // 포함(기본) → 50 > 45 → 탈락
        isFalse,
      );
      expect(
        housingMatchesFilter(s, const HousingFilter(
          maxMonthly: 45,
          includeMaintenance: false,
        )), // 월세만 → 40 ≤ 45 → 통과
        isTrue,
      );
    });

    test('보증금 상한', () {
      expect(
        housingMatchesFilter(
            sum(deposit: 1000), const HousingFilter(maxDeposit: 500)),
        isFalse,
      );
      expect(
        housingMatchesFilter(
            sum(deposit: 300), const HousingFilter(maxDeposit: 500)),
        isTrue,
      );
    });

    test('필요 조건은 전부 갖춰야 한다 (AND)', () {
      final s = sum(features: {'풀옵션', '베란다'});
      expect(
        housingMatchesFilter(
            s, const HousingFilter(requiredFeatures: {'풀옵션', '베란다'})),
        isTrue,
      );
      expect(
        housingMatchesFilter(
            s, const HousingFilter(requiredFeatures: {'풀옵션', '엘리베이터'})),
        isFalse,
      );
    });

    test('상위 5개 밖으로 밀린 특징도 조건으로 걸린다', () {
      final s = HousingSummary.from([
        _r(features: const ['a', 'b', 'c', 'd', 'e', '도시가스']),
      ]);
      expect(
        housingMatchesFilter(
            s, const HousingFilter(requiredFeatures: {'도시가스'})),
        isTrue,
      );
    });

    test('여러 조건은 모두 만족해야 한다', () {
      final s = sum(
        deposit: 300,
        rent: 35,
        fee: 5,
        types: {HousingRoomType.oneRoom},
        features: {'풀옵션'},
      );
      const good = HousingFilter(
        roomTypes: {HousingRoomType.oneRoom},
        maxDeposit: 500,
        maxMonthly: 45,
        requiredFeatures: {'풀옵션'},
      );
      expect(housingMatchesFilter(s, good), isTrue);
      // 하나만 어긋나도 탈락
      expect(
        housingMatchesFilter(s, const HousingFilter(
          roomTypes: {HousingRoomType.oneRoom},
          maxDeposit: 100,
          maxMonthly: 45,
          requiredFeatures: {'풀옵션'},
        )),
        isFalse,
      );
    });
  });

  group('기숙사 비용 환산', () {
    final dorm = kDormCosts.first;

    test('학교 공지의 총액과 일치한다', () {
      expect(dorm.semesterTotalWon, 4071320);
    });

    test('월 환산이 공지의 값과 맞는다 (주거 34 / 식비 24 / 합계 58만원)', () {
      expect(dorm.monthlyHousing, 34);
      expect(dorm.monthlyMeal, 24);
      expect(dorm.monthlyWithMeals, 58);
    });
  });

  group('kHousingFeatures — 제보에 쌓인 문자열과 일치해야 한다', () {
    test('제보 폼이 써 온 값들이 그대로 들어 있다', () {
      // 철자가 바뀌면 기존 제보가 그 조건에 영영 안 걸린다.
      for (final f in const [
        '풀옵션',
        '엘리베이터',
        '주차 가능',
        '베란다',
        '복층',
        '심야전기',
        '도시가스',
        '햇빛 잘 듦',
        '방음 양호',
        '벌레 적음',
      ]) {
        expect(kHousingFeatures, contains(f), reason: '$f 가 목록에서 빠졌다');
      }
    });

    test('같은 뜻의 문자열이 두 벌로 갈라져 있지 않다', () {
      // 예전엔 제보 폼이 "방음 양호", 관리자 화면이 "방음 좋음"을 썼다.
      expect(kHousingFeatures, isNot(contains('방음 좋음')));
    });

    test('중복이 없다', () {
      expect(kHousingFeatures.toSet().length, kHousingFeatures.length);
    });
  });
}
