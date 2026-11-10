import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_model.dart';

void main() {
  group('busTimetableAdSlot', () {
    test('지나간 버스와 다음 버스 사이(다음 버스 바로 위)', () {
      expect(busTimetableAdSlot(3, 10), 3);
    });
    test('지나간 버스가 없으면 맨 위', () {
      expect(busTimetableAdSlot(0, 10), 0);
    });
    test('오늘 버스가 모두 지났으면 맨 끝', () {
      expect(busTimetableAdSlot(-1, 10), 10);
    });
    test('범위를 벗어난 값은 맨 끝', () {
      expect(busTimetableAdSlot(11, 10), 10);
    });
  });
}
