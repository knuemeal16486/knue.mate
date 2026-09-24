import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';
import 'package:knue_mate/vworld_api_service.dart';

void main() {
  group('Housing Distance & Walking Time Calculation', () {
    test('정문 기준 도보 거리 및 소요 시간 계산', () {
      // 정문 (-20, 205)과 정확히 같은 위치일 때
      final meters = walkingDistanceMeters(
        const Offset(-20, 205),
        CampusLandmark.mainGate,
      );
      expect(meters, 0);

      // 120m -> (120 / 67).ceil() = 2분
      expect(walkingMinutes(120), 2);

      // 정문으로부터 (80, 205) -> dx = 100m, dy = 0 -> 직선 100m, 도보 거리 = round(100 * 1.2) = 120m
      final dist100 = walkingDistanceMeters(
        const Offset(80, 205),
        CampusLandmark.mainGate,
      );
      expect(dist100, 120);
      expect(walkingMinutes(dist100), 2);
    });

    test('도서관 기준 도보 소요 시간 계산', () {
      // 도서관 (365, 22)
      final dist = walkingDistanceMeters(
        const Offset(365, 22),
        CampusLandmark.library,
      );
      expect(dist, 0);
      expect(walkingMinutes(dist), 1); // clamp(1, 60)
    });
  });

  group('Housing Summary with Reviews and Utilities', () {
    test('최근 후기 및 포함 공과금 집계', () {
      final reports = [
        HousingReport(
          id: 'r1',
          buildingId: 'b1',
          deposit: 100,
          monthlyRent: 35,
          features: const ['남향'],
          reportedAt: DateTime(2024, 1, 1),
          review: '조용하고 살기 좋아요.',
          includedUtilities: const ['수도', '인터넷'],
        ),
        HousingReport(
          id: 'r2',
          buildingId: 'b1',
          deposit: 100,
          monthlyRent: 30,
          features: const ['풀옵션'],
          reportedAt: DateTime(2024, 2, 1),
          review: '남향이라 채광이 아주 좋습니다.',
          includedUtilities: const ['인터넷', '전기'],
        ),
        HousingReport(
          id: 'r3',
          buildingId: 'b1',
          deposit: 100,
          monthlyRent: 35,
          features: const ['신축'],
          reportedAt: DateTime(2024, 3, 1),
          review: '', // 빈 후기는 제외되어야 함
          includedUtilities: const ['인터넷'],
        ),
      ];

      final summary = HousingSummary.from(reports);

      // 후기 집계: 최신순 (r2, r1), 빈 후기 제외
      expect(summary.recentReviews.length, 2);
      expect(summary.recentReviews[0], '남향이라 채광이 아주 좋습니다.');
      expect(summary.recentReviews[1], '조용하고 살기 좋아요.');

      // 공과금 집계: 인터넷(3건), 수도(1건), 전기(1건)
      expect(summary.commonUtilities.contains('인터넷'), isTrue);
    });
  });

  group('sortHousingItems', () {
    const b1 = BaseBuilding(
      id: 'b1',
      floors: 3,
      ring: [Offset(-20, 205), Offset(-10, 205), Offset(-10, 215), Offset(-20, 215)],
    );
    const b2 = BaseBuilding(
      id: 'b2',
      floors: 3,
      ring: [Offset(180, 205), Offset(190, 205), Offset(190, 215), Offset(180, 215)],
    );

    final s1 = HousingSummary.from([
      HousingReport(
        id: 'r1',
        buildingId: 'b1',
        deposit: 200,
        monthlyRent: 40,
        features: const [],
        reportedAt: DateTime(2024, 1, 1),
      ),
    ]);

    final s2 = HousingSummary.from([
      HousingReport(
        id: 'r2',
        buildingId: 'b2',
        deposit: 100,
        monthlyRent: 30,
        features: const [],
        reportedAt: DateTime(2024, 1, 1),
      ),
      HousingReport(
        id: 'r3',
        buildingId: 'b2',
        deposit: 100,
        monthlyRent: 30,
        features: const [],
        reportedAt: DateTime(2024, 1, 2),
      ),
    ]);

    final map = {
      'b1': s1,
      'b2': s2,
    };

    final items = [b1, b2];

    test('월 부담 싼 순 정렬', () {
      final sorted = sortHousingItems<BaseBuilding>(
        items: items,
        sortType: HousingSortType.monthlyTotalAsc,
        getSummary: (b) => map[b.id] ?? HousingSummary.empty,
        getBuilding: (b) => b,
        getName: (b) => b.id,
      );
      expect(sorted.first.id, 'b2'); // 월세 30이 40보다 앞
    });

    test('보증금 싼 순 정렬', () {
      final sorted = sortHousingItems<BaseBuilding>(
        items: items,
        sortType: HousingSortType.depositAsc,
        getSummary: (b) => map[b.id] ?? HousingSummary.empty,
        getBuilding: (b) => b,
        getName: (b) => b.id,
      );
      expect(sorted.first.id, 'b2'); // 보증금 100이 200보다 앞
    });

    test('정문 가까운 순 정렬', () {
      final sorted = sortHousingItems<BaseBuilding>(
        items: items,
        sortType: HousingSortType.distanceMainGateAsc,
        getSummary: (b) => map[b.id] ?? HousingSummary.empty,
        getBuilding: (b) => b,
        getName: (b) => b.id,
      );
      expect(sorted.first.id, 'b1'); // 정문 (-20, 205)에 가까운 b1이 앞
    });

    test('제보 많은 순 정렬', () {
      final sorted = sortHousingItems<BaseBuilding>(
        items: items,
        sortType: HousingSortType.reportCountDesc,
        getSummary: (b) => map[b.id] ?? HousingSummary.empty,
        getBuilding: (b) => b,
        getName: (b) => b.id,
      );
      expect(sorted.first.id, 'b2'); // 제보 2건인 b2가 1건인 b1보다 앞
    });
  });

  group('Housing Filter Matching with Quick Presets', () {
    test('월 35 이하 퀵 필터 매칭 검증', () {
      final summary30 = HousingSummary.from([
        HousingReport(
          id: 'r1',
          buildingId: 'b1',
          deposit: 100,
          monthlyRent: 30,
          features: const [],
          reportedAt: DateTime(2024, 1, 1),
        ),
      ]);
      final summary40 = HousingSummary.from([
        HousingReport(
          id: 'r2',
          buildingId: 'b2',
          deposit: 100,
          monthlyRent: 40,
          features: const [],
          reportedAt: DateTime(2024, 1, 1),
        ),
      ]);

      const filterUnder35 = HousingFilter(maxMonthly: 35);
      expect(housingMatchesFilter(summary30, filterUnder35), isTrue);
      expect(housingMatchesFilter(summary40, filterUnder35), isFalse);
    });
  });

  group('Housing Pros, Cons and Contact Phone Direct Deal Features', () {
    test('장단점 집계, 최신 외벽 연락처 추출, 시세 왜곡 방지 검증', () {
      final reports = [
        HousingReport(
          id: 'r1',
          buildingId: 'b1',
          deposit: 100,
          monthlyRent: 35,
          features: const ['도시가스 난방', '정문 도보 3분컷'],
          drawbacks: const ['심야전기/LPG (겨울 난방비 폭탄 주의)', '벽간/층간 소음 있음 (방음 취약)'],
          contactPhone: '010-1111-2222',
          reportedAt: DateTime(2024, 1, 1),
        ),
        HousingReport(
          id: 'r2',
          buildingId: 'b1',
          deposit: 100,
          monthlyRent: 37,
          features: const ['도시가스 난방'],
          drawbacks: const ['벽간/층간 소음 있음 (방음 취약)'],
          contactPhone: '010-3333-4444', // 더 최신 연락처
          reportedAt: DateTime(2024, 3, 1),
        ),
        HousingReport(
          id: 'r3_phone_only',
          buildingId: 'b1',
          deposit: 0,
          monthlyRent: 0,
          features: const [],
          drawbacks: const [],
          contactPhone: '010-5555-6666', // 가장 최신 연락처 제보 (시세는 0)
          reportedAt: DateTime(2024, 5, 1),
        ),
      ];

      final summary = HousingSummary.from(reports);

      // 장단점 정렬 및 집계
      expect(summary.topFeatures.first, '도시가스 난방');
      expect(summary.allFeatures.contains('정문 도보 3분컷'), isTrue);
      expect(summary.topDrawbacks.first, '벽간/층간 소음 있음 (방음 취약)');
      expect(summary.allDrawbacks.contains('심야전기/LPG (겨울 난방비 폭탄 주의)'), isTrue);

      // 최신 외벽 연락처 확인
      expect(summary.publicContactPhone, '010-5555-6666');

      // 전화번호 단독 제보(0원)로 인해 시세 중앙값이 0으로 왜곡되지 않고 정상 범위 유지
      expect(summary.medianDeposit, 100);
      expect(summary.medianRent, 36); // (35 + 37) / 2 = 36
    });
  });

  group('CampusElevation 3D Topography & VWorld API Integration', () {
    test('정문 평지 -> 도서관 -> 기숙사 -> 청람동산 고도 상승 검증', () {
      final gateElev = CampusElevation.elevationAt(0, 205);
      final libElev = CampusElevation.elevationAt(230, 70);
      final dormElev = CampusElevation.elevationAt(600, -350);
      final chungramElev = CampusElevation.elevationAt(620, -520);

      // 정문은 평지(0~3m)
      expect(gateElev, lessThan(5.0));
      // 도서관은 완만한 오르막(10~15m)
      expect(libElev, greaterThan(gateElev));
      expect(libElev, greaterThanOrEqualTo(10.0));
      // 기숙사는 고지대 구릉(24~32m)
      expect(dormElev, greaterThan(libElev));
      expect(dormElev, greaterThanOrEqualTo(24.0));
      // 청람동산 정상은 캠퍼스 최고지대(45~50m)
      expect(chungramElev, greaterThan(dormElev));
      expect(chungramElev, greaterThanOrEqualTo(45.0));
    });

    test('마칭 스퀘어 5m 등고선 레벨 생성 검증', () {
      final contours = CampusElevation.generateContourLevels();
      expect(contours.containsKey(10), isTrue);
      expect(contours.containsKey(20), isTrue);
      expect(contours.containsKey(30), isTrue);
      expect(contours.containsKey(40), isTrue);
      // 등고선 세그먼트가 정상적으로 생성되었는지 확인
      expect(contours[20]!.isNotEmpty, isTrue);
    });

    test('VWorldApiService 기본 키 및 BBOX 확인', () {
      final service = VWorldApiService();
      expect(service.apiKey, '4E4A8E57-990A-4BEE-BD4E-BF0AA63E318B');
      expect(VWorldApiService.knueBbox.contains('127.3'), isTrue);
    });
  });

  group('Developer Mode Custom Color and Building Overrides', () {
    test('HousingBuildingOverride customColorHex 직렬화 및 Color 변환 검증', () {
      const override = HousingBuildingOverride(
        buildingId: 'b_custom_1',
        name: '청람 스마트빌',
        zone: HousingZone.darak,
        customColorHex: '#03C75A',
        floors: 4,
      );

      // Color 파싱 검증 (#03C75A -> 0xFF03C75A)
      expect(override.customColor, isNotNull);
      expect(override.customColor!.toARGB32(), 0xFF03C75A);

      // Firestore map 직렬화 및 역직렬화
      final map = override.toFirestore();
      expect(map['customColorHex'], '#03C75A');
      expect(map['name'], '청람 스마트빌');

      final restored = HousingBuildingOverride.fromMap('b_custom_1', map);
      expect(restored, isNotNull);
      expect(restored!.customColorHex, '#03C75A');
      expect(restored.customColor, override.customColor);
      expect(restored.name, '청람 스마트빌');
    });

    test('housingMapStyle에서 커스텀 건물 색상(customColor) 최우선 적용 검증', () {
      const b = BaseBuilding(
        id: 'b_test',
        floors: 3,
        ring: [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)],
      );

      final styleWithoutOverride = housingMapStyle(
        [b],
        overrides: {},
        summaries: {},
      );
      // 오버라이드가 없으면 기본 unconfirmed 색상 사용
      expect(styleWithoutOverride.zoneColors.containsKey('b_test'), isFalse);

      final styleWithOverride = housingMapStyle(
        [b],
        overrides: {
          'b_test': const HousingBuildingOverride(
            buildingId: 'b_test',
            name: '초록 원룸',
            zone: HousingZone.darak,
            customColorHex: '#03C75A',
          ),
        },
        summaries: {},
      );
      // 커스텀 색상이 지정되면 zoneColors에 정확히 주입되어 건물 옥상/외벽에 반영됨
      expect(styleWithOverride.zoneColors.containsKey('b_test'), isTrue);
      expect(styleWithOverride.zoneColors['b_test']!.toARGB32(), 0xFF03C75A);
    });
  });

  group('Map Details: Greenery, Sidewalk and Parking Lots', () {
    test('IsoTerrain projectTerrain 주차장 P 심볼 뱃지 및 주차 구획 투영 검증', () {
      final baseTerrain = BaseTerrain(
        traced: const TracedGround(
          parking: [
            [Offset(10, 10), Offset(30, 10), Offset(30, 30), Offset(10, 30)],
            [Offset(50, 50), Offset(80, 50), Offset(80, 70), Offset(50, 70)],
          ],
        ),
        parkingLots: [
          [Offset(100, 100), Offset(120, 100), Offset(120, 120), Offset(100, 120)],
        ],
      );

      final p = IsoProjection();
      final isoTerrain = projectTerrain(baseTerrain, p);

      // 주차장 중심점(P 심볼 뱃지)이 각 주차장에 1개씩 정상 생성되는지 검증
      expect(isoTerrain.parkingBadgeCenters.length, 3);
      for (final center in isoTerrain.parkingBadgeCenters) {
        expect(center.dx, isNotNull);
        expect(center.dy, isNotNull);
      }
    });

    test('IsoTerrain 녹지 패스 및 경계선 유효성 검증', () {
      final baseTerrain = BaseTerrain(
        traced: const TracedGround(
          greens: [
            [Offset(0, 0), Offset(20, 0), Offset(20, 20), Offset(0, 20)],
          ],
        ),
        centralPlaza: const [
          Offset(40, 40),
          Offset(60, 40),
          Offset(60, 60),
          Offset(40, 60),
        ],
      );

      final p = IsoProjection();
      final isoTerrain = projectTerrain(baseTerrain, p);

      expect(isoTerrain.greens.getBounds().isEmpty, isFalse);
      expect(isoTerrain.centralPlaza.getBounds().isEmpty, isFalse);
    });
  });
}


