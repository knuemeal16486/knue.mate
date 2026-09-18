// 일회성 스크립트: 상태바 알림 아이콘(모노크롬 실루엣) 생성 후 삭제 예정.
import 'dart:io';
import 'package:image/image.dart';

void main() {
  const s = 768;
  final img = Image(width: s, height: s, numChannels: 4);
  fill(img, color: ColorRgba8(0, 0, 0, 0));

  final white = ColorRgba8(255, 255, 255, 255);
  const cx = s / 2;

  // 사각모 윗판 (마름모)
  const capTopY = s * 0.30;
  const dw = s * 0.32;
  const dh = s * 0.115;
  fillPolygon(
    img,
    vertices: [
      Point(cx, capTopY - dh),
      Point(cx + dw, capTopY),
      Point(cx, capTopY + dh),
      Point(cx - dw, capTopY),
    ],
    color: white,
  );

  // 머리에 닿는 둥근 밴드 (알약 모양)
  const bandW = s * 0.30;
  const bandH = s * 0.16;
  const bandTop = capTopY + dh * 0.2;
  const bandLeft = cx - bandW / 2;
  final bandRadius = bandH / 2;
  fillRect(
    img,
    x1: (bandLeft + bandRadius).round(),
    y1: bandTop.round(),
    x2: (bandLeft + bandW - bandRadius).round(),
    y2: (bandTop + bandH).round(),
    color: white,
  );
  fillCircle(
    img,
    x: (bandLeft + bandRadius).round(),
    y: (bandTop + bandRadius).round(),
    radius: bandRadius.round(),
    color: white,
  );
  fillCircle(
    img,
    x: (bandLeft + bandW - bandRadius).round(),
    y: (bandTop + bandRadius).round(),
    radius: bandRadius.round(),
    color: white,
  );

  // 술 (tassel): 마름모 오른쪽 꼭짓점에서 아래로
  const tasselStartX = cx + dw * 0.55;
  const tasselStartY = capTopY + dh * 0.35;
  const tasselEndX = cx + dw * 0.80;
  const tasselEndY = capTopY + dh + s * 0.30;
  const tasselW = s * 0.028;
  final dxT = tasselEndX - tasselStartX;
  final dyT = tasselEndY - tasselStartY;
  final len = (dxT * dxT + dyT * dyT) == 0 ? 1 : (dxT * dxT + dyT * dyT);
  final nx = -dyT / len * tasselW * 40; // perpendicular offset scaled
  final ny = dxT / len * tasselW * 40;
  fillPolygon(
    img,
    vertices: [
      Point(tasselStartX - nx, tasselStartY - ny),
      Point(tasselStartX + nx, tasselStartY + ny),
      Point(tasselEndX + nx, tasselEndY + ny),
      Point(tasselEndX - nx, tasselEndY - ny),
    ],
    color: white,
  );
  fillCircle(
    img,
    x: tasselEndX.round(),
    y: tasselEndY.round(),
    radius: (s * 0.035).round(),
    color: white,
  );

  // flutter_local_notifications가 아이콘을 drawable 타입으로만 조회하므로
  // mipmap-*이 아니라 drawable-*에 둬야 한다.
  final targets = {
    'drawable-mdpi': 24,
    'drawable-hdpi': 36,
    'drawable-xhdpi': 48,
    'drawable-xxhdpi': 72,
    'drawable-xxxhdpi': 96,
  };

  for (final entry in targets.entries) {
    final resized = copyResize(
      img,
      width: entry.value,
      height: entry.value,
      interpolation: Interpolation.average,
    );
    final dir = Directory('android/app/src/main/res/${entry.key}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/ic_stat_notify.png').writeAsBytesSync(encodePng(resized));
  }

  stdout.writeln('done');
}
