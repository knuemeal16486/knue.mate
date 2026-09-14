// 홈 화면 속도 개선의 핵심 장치들을 검증한다.
//
// 배경: 홈이 뜨는 데 7초가 걸렸다. 원인은 (1) 식단·학사일정에 로컬 캐시가 없어
// 매번 네트워크를 기다렸고, (2) revision → 재로드 → 갱신 → revision 으로 도는
// 무한 갱신 루프가 있었으며, (3) 실패하는 Firestore 호출에 타임아웃이 없었다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/offline_cache.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RefreshThrottle.reset();
    FirestoreHealth.reportSuccess();
  });

  group('JsonCache', () {
    test('저장한 값을 그대로 돌려준다', () async {
      await JsonCache.save('k', {'a': 1});
      expect(await JsonCache.load('k', maxAge: const Duration(days: 1)),
          {'a': 1});
    });

    test('maxAge를 넘긴 값은 없는 것으로 친다', () async {
      await JsonCache.save('k', {'a': 1});
      expect(await JsonCache.load('k', maxAge: Duration.zero), isNull);
    });

    test('내용이 바뀔 때만 changed=true를 준다', () async {
      // 이게 false를 못 주면 revision이 계속 올라가 무한 갱신 루프가 된다.
      expect(await JsonCache.save('k', {'a': 1}), isTrue); // 최초 저장
      expect(await JsonCache.save('k', {'a': 1}), isFalse); // 같은 값
      expect(await JsonCache.save('k', {'a': 2}), isTrue); // 달라짐
    });

    test('깨진 JSON은 조용히 무시한다', () async {
      SharedPreferences.setMockInitialValues({
        'k': '{깨진',
        'k_ts': DateTime.now().millisecondsSinceEpoch,
      });
      expect(await JsonCache.load('k', maxAge: const Duration(days: 1)), isNull);
    });
  });

  group('MealCache', () {
    final d1 = DateTime(2026, 8, 19);
    final d2 = DateTime(2026, 8, 20);

    test('저장한 식단을 그대로 읽는다', () async {
      const data = {
        'meals': {
          'breakfast': <String>[],
          'lunch': ['김치찌개'],
          'dinner': <String>[],
        }
      };
      await MealCache.save(d1, MealSource.a, data);
      expect(await MealCache.load(d1, MealSource.a), data);
    });

    test('날짜와 식당이 다르면 서로 섞이지 않는다', () async {
      await MealCache.save(d1, MealSource.a, const {
        'meals': {'lunch': ['A']}
      });
      expect(await MealCache.load(d2, MealSource.a), isNull);
      expect(await MealCache.load(d1, MealSource.b), isNull);
    });

    test('내용이 같으면 revision을 올리지 않는다', () async {
      // 올리면 화면이 다시 로드하고, 그게 또 갱신을 불러 루프가 된다.
      const data = {
        'meals': {'lunch': ['A']}
      };
      await MealCache.save(d1, MealSource.a, data);
      final before = MealCache.revision.value;
      await MealCache.save(d1, MealSource.a, data);
      expect(MealCache.revision.value, before);
    });

    test('내용이 바뀌면 revision을 올려 화면이 다시 그리게 한다', () async {
      await MealCache.save(d1, MealSource.a, const {
        'meals': {'lunch': ['A']}
      });
      final before = MealCache.revision.value;
      await MealCache.save(d1, MealSource.a, const {
        'meals': {'lunch': ['B']}
      });
      expect(MealCache.revision.value, greaterThan(before));
    });
  });

  group('MealCache — JSON 직렬화 안전성', () {
    test('JSON으로 못 바꾸는 값이 섞이면 저장이 실패한다', () async {
      // Firestore 문서에는 Timestamp 같은 값이 들어 있다. 그대로 캐시에 넣으면
      // jsonEncode가 터지므로, 저장 전에 걸러야 한다는 걸 못 박아 둔다.
      expect(
        () => JsonCache.save('k', {'ts': Object()}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });

    test('meals만 담으면 문제없이 저장된다', () async {
      final ok = await JsonCache.save('k', {
        'meals': {'lunch': ['김치찌개'], 'dinner': <String>[]}
      });
      expect(ok, isTrue);
    });
  });

  group('RefreshThrottle', () {
    test('같은 키의 연속 갱신을 막는다', () {
      expect(RefreshThrottle.shouldRefresh('x'), isTrue);
      expect(RefreshThrottle.shouldRefresh('x'), isFalse);
    });

    test('키가 다르면 서로 막지 않는다', () {
      expect(RefreshThrottle.shouldRefresh('x'), isTrue);
      expect(RefreshThrottle.shouldRefresh('y'), isTrue);
    });

    test('reset하면 다시 허용한다 (당겨서 새로고침)', () {
      RefreshThrottle.shouldRefresh('x');
      RefreshThrottle.reset();
      expect(RefreshThrottle.shouldRefresh('x'), isTrue);
    });

    test('deferred는 즉시 실행하지 않는다 (첫 페인트 보호)', () {
      // 캐시로 그려놓고 곧바로 갱신하면 HTML 파싱이 첫 프레임을 밀어낸다.
      var ran = false;
      RefreshThrottle.deferred('x', () => ran = true);
      expect(ran, isFalse, reason: '즉시 실행되면 첫 프레임을 막는다');
      expect(RefreshThrottle.warmupDelay.inMilliseconds, greaterThan(0));
    });
  });

  group('FirestoreHealth (회로 차단기)', () {
    test('처음에는 사용 가능하다', () {
      expect(FirestoreHealth.isAvailable, isTrue);
    });

    test('실패를 보고하면 잠시 건너뛴다', () {
      // 규칙 미배포 상태에서 매 호출마다 몇 초씩 버리는 걸 막는다.
      FirestoreHealth.reportFailure();
      expect(FirestoreHealth.isAvailable, isFalse);
    });

    test('성공을 보고하면 즉시 복구된다', () {
      FirestoreHealth.reportFailure();
      FirestoreHealth.reportSuccess();
      expect(FirestoreHealth.isAvailable, isTrue);
    });
  });
}
