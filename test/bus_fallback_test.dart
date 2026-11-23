// 네트워크가 안 될 때 보여 줄 실시간 버스 값(2026-11-12). 기기 저장본을 맨 먼저
// 돌려주던 것을 "실패했을 때 가진 것 중 가장 최근 값"으로 바꿨다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_model.dart';

void main() {
  group('newestBusSnapshot', () {
    final a = <BusSummary>[];
    final b = <BusSummary>[];
    final c = <BusSummary>[];
    final t0 = DateTime(2026, 11, 12, 9, 0);

    test('가장 최근 값을 고른다', () {
      final got = newestBusSnapshot([
        (a, t0),
        (b, t0.add(const Duration(minutes: 3))),
        (c, t0.add(const Duration(minutes: 1))),
      ]);
      expect(identical(got, b), isTrue);
    });

    test('값이 없는 후보는 건너뛴다', () {
      final got = newestBusSnapshot([
        (null, t0.add(const Duration(minutes: 5))),
        (a, t0),
      ]);
      expect(identical(got, a), isTrue);
    });

    test('시각을 모르는 값은 시각이 있는 값에 밀린다', () {
      expect(identical(newestBusSnapshot([(a, null), (b, t0)]), b), isTrue);
      expect(identical(newestBusSnapshot([(b, t0), (a, null)]), b), isTrue);
    });

    test('시각을 모르는 값뿐이어도 없는 것보다 낫다', () {
      expect(identical(newestBusSnapshot([(null, t0), (a, null)]), a), isTrue);
    });

    test('아무것도 없으면 null', () {
      expect(newestBusSnapshot([(null, null), (null, t0)]), isNull);
    });
  });
}
