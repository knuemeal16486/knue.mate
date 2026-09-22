// 종료 팝업 윗칸을 무엇으로 채울지 고르는 판단과, 그 스위치를 읽는 부분.
//
// 화면 안에 있으면 확인할 방법이 없어 순수 함수로 떼어 놓았다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/exit_promo_settings.dart';

void main() {
  group('exitPromoSlot', () {
    test('행사가 있으면 광고 스위치와 무관하게 행사가 이긴다', () {
      // 이 팝업이 존재하는 이유가 동아리·학과에 자리를 내주는 것이다.
      // 광고를 켜 뒀다고 그 자리를 빼앗으면 안 된다.
      expect(
        exitPromoSlot(hasEvent: true, fillWithAdmob: true),
        ExitPromoSlot.clubEvent,
      );
      expect(
        exitPromoSlot(hasEvent: true, fillWithAdmob: false),
        ExitPromoSlot.clubEvent,
      );
    });

    test('행사가 없고 스위치가 켜져 있으면 애드몹 광고', () {
      expect(
        exitPromoSlot(hasEvent: false, fillWithAdmob: true),
        ExitPromoSlot.admobAd,
      );
    });

    test('행사가 없고 스위치가 꺼져 있으면 원래 안내', () {
      expect(
        exitPromoSlot(hasEvent: false, fillWithAdmob: false),
        ExitPromoSlot.emptyNotice,
      );
    });
  });

  group('parseFillWithAdmob', () {
    test('true면 켠다', () {
      expect(parseFillWithAdmob({'fillWithAdmob': true}), isTrue);
    });

    test('false면 끈다', () {
      expect(parseFillWithAdmob({'fillWithAdmob': false}), isFalse);
    });

    test('문서가 없으면 꺼진 것으로 본다', () {
      expect(parseFillWithAdmob(null), isFalse);
    });

    test('필드가 없으면 꺼진 것으로 본다', () {
      expect(parseFillWithAdmob({}), isFalse);
      expect(parseFillWithAdmob({'updatedAt': 123}), isFalse);
    });

    test('타입이 엉뚱하면 꺼진 것으로 본다', () {
      // 콘솔에서 손으로 문자열 "true"를 넣는 실수가 흔하다. 그걸 켬으로
      // 읽어버리면 학생 화면에 광고가 의도치 않게 켜진다 — 켜는 쪽은
      // 언제나 명시적이어야 한다.
      expect(parseFillWithAdmob({'fillWithAdmob': 'true'}), isFalse);
      expect(parseFillWithAdmob({'fillWithAdmob': 1}), isFalse);
      expect(parseFillWithAdmob({'fillWithAdmob': null}), isFalse);
    });
  });
}
