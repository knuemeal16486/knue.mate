import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/club_event_service.dart';

/// 포스터/제휴 이미지 업로드용 메타데이터 계산.
///
/// storage.rules가 `contentType.matches('image/.*')`를 요구하는데, putFile은
/// (putBlob과 달리) 메타데이터를 추론해 주지 않는다. 예전엔 아무것도 안 넘겨서
/// 규칙에 걸려 업로드가 조용히 거부됐다 — 그래서 "사진 첨부가 안 되는" 것처럼
/// 보였다. 여기서 계산한 값이 반드시 image/* 여야 한다.
void main() {
  group('posterContentType — 항상 image/* 여야 한다', () {
    test('흔한 확장자를 제대로 매핑한다', () {
      expect(posterContentType('/tmp/a.jpg'), 'image/jpeg');
      expect(posterContentType('/tmp/a.jpeg'), 'image/jpeg');
      expect(posterContentType('/tmp/a.png'), 'image/png');
      expect(posterContentType('/tmp/a.webp'), 'image/webp');
      expect(posterContentType('/tmp/a.gif'), 'image/gif');
      expect(posterContentType('/tmp/a.heic'), 'image/heic');
    });

    test('대문자 확장자도 인식한다', () {
      expect(posterContentType('/tmp/PHOTO.PNG'), 'image/png');
      expect(posterContentType('/tmp/PHOTO.HEIC'), 'image/heic');
    });

    test('확장자가 없거나 이상해도 image/* 를 돌려준다', () {
      // 규칙에 걸려 통째로 거부되느니 jpeg로 보내는 편이 낫다.
      for (final p in [
        '/tmp/noext',
        '/tmp/trailingdot.',
        '/tmp/weird.verylongextension',
        '/tmp/sym.\$\$\$',
        '',
      ]) {
        expect(
          posterContentType(p),
          startsWith('image/'),
          reason: '경로 "$p" 에서 image/* 가 안 나옴',
        );
      }
    });

    test('image_picker가 주는 실제 형태의 경로에서 동작한다', () {
      expect(
        posterContentType(
          '/data/user/0/com.knue.knuemate/cache/image_picker_1726.jpg',
        ),
        'image/jpeg',
      );
      expect(
        posterContentType(
          '/private/var/mobile/Containers/Data/Application/AB-CD/tmp/image_picker_X.heic',
        ),
        'image/heic',
      );
    });
  });

  group('posterFileExtension', () {
    test('확장자를 소문자로 뽑는다', () {
      expect(posterFileExtension('/tmp/a.PNG'), 'png');
      expect(posterFileExtension('/tmp/a.jpeg'), 'jpeg');
    });

    test('윈도우 경로 구분자도 처리한다', () {
      expect(posterFileExtension(r'C:\temp\photo.png'), 'png');
    });

    test('쿼리스트링을 떼어낸다', () {
      expect(posterFileExtension('/tmp/a.png?v=2'), 'png');
    });

    test('알 수 없으면 jpg', () {
      expect(posterFileExtension('/tmp/noext'), 'jpg');
      expect(posterFileExtension('/tmp/a.'), 'jpg');
      expect(posterFileExtension(''), 'jpg');
    });

    test('경로 중간의 점에 속지 않는다', () {
      expect(posterFileExtension('/tmp/my.folder/photo.png'), 'png');
      expect(posterFileExtension('/tmp/my.folder/noext'), 'jpg');
    });
  });
}
