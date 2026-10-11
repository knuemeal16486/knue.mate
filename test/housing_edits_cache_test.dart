// 관리자 수정(건물 수정·추가 건물·위치 표시)을 학생 기기가 언제 서버에서
// 다시 받는지(2026-10-08). 지도를 열 때마다 약 270건을 읽어 하루 읽기 한도가
// 찼다 — 판 번호가 그대로면 기기 캐시에서 읽는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_service.dart';

void main() {
  final now = DateTime(2026, 10, 8, 15);

  bool can({int? remote, int? synced, DateTime? at}) => canUseCachedHousingEdits(
        remoteVersion: remote,
        syncedVersion: synced,
        syncedAt: at,
        now: now,
      );

  test('판 번호가 그대로면 캐시 — 서버 읽기 0건', () {
    expect(can(remote: 7, synced: 7, at: now.subtract(const Duration(hours: 3))), isTrue);
  });

  test('관리자가 고쳐 판 번호가 바뀌었으면 서버에서', () {
    expect(can(remote: 8, synced: 7, at: now.subtract(const Duration(minutes: 5))), isFalse);
  });

  test('한 번도 서버에서 받은 적이 없으면 서버에서', () {
    expect(can(remote: 7, synced: null, at: null), isFalse);
  });

  test('판 번호를 못 읽으면(오프라인·읽기 한도) 캐시', () {
    expect(can(remote: null, synced: 7, at: now.subtract(const Duration(hours: 1))), isTrue);
  });

  test('하루가 지나면 판 번호가 같아도 한 번은 서버에서 — 옛 관리자 앱으로 고친 것도 퍼지게', () {
    expect(can(remote: 7, synced: 7, at: now.subtract(const Duration(hours: 25))), isFalse);
  });

  test('기기 시계가 거꾸로 가서 받은 시각이 미래면 서버에서', () {
    expect(can(remote: 7, synced: 7, at: now.add(const Duration(hours: 1))), isFalse);
  });
}
