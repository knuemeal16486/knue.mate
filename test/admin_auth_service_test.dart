import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/admin_auth_service.dart';

/// Firebase가 없는 환경에서 AdminAuthService가 **던지지 않는지** 본다.
///
/// main.dart는 Firebase 초기화 실패를 일부러 삼키고 앱을 띄운다(읽기 전용
/// 기능은 살아야 하니까). 그래서 초기화가 실패한 채로 관리자 화면이 열릴 수
/// 있는데, 처음 구현에서는 `FirebaseAuth.instance`를 try 밖에서 건드려
/// 그 화면이 통째로 터졌다. 테스트 환경이 바로 그 "Firebase 없음" 상태라
/// 여기서 그대로 재현된다.
void main() {
  test('Firebase가 없어도 initialize가 던지지 않는다', () async {
    await expectLater(AdminAuthService.initialize(), completes);
  });

  test('Firebase가 없으면 관리자가 아니라고 답한다', () async {
    expect(await AdminAuthService.refreshAdminStatus(), isFalse);
    expect(AdminAuthService.isAdmin.value, isFalse);
  });

  test('Firebase가 없으면 unlock은 실패로 끝난다(통과시키지 않는다)', () async {
    expect(await AdminAuthService.unlock('아무거나'), AdminUnlockResult.failed);
    expect(AdminAuthService.isAdmin.value, isFalse);
  });

  test('빈 비밀번호는 서버에 묻지도 않고 거절한다', () async {
    expect(await AdminAuthService.unlock(''), AdminUnlockResult.wrongPassword);
    expect(
      await AdminAuthService.unlock('   '),
      AdminUnlockResult.wrongPassword,
    );
  });

  test('Firebase가 없어도 권한 해제가 던지지 않는다', () async {
    await expectLater(AdminAuthService.revokeOnThisDevice(), completes);
    expect(AdminAuthService.isAdmin.value, isFalse);
  });

  test('currentUser는 로그인 전에 null', () {
    expect(AdminAuthService.currentUser, isNull);
  });
}
