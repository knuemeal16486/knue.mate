import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../ui_utils.dart';

/// 홈 히어로 헤더 안의 반투명 브리핑 타일 한 장(식단/버스 요약).
///
/// `IntrinsicHeight`의 2패스 레이아웃 비용과 OS 글꼴 확대 시 오버플로 위험을
/// 피하기 위해, 상위에서 텍스트 스케일에 맞춰 계산한 단일 패스 높이 안에서
/// 본문 영역을 `Expanded`로 유연하게 배치한다.
class HomeHeroTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String chip;
  final String footer;
  final VoidCallback onTap;
  final Widget body;
  final Widget? extra;
  final KnueWeatherInfo? weather;

  const HomeHeroTile({
    super.key,
    required this.icon,
    required this.title,
    required this.chip,
    required this.footer,
    required this.onTap,
    required this.body,
    this.extra,
    this.weather,
  });

  @override
  Widget build(BuildContext context) {
    final semanticLabel = chip.isEmpty ? '$title, $footer' : '$title, $chip, $footer';
    return AnimatedScaleButton(
      onTap: onTap,
      scaleFactor: 0.96,
      semanticLabel: semanticLabel,
      child: GlassContainer(
        opacity: 0.12,
        blur: 12,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(12),
        border: Border.all(
          color: KnueWeatherAtmosphere.tileBorderColor(weather),
          width: 1.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 17, color: Colors.white),
                if (chip.isNotEmpty)
                  Flexible(
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        chip,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: Colors.white,
                shadows: KnueTokens.headerTextShadow,
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: body,
              ),
            ),
            if (extra != null) ...[const SizedBox(height: 4), extra!],
            const SizedBox(height: 4),
            Row(
              children: [
                Flexible(
                  child: Text(
                    footer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
