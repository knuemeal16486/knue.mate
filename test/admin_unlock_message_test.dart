import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/admin_auth_service.dart';

void main() {
  // 예전엔 네트워크·사용량 한도 실패까지 모두 "비밀번호가 일치하지 않습니다"로
  // 떠서, 맞는 비밀번호를 넣고도 원인을 알 수 없었다.
  test('실패 원인마다 다른 문구를 보여준다', () {
    final messages = {for (final r in AdminUnlockResult.values) r: r.message};
    expect(messages.values.toSet().length, AdminUnlockResult.values.length);
    expect(AdminUnlockResult.wrongPassword.message, contains('비밀번호'));
    expect(AdminUnlockResult.quotaExceeded.message, contains('한도'));
    expect(AdminUnlockResult.failed.message, isNot(contains('비밀번호')));
  });
}
