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
      // 옛 제보 문구는 조건 찾기의 이름으로 모인다('도시가스 난방' → '도시가스').
      expect(summary.topFeatures.first, '도시가스');
      expect(summary.allFeatures.contains('학교와 가까움'), isTrue);
      expect(summary.topDrawbacks.first, '벽간/층간 소음 있음 (방음 취약)');
      expect(summary.allDrawbacks.contains('심야전기/LPG (겨울 난방비 폭탄 주의)'), isTrue);

      // 최신 외벽 연락처 확인
      expect(summary.publicContactPhone, '010-5555-6666');

      // 전화번호 단독 제보(0원)로 인해 시세 평균이 0으로 왜곡되지 않고 정상 범위 유지
      expect(summary.avgDeposit, 100);
      expect(summary.avgRent, 36); // (35 + 37) / 2 = 36
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

    // Firestore는 배열 안의 배열을 거부한다. [[x,y],…]로 넣다가 건물
    // 합치기·추가가 한 번도 저장되지 못했다.
    test('외곽선은 배열 안의 배열 없이 저장되고 그대로 되읽힌다', () {
      const ring = [Offset(0, 0), Offset(10.5, 0), Offset(10.5, 7)];
      final map = const HousingBuildingOverride(
        buildingId: 'm',
        name: '합친 동',
        zone: HousingZone.darak,
        customRing: ring,
      ).toFirestore();

      final stored = map['customRing'] as List;
      expect(stored.any((p) => p is List), isFalse);
      expect(HousingBuildingOverride.fromMap('m', map)!.customRing, ring);
      expect(decodeRing(encodeRing(ring)), ring);
    });

    test('옛 [x, y] 모양 외곽선도 읽고, 깨진 점은 건너뛴다', () {
      expect(
        decodeRing([
          [1, 2],
          {'x': 3, 'y': 4},
          'junk',
          [5],
        ]),
        const [Offset(1, 2), Offset(3, 4)],
      );
      expect(decodeRing(null), isEmpty);
    });

    test('직접 추가한 건물 문서를 읽고, 외곽선이 모자라면 버린다', () {
      final b = customBuildingFromMap('custom_1', {
        'name': '신규 원룸',
        'floors': 5,
        'ring': encodeRing(const [Offset(0, 0), Offset(4, 0), Offset(4, 4)]),
      })!;
      expect(b.officialName, '신규 원룸');
      expect(b.floors, 5);
      expect(b.ring.length, 3);
      expect(customBuildingFromMap('x', {'ring': encodeRing(const [Offset(0, 0)])}), isNull);
    });

    test('추가한 건물은 지도 뒤에 붙고, 같은 id면 구워진 쪽을 쓴다', () {
      const ring = [Offset(0, 0), Offset(1, 0), Offset(1, 1)];
      const baked = BaseBuilding(id: 'a', floors: 2, ring: ring);
      const dup = BaseBuilding(id: 'a', floors: 9, ring: ring);
      const added = BaseBuilding(id: 'custom_1', floors: 3, ring: ring);
      final out = withCustomBuildings([baked], [dup, added]);
      expect(out.map((b) => b.id), ['a', 'custom_1']);
      expect(out.first.floors, 2);
    });

    group('applyBuildingOverrides', () {
      const ring = [Offset(0, 0), Offset(10, 0), Offset(10, 10)];
      const low = BaseBuilding(id: 'a', floors: 1, ring: ring);
      const other = BaseBuilding(id: 'b', floors: 2, ring: ring);
      HousingBuildingOverride o({int? floors, bool? isDeleted, String? mergedWith, List<Offset>? customRing}) =>
          HousingBuildingOverride(
            buildingId: 'a',
            name: 'x',
            zone: HousingZone.darak,
            floors: floors,
            isDeleted: isDeleted,
            mergedWith: mergedWith,
            customRing: customRing,
          );

      test('고친 층수만큼 건물이 높아진다', () {
        final out = applyBuildingOverrides([low, other], {'a': o(floors: 5)});
        expect(out.map((b) => b.floors), [5, 2]);
        const proj = IsoProjection(scale: 1, rotation: 0);
        expect(proj.heightOf(out.first), 5 * proj.heightOf(low));
      });

      test('층수를 안 고쳤거나 0 이하면 원래 층수를 쓴다', () {
        expect(applyBuildingOverrides([low], {'a': o()}).single.floors, 1);
        expect(applyBuildingOverrides([low], {'a': o(floors: 0)}).single.floors, 1);
      });

      test('삭제·병합된 건물은 빠지고, 고친 외곽선은 반영된다', () {
        expect(applyBuildingOverrides([low, other], {'a': o(isDeleted: true)}).map((b) => b.id), ['b']);
        expect(applyBuildingOverrides([low, other], {'a': o(mergedWith: 'm')}).map((b) => b.id), ['b']);
        const newRing = [Offset(0, 0), Offset(5, 0), Offset(5, 5), Offset(0, 5)];
        expect(applyBuildingOverrides([low], {'a': o(customRing: newRing)}).single.ring, newRing);
      });
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

      // P 마커 제거 요구사항 반영: parkingBadgeCenters는 비어 있어야 함
      expect(isoTerrain.parkingBadgeCenters.isEmpty, isTrue);
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

    test('IsoProjection.unproject 역투영 정밀도 검증 (화면 좌표 -> 월드 좌표)', () {
      final p = IsoProjection(scale: 1.4, rotation: 0.35);
      const originalWorld = Offset(120.5, -45.2);
      
      final screen = p.project(originalWorld.dx, originalWorld.dy);
      final recoveredWorld = p.unproject(screen.dx, screen.dy);

      expect((recoveredWorld.dx - originalWorld.dx).abs(), lessThan(1e-5));
      expect((recoveredWorld.dy - originalWorld.dy).abs(), lessThan(1e-5));
    });

    test('computeConvexHull 다각형 병합 외곽선 생성 검증', () {
      // 사각형 4개 정점 + 내부 점 1개
      final points = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 10),
        const Offset(0, 10),
        const Offset(5, 5), // 내부 점
      ];

      final hull = computeConvexHull(points);
      // 외곽선 점 4개만 남아야 함
      expect(hull.length, 4);
      expect(hull.contains(const Offset(5, 5)), isFalse);
    });
  });

  group('Korean Chosung Search, Phone Parsing & Room Type Pricing', () {
    test('한글 초성 및 부분 문자열 실시간 매칭 검증', () {
      expect(matchesKoreanHousingSearch('다솜빌', 'ㄷㅅ'), isTrue);
      expect(matchesKoreanHousingSearch('다솜빌', '다솜'), isTrue);
      expect(matchesKoreanHousingSearch('다솜빌', '다솜빌'), isTrue);
      expect(matchesKoreanHousingSearch('해오름빌', 'ㅎㅇ'), isTrue);
      expect(matchesKoreanHousingSearch('해오름빌', 'ㅎㅇㄹ'), isTrue);
      expect(matchesKoreanHousingSearch('바우하우스 A동', 'ㅂㅇ'), isTrue);
      expect(matchesKoreanHousingSearch('청람드림빌 A동', 'ㅊㄹ'), isTrue);
      expect(matchesKoreanHousingSearch('미래로빌', 'ㅁㄹ'), isTrue);
      expect(matchesKoreanHousingSearch('해오름빌', 'ㄱㄴ'), isFalse);
    });

    test('복수 전화번호(집주인, 관리인) 분리 파싱 검증', () {
      final parsed1 = parseContactPhones(['010-1234-5678, 010-9876-5432']);
      expect(parsed1, ['010-1234-5678', '010-9876-5432']);

      final parsed2 = parseContactPhones(['010-1111-2222 / 043-231-1234']);
      expect(parsed2, ['010-1111-2222', '043-231-1234']);

      final parsed3 = parseContactPhones(['010-1111-2222', '010-1111-2222']); // 중복 제거
      expect(parsed3, ['010-1111-2222']);
    });

    test('방 구조별(원룸, 1.5룸, 2룸) 시세 산출 및 환산 검증', () {
      // 1. 실 제보가 각각 있는 경우
      final reports = [
        HousingReport(
          buildingId: 'b1',
          deposit: 200,
          monthlyRent: 35,
          maintenanceFee: 3,
          roomType: HousingRoomType.oneRoom,
          features: const [],
          reportedAt: DateTime.now(),
        ),
        HousingReport(
          buildingId: 'b1',
          deposit: 300,
          monthlyRent: 45,
          maintenanceFee: 5,
          roomType: HousingRoomType.onePointFive,
          features: const [],
          reportedAt: DateTime.now(),
        ),
      ];

      final summary = HousingSummary.from(reports);

      // 원룸 시세 확인
      final oneRoomPricing = summary.getPricing(HousingRoomType.oneRoom)!;
      expect(oneRoomPricing.deposit, 200);
      expect(oneRoomPricing.monthlyRent, 35);
      expect(oneRoomPricing.maintenanceFee, 3);
      expect(oneRoomPricing.totalMonthly, 38);
      expect(oneRoomPricing.isEstimated, isFalse);

      // 1.5룸 시세 확인
      final onePointFivePricing = summary.getPricing(HousingRoomType.onePointFive)!;
      expect(onePointFivePricing.deposit, 300);
      expect(onePointFivePricing.monthlyRent, 45);
      expect(onePointFivePricing.maintenanceFee, 5);
      expect(onePointFivePricing.totalMonthly, 50);
      expect(onePointFivePricing.isEstimated, isFalse);

      // 2룸 제보가 없으면 시세를 지어내지 않는다(예전엔 원룸 값에 +300/+18을 더해 만들었다).
      expect(summary.getPricing(HousingRoomType.twoRoom), isNull);
    });

    test('UI/UX 5대 기능 모델 및 시세 태그 연동 검증', () {
      final summary = HousingSummary.empty;
      // 교원대 정문 좌표와 가상 건물 좌표
      const buildingCenter = Offset(50, 400);
      final dist = walkingDistanceMeters(buildingCenter, CampusLandmark.mainGate);
      final minutes = walkingMinutes(dist);

      expect(dist, greaterThan(0));
      expect(minutes, greaterThan(0));

      // 제보가 하나도 없으면 시세가 없다 — 예전엔 "표준 가이드"라며 200/34를 지어냈다.
      expect(summary.getPricing(HousingRoomType.oneRoom), isNull);
      expect(summary.getPricing(HousingRoomType.onePointFive), isNull);
    });
  });
}


