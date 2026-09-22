import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 종료 팝업(뒤로가기 팝업)의 윗칸에 무엇을 넣을지.
enum ExitPromoSlot {
  /// 진행중인 동아리·학과 행사.
  clubEvent,

  /// 애드몹 네이티브 광고.
  admobAd,

  /// "아직 등록된 행사가 없어요" 안내.
  emptyNotice,
}

/// 종료 팝업 윗칸을 무엇으로 채울지 고른다. 순수 함수(테스트 대상).
///
/// 동아리 행사가 **항상 이긴다.** 이 팝업이 존재하는 이유가 그 자리를
/// 동아리·학과에 내주기 위해서이기 때문이다. 광고는 그 자리가 비어 있을 때만,
/// 그리고 관리자가 켜 두었을 때만 들어간다.
ExitPromoSlot exitPromoSlot({
  required bool hasEvent,
  required bool fillWithAdmob,
}) {
  if (hasEvent) return ExitPromoSlot.clubEvent;
  return fillWithAdmob ? ExitPromoSlot.admobAd : ExitPromoSlot.emptyNotice;
}

/// Firestore 문서에서 스위치 값을 읽는다. 순수 함수(테스트 대상).
///
/// 문서가 없거나, 필드가 비었거나, 타입이 엉뚱하면 **꺼진 것으로 본다.**
/// 광고를 켜는 쪽이 언제나 명시적이어야 한다 — 읽다가 잘못된 값을 만났을 때
/// 학생 화면에 광고가 저절로 켜지는 일은 없어야 한다.
bool parseFillWithAdmob(Map<String, dynamic>? data) {
  final value = data?['fillWithAdmob'];
  return value is bool ? value : false;
}

/// 종료 팝업의 빈자리를 애드몹 광고로 채울지에 대한 **공용** 설정.
///
/// 관리자가 팝업 안에서 켜면 Firestore에 저장되고, 모든 기기가 그 값을 읽는다
/// (`app_settings/exit_promo`). 규칙이 쓰기를 관리자로 막으므로 학생 기기에서
/// [setFillWithAdmob]을 불러도 서버가 거부한다.
class ExitPromoSettings {
  static const _collection = 'app_settings';
  static const _doc = 'exit_promo';
  static const _prefsKey = 'exit_promo_fill_admob';

  static final ValueNotifier<bool> fillWithAdmob = ValueNotifier<bool>(false);

  static DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection(_collection).doc(_doc);

  /// 기기에 적어 둔 마지막 값을 올린다.
  ///
  /// 종료 팝업은 뒤로가기 한 번에 **바로** 떠야 해서 네트워크를 기다릴 수
  /// 없다. 그래서 값을 기기에도 남겨 두고, 팝업은 항상 이 캐시를 본다.
  static Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      fillWithAdmob.value = prefs.getBool(_prefsKey) ?? false;
    } catch (e) {
      debugPrint('ExitPromoSettings: 캐시 읽기 실패: $e');
    }
  }

  /// Firestore에서 최신값을 받아 기기에도 적어 둔다.
  ///
  /// 실패해도 조용히 넘어간다 — 캐시값이 남아 있고, 광고 설정 하나 때문에
  /// 앱이 켜지다 말면 안 된다.
  static Future<void> refresh() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final snap = await _ref.get();
      final value = parseFillWithAdmob(snap.data());
      fillWithAdmob.value = value;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('ExitPromoSettings: 갱신 실패: $e');
    }
  }

  /// 값을 바꾼다. **관리자 기기에서만 성공한다**(서버 규칙이 막는다).
  ///
  /// 거부당하면 화면 값을 되돌리고 예외를 그대로 올린다 — 호출부가 사용자에게
  /// 실패를 알릴 수 있어야 한다. 조용히 삼키면 "켰는데 안 켜진다"가 된다.
  static Future<void> setFillWithAdmob(bool value) async {
    final previous = fillWithAdmob.value;
    fillWithAdmob.value = value; // 스위치가 손가락을 바로 따라가게
    try {
      await _ref.set({
        'fillWithAdmob': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      fillWithAdmob.value = previous;
      rethrow;
    }
  }
}
