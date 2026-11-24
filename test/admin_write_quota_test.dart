import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

void main() {
  group('관리자 쓰기 실패 문구', () {
    // 한도에 걸린 쓰기는 끝나지 않아서, 예전엔 저장 창이 안 닫히고 아무
    // 안내도 없었다. 이제 제한 시간이 지나면 한도·네트워크를 짚어 준다.
    test('시간 초과는 쓰기 한도나 네트워크를 짚는다', () {
      final m = adminWriteErrorMessage(TimeoutException('x'));
      expect(m, contains('한도'));
      expect(m, contains('저장'));
    });

    test('한도 초과·권한 없음·그 밖을 구분한다', () {
      FirebaseException fe(String code) => FirebaseException(plugin: 'cloud_firestore', code: code);
      expect(adminWriteErrorMessage(fe('resource-exhausted')), contains('오후 4~5시'));
      expect(adminWriteErrorMessage(fe('permission-denied'), what: '삭제'), allOf(contains('권한'), contains('삭제')));
      expect(adminWriteErrorMessage(fe('unavailable')), contains('네트워크'));
      expect(adminWriteErrorMessage(StateError('x')), contains('네트워크'));
    });
  });

  test('이름 없이 "삭제됨" 표시만 단 문서도 읽는다', () {
    final o = HousingBuildingOverride.fromMap('b', {'name': '', 'zone': HousingZone.values.first.name, 'isDeleted': true});
    expect(o?.isDeleted, isTrue);
    expect(applyBuildingOverrides(const [], {'b': o!}), isEmpty);
  });
}
