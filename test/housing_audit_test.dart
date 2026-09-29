// 자취방 탭 점검(2026-09-29)에서 찾은 문제들을 고정하는 테스트.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/housing_filter_sheet.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

BaseBuilding _b(String id, {String? name, bool campus = false}) => BaseBuilding(
      id: id,
      floors: 4,
      ring: const [Offset(0, 0), Offset(20, 0), Offset(20, 20), Offset(0, 20)],
      road: '월탄3길',
      officialName: name,
      isCampus: campus,
    );

final _dasom = kOneRoomNameById['dasom']!;

void main() {
  group('buildingForOneRoom — 검색이 엉뚱한 건물로 가지 않는다', () {
    test('학생 제보로 이어진 건물을 먼저 찾는다', () {
      final b = buildingForOneRoom(
        _dasom,
        [_b('a', name: '다른빌'), _b('b', name: '또다른빌')],
        linkedOneRoomId: (id) => id == 'b' ? 'dasom' : null,
        nameOf: (x) => x.officialName,
      );
      expect(b?.id, 'b');
    });

    test('제보가 없으면 건물 이름으로 잇는다("다솜빌라"·"다솜"도 같은 곳)', () {
      final b = buildingForOneRoom(
        _dasom,
        [_b('a', name: '파인빌'), _b('b', name: '다솜빌라')],
        linkedOneRoomId: (_) => null,
        nameOf: (x) => x.officialName,
      );
      expect(b?.id, 'b');
    });

    test('이어진 건물이 없으면 null — 예전엔 아무 원룸 건물로 옮겨 갔다', () {
      final b = buildingForOneRoom(
        _dasom,
        [_b('a', name: '파인빌'), _b('b')],
        linkedOneRoomId: (_) => null,
        nameOf: (x) => x.officialName,
      );
      expect(b, isNull);
    });

    test('교내 건물은 이름이 같아도 원룸으로 잇지 않는다', () {
      final b = buildingForOneRoom(
        _dasom,
        [_b('c', name: '다솜빌', campus: true)],
        linkedOneRoomId: (_) => null,
        nameOf: (x) => x.officialName,
      );
      expect(b, isNull);
    });
  });

  group('housingMapStyle filtering — 맞는 곳이 0곳이면 지도도 0곳', () {
    final buildings = [_b('a', name: '파인빌'), _b('b', name: '에코빌')];

    test('거르는 중인데 맞는 곳이 없으면 아무것도 칠하지 않는다', () {
      final s = housingMapStyle(buildings, filtering: true);
      expect(s.displayNames, isEmpty);
    });

    test('거르지 않으면 예전처럼 전부 이름표를 단다', () {
      final s = housingMapStyle(buildings);
      expect(s.displayNames.keys, containsAll(['a', 'b']));
    });

    test('맞는 곳만 남긴다', () {
      final s = housingMapStyle(buildings, matches: {'b'}, filtering: true);
      expect(s.displayNames.keys, ['b']);
    });
  });

  group('HousingSummary — 전화번호만 남긴 제보는 시세로 세지 않는다', () {
    HousingReport r(int dep, int rent, {String? phone}) => HousingReport(
          buildingId: 'a',
          deposit: dep,
          monthlyRent: rent,
          contactPhone: phone,
          features: const [],
          drawbacks: const [],
          reportedAt: DateTime(2026, 9, 29),
        );

    test('번호만 있으면 시세 없음 — 예전엔 "월 0만원"으로 월세순 맨 앞에 섰다', () {
      final s = HousingSummary.from([r(0, 0, phone: '010-1234-5678')]);
      expect(s.hasData, isFalse);
      expect(s.avgMonthlyTotal, isNull);
      expect(s.avgDeposit, isNull);
      expect(s.getPricing(HousingRoomType.oneRoom), isNull);
      // 번호는 그대로 남는다.
      expect(s.publicContactPhones, isNotEmpty);
      // [월 35 이하]에 걸리지 않는다.
      expect(
        evaluateHousingFilter(s, null, const HousingFilter(maxMonthly: 35)).verdict,
        isNot(HousingFilterVerdict.match),
      );
    });

    test('시세 제보와 섞여 있으면 평균·건수는 시세 제보로만', () {
      final s = HousingSummary.from([r(300, 40), r(0, 0, phone: '010-1111-2222')]);
      expect(s.reportCount, 1);
      expect(s.avgRent, 40);
      expect(s.avgDeposit, 300);
    });
  });

  testWidgets('내 조건 찾기: 금액 칸엔 숫자만 들어간다 — "35.5"로 조건이 조용히 풀리지 않게', (tester) async {
    HousingFilter? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async => result = await showModalBottomSheet<HousingFilter>(
              context: c,
              isScrollControlled: true,
              builder: (_) => HousingFilterSheet(
                initial: const HousingFilter(),
                isDark: false,
                countMatches: (_) => 0,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '월 부담'), '35.5');
    await tester.pump();
    expect(find.text('355'), findsOneWidget, reason: '점은 걸러지고 숫자만 남는다');
    await tester.ensureVisible(find.textContaining('곳 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('곳 보기'));
    await tester.pumpAndSettle();
    expect(result, isNotNull, reason: '시트가 조건을 돌려줘야 한다');
    expect(result!.maxMonthly, 355);
  });

  testWidgets('showOverlayToast — 바텀시트가 열려 있어도 맨 위에 뜨고, 잠시 뒤 사라진다', (tester) async {
    late BuildContext sheetCtx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showModalBottomSheet(
              context: c,
              builder: (ctx) {
                sheetCtx = ctx;
                return const SizedBox(height: 500, child: Text('sheet'));
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    showOverlayToast(sheetCtx, '담겼습니다');
    await tester.pump();
    expect(find.text('담겼습니다'), findsOneWidget);

    // 시트가 덮는 화면 아래쪽에 뜬다. 오버레이 맨 위에 나중에 올라가므로
    // 시트 위에 그려진다(SnackBar는 같은 자리에서 시트 아래에 깔렸다).
    final toast = tester.getRect(find.text('담겼습니다'));
    final sheetTop = tester.getRect(find.text('sheet')).top;
    expect(toast.top, greaterThan(sheetTop));

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('담겼습니다'), findsNothing);
  });
}
