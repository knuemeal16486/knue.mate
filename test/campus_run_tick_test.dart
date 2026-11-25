import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/campus_run_screen.dart';

/// 런 탭 1초 틱: 달리지 않을 땐 분이 바뀔 때만 다시 그린다.
void main() {
  DateTime t(int h, int m, int s) => DateTime(2026, 11, 25, h, m, s);

  test('달리는 중이면 매초', () {
    expect(runTickNeedsRebuild(t(12, 0, 1), t(12, 0, 2), running: true), isTrue);
  });
  test('달리지 않으면 같은 분 안에선 안 그린다', () {
    expect(runTickNeedsRebuild(t(12, 0, 1), t(12, 0, 59), running: false), isFalse);
  });
  test('분·시·날이 바뀌면 그린다', () {
    expect(runTickNeedsRebuild(t(12, 0, 59), t(12, 1, 0), running: false), isTrue);
    expect(runTickNeedsRebuild(t(12, 59, 59), t(13, 59, 0), running: false), isTrue);
    expect(
        runTickNeedsRebuild(DateTime(2026, 11, 25, 23, 59), DateTime(2026, 11, 26, 23, 59),
            running: false),
        isTrue);
  });
}
