"""스플래시 로고 만들기: assets/icons/knue_icon.png(흰 정사각형) → 바탕이 투명한 로고 4장.

    python tool/make_splash_images.py
    dart run flutter_native_splash:create   # 그 뒤 styles.xml의 shortEdges 줄은 지운다(CLAUDE.md)

원본은 흰 바탕 위 수채 글씨라, 다크 모드 검은 바탕에 그대로 올리면 흰 네모가 뜬다.

- splash_light.png        흰 바탕을 투명으로(글씨 색 그대로). 원본 가장자리의 미세한
                          회색(249)이 흰 바탕에 네모 테두리로 비치던 것도 없어진다.
- splash_dark.png         + 회색 "KNUE"를 밝은 회색으로, 색 획은 명도를 올린다(짙은 남색이
                          검은 바탕에 묻혔다).
- splash_android12*.png   1152×1152. Android 12+는 가운데 지름 2/3 원만 보여서, 잉크가
                          반지름 0.30 안에 들게 줄인다(원본 그대로면 "Mate" 양끝이 잘린다).
- knue_icon_dark.png      splash_dark를 512로 줄인 것 — 앱 번들에 들어간다(로딩 화면).

흰 바탕 빼기: alpha = 1 - (가장 어두운 채널), 색 = 흰색과 섞이기 전 값으로 되돌린다.
"""
from pathlib import Path

import numpy as np
from PIL import Image

ICONS = Path(__file__).resolve().parent.parent / "assets" / "icons"
A12_SIZE = 1152
A12_RADIUS = 0.30  # 보이는 원의 반지름은 1/3 — 조금 안쪽


def unmultiply_white(src: Path) -> tuple[np.ndarray, np.ndarray]:
    im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255
    a = 1 - im.min(axis=2)
    a = np.clip((a - 0.04) / 0.96, 0, 1)  # 종이 결(249~254) 잡음은 완전 투명으로
    safe = np.maximum(a, 1e-4)[..., None]
    rgb = np.clip((im - (1 - safe)) / safe, 0, 1)
    return rgb, a


def for_dark(rgb: np.ndarray) -> np.ndarray:
    rgb = rgb.copy()
    mx = rgb.max(axis=2)
    grey = (mx - rgb.min(axis=2)) < 0.18
    rgb[grey] = np.array([0.90, 0.90, 0.92])
    col = ~grey
    # 가장 밝은 채널이 0.85 이상이 되게 같은 비율로 올린다(색상 유지).
    k = np.clip(0.85 / np.maximum(mx, 1e-3), 1, 2.2)
    rgb[col] = np.clip(rgb[col] * k[col][:, None], 0, 1)
    return rgb


def to_image(rgb: np.ndarray, a: np.ndarray) -> Image.Image:
    return Image.fromarray((np.dstack([rgb, a]) * 255).round().astype(np.uint8), "RGBA")


def android12(im: Image.Image) -> Image.Image:
    alpha = np.asarray(im)[..., 3]
    ys, xs = np.where(alpha > 40)
    c = im.size[0] / 2
    dmax = np.sqrt((xs - c) ** 2 + (ys - c) ** 2).max()
    n = round(im.size[0] * A12_SIZE * A12_RADIUS / dmax)
    out = Image.new("RGBA", (A12_SIZE, A12_SIZE), (0, 0, 0, 0))
    out.alpha_composite(im.resize((n, n), Image.LANCZOS), ((A12_SIZE - n) // 2,) * 2)
    return out


def main() -> None:
    rgb, a = unmultiply_white(ICONS / "knue_icon.png")
    light = to_image(rgb, a)
    dark = to_image(for_dark(rgb), a)
    for name, im in [
        ("splash_light.png", light),
        ("splash_dark.png", dark),
        ("splash_android12.png", android12(light)),
        ("splash_android12_dark.png", android12(dark)),
    ]:
        im.save(ICONS / name, optimize=True)
        print(name, im.size)
    # 앱 로딩 화면(lib/main.dart _buildLoadingScreen)용 — 100pt로 그리므로 작게.
    dark.resize((512, 512), Image.LANCZOS).save(ICONS / "knue_icon_dark.png", optimize=True)
    print("knue_icon_dark.png", (512, 512))


if __name__ == "__main__":
    main()
