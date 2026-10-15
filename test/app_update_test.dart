// 강제 업데이트 판정(lib/app_update.dart). 잘못된 값 하나로 모든 사용자가
// 업데이트 창에 갇히면 안 된다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/app_update.dart';

void main() {
  group('requiredBuildFor', () {
    test('플랫폼마다 따로 읽는다 — 스토어마다 풀리는 날이 다르다', () {
      final data = {'androidBuild': 104, 'iosBuild': 103};
      expect(requiredBuildFor(data, isIOS: false), 104);
      expect(requiredBuildFor(data, isIOS: true), 103);
    });

    test('문서·필드가 없거나 값이 이상하면 묻지 않는다(null)', () {
      expect(requiredBuildFor(null, isIOS: false), isNull);
      expect(requiredBuildFor({}, isIOS: true), isNull);
      expect(requiredBuildFor({'androidBuild': '104'}, isIOS: false), isNull);
      expect(requiredBuildFor({'androidBuild': 0}, isIOS: false), isNull);
      expect(requiredBuildFor({'androidBuild': -1}, isIOS: false), isNull);
    });

    test('콘솔에서 숫자를 실수(double)로 넣어도 읽는다', () {
      expect(requiredBuildFor({'iosBuild': 104.0}, isIOS: true), 104);
    });
  });

  group('needsAppUpdate', () {
    test('내 빌드가 낮으면 업데이트', () {
      expect(needsAppUpdate(currentBuild: '103', requiredBuild: 104), isTrue);
    });

    test('같거나 높으면 묻지 않는다', () {
      expect(needsAppUpdate(currentBuild: '104', requiredBuild: 104), isFalse);
      expect(needsAppUpdate(currentBuild: '105', requiredBuild: 104), isFalse);
    });

    test('기준이 없거나 내 빌드 번호를 못 읽으면 묻지 않는다', () {
      expect(needsAppUpdate(currentBuild: '103', requiredBuild: null), isFalse);
      expect(needsAppUpdate(currentBuild: '', requiredBuild: 104), isFalse);
      expect(needsAppUpdate(currentBuild: 'abc', requiredBuild: 104), isFalse);
    });
  });
}
