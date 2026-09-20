import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 인증·관리자 권한을 한 곳에서 다룬다.
///
/// ## 왜 이렇게 생겼나
///
/// 예전에는 `app_config/club_admin`의 비밀번호를 **클라이언트가 읽어서**
/// 입력값과 비교했다. 문제가 둘이었다:
///  1. 그 문서는 누구나 읽을 수 있어서 비밀번호가 사실상 공개였다.
///  2. 애초에 Firestore 쓰기에 인증이 없어서, 비밀번호를 몰라도 아무나
///     club_events·sponsors에 직접 쓸 수 있었다(외부 링크가 붙는
///     sponsors는 피싱 통로가 된다).
///
/// 지금 구조:
///  - 모든 사용자는 **익명 로그인**한다. 학생 제보·별점처럼 누구나 하는
///    쓰기는 "로그인은 되어 있을 것"만 요구해 외부 스크립트를 막는다.
///  - 관리자는 비밀번호를 입력해 `admin_grants/{uid}` 문서를 만든다.
///    비밀번호 대조는 **보안 규칙이 서버에서** 한다(클라이언트는 정답을
///    읽을 수 없다). 이후 관리자 쓰기는 이 문서의 존재만 확인한다.
///  - 기기를 바꾸면 익명 uid가 새로 생기므로 비밀번호를 한 번 더 입력하면
///    그 기기에도 grant가 생긴다. 계정을 따로 만들 필요가 없다.
///
/// ⚠️ 비밀번호가 새어나가면 누구나 grant를 만들 수 있다. 그때는 콘솔에서
/// `app_config/admin`의 값을 바꾸고 기존 `admin_grants` 문서를 지우면 된다.
class AdminAuthService {
  AdminAuthService._();

  static const String grantCollection = 'admin_grants';

  /// Firebase 초기화가 실패했거나(앱은 그래도 뜬다) 테스트처럼 Firebase가
  /// 아예 없는 환경에서는 `FirebaseAuth.instance`가 **던진다**. 게터를 쓰는
  /// 쪽마다 try로 감싸는 걸 잊기 쉬우므로 여기서 한 번만 삼킨다.
  static FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  static FirebaseFirestore? get _db {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// 지금 로그인된 익명 사용자. 아직 로그인 전이면 null.
  static User? get currentUser => _auth?.currentUser;

  /// 이 기기가 관리자 권한을 갖고 있는지(마지막 확인 결과).
  /// 화면이 버튼을 감추거나 보여줄 때 쓴다 — 실제 차단은 보안 규칙이 한다.
  static final ValueNotifier<bool> isAdmin = ValueNotifier<bool>(false);

  /// 앱 시작 시 한 번. 익명 로그인하고, 이 기기에 관리자 grant가 있는지 본다.
  ///
  /// 실패해도 앱은 그대로 뜬다 — 읽기는 인증 없이도 되므로 식단·공지 같은
  /// 기본 기능은 살아 있어야 한다.
  static Future<void> initialize() async {
    try {
      final auth = _auth;
      if (auth == null) return;
      _watchForLostAccount(auth);
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      await refreshAdminStatus();
    } catch (e) {
      debugPrint('AdminAuthService.initialize 실패(앱은 계속 동작): $e');
    }
  }

  static bool _watching = false;

  /// 계정이 사라지면 다시 익명 로그인한다.
  ///
  /// Firebase 콘솔의 **익명 계정 자동 정리**를 켜 두면 오래된 익명 계정이
  /// 서버에서 지워진다. 그때 기기에는 로그인 상태가 남아 있는데 토큰은
  /// 무효라, 그대로 두면 Firestore 쓰기가 전부 권한 오류로 떨어진다.
  /// SDK가 토큰 갱신에 실패해 로그아웃 상태로 떨어뜨리는 순간을 잡아
  /// 새 익명 계정을 만든다.
  ///
  /// uid가 바뀌므로 기존 `admin_grants` 문서는 쓸모없어진다 — 관리자는
  /// 비밀번호를 한 번 더 넣으면 된다(새 기기에 권한을 여는 것과 같은 흐름).
  static void _watchForLostAccount(FirebaseAuth auth) {
    if (_watching) return;
    _watching = true;
    auth.authStateChanges().listen((user) async {
      if (user != null) return;
      isAdmin.value = false;
      try {
        await auth.signInAnonymously();
      } catch (e) {
        // 실패하면 그대로 둔다. 여기서 되풀이하면 네트워크가 없을 때
        // 재시도가 끝없이 돈다 — 다음 앱 실행의 initialize가 다시 해 준다.
        debugPrint('AdminAuthService: 익명 재로그인 실패: $e');
      }
    });
  }

  /// 이 기기에 grant 문서가 있는지 다시 확인한다.
  static Future<bool> refreshAdminStatus() async {
    final uid = _auth?.currentUser?.uid;
    final db = _db;
    if (uid == null || db == null) {
      isAdmin.value = false;
      return false;
    }
    try {
      final doc = await db
          .collection(grantCollection)
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      isAdmin.value = doc.exists;
      return doc.exists;
    } catch (e) {
      // grant 문서는 읽기가 막혀 있을 수도 있다(규칙을 더 조일 경우).
      // 확인에 실패했다고 권한을 준 것처럼 굴면 안 되므로 false로 둔다.
      debugPrint('AdminAuthService.refreshAdminStatus 실패: $e');
      isAdmin.value = false;
      return false;
    }
  }

  /// 비밀번호로 이 기기에 관리자 권한을 연다.
  ///
  /// 비밀번호가 맞는지는 **보안 규칙이 서버에서** 판단한다. 틀리면 쓰기가
  /// 거부되고 여기서는 실패로 돌아온다 — 앱은 정답을 알지 못한다.
  static Future<AdminUnlockResult> unlock(String password) async {
    if (password.trim().isEmpty) return AdminUnlockResult.wrongPassword;
    final auth = _auth;
    final db = _db;
    if (auth == null || db == null) return AdminUnlockResult.failed;
    var uid = auth.currentUser?.uid;
    if (uid == null) {
      try {
        final cred = await auth.signInAnonymously();
        uid = cred.user?.uid;
      } catch (e) {
        debugPrint('AdminAuthService.unlock 익명 로그인 실패: $e');
        return AdminUnlockResult.failed;
      }
    }
    if (uid == null) return AdminUnlockResult.failed;

    try {
      await db.collection(grantCollection).doc(uid).set({
        // 규칙이 app_config/admin의 값과 대조한다. 이 문서는 읽기가 막혀
        // 있어서 저장된 값이 밖으로 새지 않는다.
        'token': password.trim(),
        'grantedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 8));
      isAdmin.value = true;
      return AdminUnlockResult.ok;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return AdminUnlockResult.wrongPassword;
      }
      debugPrint('AdminAuthService.unlock 실패: $e');
      return AdminUnlockResult.failed;
    } catch (e) {
      debugPrint('AdminAuthService.unlock 실패: $e');
      return AdminUnlockResult.failed;
    }
  }

  /// 이 기기의 관리자 권한을 내려놓는다(기기를 넘길 때 등).
  static Future<void> revokeOnThisDevice() async {
    final uid = _auth?.currentUser?.uid;
    final db = _db;
    if (uid == null || db == null) return;
    try {
      await db.collection(grantCollection).doc(uid).delete();
    } catch (e) {
      debugPrint('AdminAuthService.revoke 실패: $e');
    }
    isAdmin.value = false;
  }
}

enum AdminUnlockResult {
  ok,
  /// 서버가 거부 — 비밀번호가 틀렸다.
  wrongPassword,
  /// 네트워크 등 다른 이유로 실패.
  failed,
}
