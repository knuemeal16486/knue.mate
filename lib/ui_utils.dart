import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';

/// 누르면 살짝 작아졌다가 돌아오는(Scale-down) 마이크로 인터랙션을 제공하는 래퍼 위젯.
class AnimatedScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;
  final Duration duration;

  const AnimatedScaleButton({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleFactor = 0.95,
    this.duration = const Duration(milliseconds: 150),
  });

  @override
  State<AnimatedScaleButton> createState() => _AnimatedScaleButtonState();
}

class _AnimatedScaleButtonState extends State<AnimatedScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleFactor).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// 부드러운 글래스모피즘(유리 질감)을 제공하는 컨테이너
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 15.0,
    this.opacity = 0.15,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding = const EdgeInsets.all(16),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary로 감싼다 — BackdropFilter를 스크롤되는 리스트 안에서
    // 그대로 쓰면(감싸지 않으면) 안드로이드 실기기에서 스크롤할 때 컴포지터가
    // 블러의 저장 레이어 경계를 못 따라가 그 아래 내용이 빈 사각형으로 남는
    // 고질적인 문제가 있다(Chrome/데스크톱에선 재현 안 됨 — 렌더링 경로가
    // 다르다). RepaintBoundary가 이 레이어를 형제 위젯의 리페인트와 분리해
    // 그 오염을 막는다.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: opacity),
              borderRadius: borderRadius,
              border: border ??
                  Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1.0,
                  ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 애플 위젯 스타일의 고급스러운 상단바 배경 (미세한 그라디언트 + 은은한 테두리)
class AppleAppBarFlexibleSpace extends StatelessWidget {
  final Color themeColor;
  final bool isDark;
  final BorderRadiusGeometry? borderRadius;
  final bool hasBottomBorder;

  const AppleAppBarFlexibleSpace({
    super.key,
    required this.themeColor,
    this.isDark = false,
    this.borderRadius,
    this.hasBottomBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: KnuePearl.headerGradient(themeColor, isDark),
        border: hasBottomBorder
            ? Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              )
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 청람 디자인 토큰 — 앱 전체 2색 체계의 단일 출처
//
// 주색은 사용자가 고르는 themeColor(constants.dart) 하나, 보조색은 여기 있는
// 웜 앰버 하나다. 보조색은 "시간이 얽힌 긴급 신호"(D-3 이내 D-Day, 제공중 상태,
// 실시간 라이브 dot, 산책로)에만 쓴다. 그 외의 유채색 하드코딩은 금지 —
// 기능마다 다른 원색을 깔면 무지개 슈퍼앱 인상이 되므로 여기로 수렴시킨다.
// ═══════════════════════════════════════════════════════════════════════════
class KnueTokens {
  KnueTokens._();

  /// 앱 기본 글꼴 패밀리 이름.
  ///
  /// 위젯은 테마(textTheme)에서 글꼴을 물려받지만, **Canvas에 직접 그리는
  /// 글자(TextPainter)는 테마를 안 탄다** — 지정 안 하면 그 부분만 기본
  /// 글씨체(Roboto)로 나온다. 지도 라벨처럼 직접 그리는 곳은 이 값을 쓴다.
  /// GoogleFonts가 런타임에 등록한 패밀리 이름을 그대로 가져온다.
  static String? get fontFamily => GoogleFonts.notoSansKr().fontFamily;

  /// 보조색(웜 앰버). 시간 긴급 신호 전용.
  static const Color warmLight = Color(0xFFD97706);
  static const Color warmDark = Color(0xFFFBBF24);
  static Color warm(bool isDark) => isDark ? warmDark : warmLight;

  /// 카드 서피스.
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color surfaceLight = Colors.white;
  static Color surface(bool isDark) => isDark ? surfaceDark : surfaceLight;

  /// 화면 배경 (홈/리스트 계열).
  static const Color bgDark = Color(0xFF000000);
  static const Color bgLight = Color(0xFFF2F2F7);
  static Color bg(bool isDark) => isDark ? bgDark : bgLight;

  /// 헤어라인(0.5px 보더) 컬러.
  static const Color hairlineDark = Color(0xFF2C2C2E);
  static const Color hairlineLight = Color(0xFFE5E5EA);
  static Color hairline(bool isDark) => isDark ? hairlineDark : hairlineLight;

  /// 보조 텍스트(캡션) 컬러.
  static const Color captionDark = Color(0xFF8E8E93);
  static const Color captionLight = Color(0xFF6E6E73);
  static Color caption(bool isDark) => isDark ? captionDark : captionLight;

  /// 표준 라운드.
  static const double radiusCard = 14;
  static const double radiusSheet = 16;

  /// 이중 소프트 섀도 — 카드가 떠 보이지 않게 아주 옅은 두 겹.
  static List<BoxShadow> cardShadow(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// 시각·D-Day·평점 등 숫자에 일괄 적용 — 자리수가 바뀌어도 폭이 안 흔들린다.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  /// 테마색 헤더 위 흰 글씨에 얹는 **아주 옅은 그림자**.
  ///
  /// 글자 가장자리만 살짝 눌러 배경에서 떠 보이게 하는 용도다. 모든 테마색에
  /// 같은 세기를 쓴다.
  ///
  /// 한때 배경이 밝을수록 그림자를 진하게 하는 방식을 썼는데(노랑에서 알파
  /// 0.66까지), 밝은 색에서 글자마다 검은 테두리가 둘린 것처럼 보여 오히려
  /// 지저분했다. 밝은 테마색에서 글씨가 흐린 건 팔레트의 선명함을 택한 대가로
  /// 받아들이고, 그림자는 어디서나 "있는 듯 없는 듯"한 선을 지킨다.
  static const double _shadowAlpha = 0.22;

  static List<Shadow> get headerTextShadow => [
        // 넓게 퍼지는 겹 — 글자 주변을 은은히 눌러준다.
        Shadow(
          color: Color.fromRGBO(0, 0, 0, _shadowAlpha),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
        // 좁은 겹 — 글자 가장자리를 또렷하게 만든다.
        Shadow(
          color: Color.fromRGBO(0, 0, 0, _shadowAlpha * 0.7),
          blurRadius: 1,
        ),
      ];

  // ── 카테고리 식별색 ──────────────────────────────────────────────────
  //
  // 아이콘을 전부 테마색 하나로 칠했더니 목록이 단조로워, 게시판처럼 "종류가
  // 여럿인 것"에만 고정색을 준다. 원색이 아니라 채도를 낮춘 잉크 톤이라
  // 서로 구분은 되면서도 한 가족으로 읽힌다 — 기능마다 원색을 박아 무지개가
  // 됐던 예전 방식으로 돌아가지 않기 위한 선이다.
  //
  // 규칙: 같은 게시판은 언제나 같은 색(이름 기반이라 순서가 바뀌어도 고정).
  static const List<Color> _categoryLight = [
    Color(0xFF4A6FA5), // slate blue
    Color(0xFF2E7D74), // teal
    Color(0xFF96603C), // clay
    Color(0xFF7A4F80), // plum
    Color(0xFF5A7A3C), // moss
    Color(0xFF8C6239), // bronze
    Color(0xFF53519E), // indigo
    Color(0xFF94506A), // mauve
  ];

  static const List<Color> _categoryDark = [
    Color(0xFF8AAAD8),
    Color(0xFF6FBFB4),
    Color(0xFFC89A78),
    Color(0xFFB98FBE),
    Color(0xFF9BC177),
    Color(0xFFC7A175),
    Color(0xFF9895DE),
    Color(0xFFC98CA4),
  ];

  /// 학생들이 실제로 즐겨찾기하는 주요 게시판은 색을 손으로 지정한다.
  /// (해시에 맡기면 기본 즐겨찾기인 대학소식/학사공지가 겹칠 수 있다.)
  static const Map<String, int> _categoryOverrides = {
    '대학소식': 0,
    '학사공지': 6,
    '장학금': 4,
    '등록금': 5,
    '학점교류': 1,
    '청람소양': 7,
    '교환학생': 1,
    '행사세미나': 3,
    '채용공고': 2,
    '입찰공고': 5,
    '학생지원': 0,
    '임용안내': 6,
    '취업정보': 2,
    '도서관일반': 2,
    '도서관학술': 5,
    '신문방송사': 3,
    // 홈 "빠른 실행" 4종 — 한 줄에 나란히 놓이므로 해시에 맡기지 않고
    // 반드시 서로 다른 색이 되도록 못 박는다.
    '공연·행사': 3,
    '자취방': 1,
    '캠퍼스런': 4,
    '교직원 연락처': 0,
  };

  /// 게시판·카테고리 이름 → 고정 식별색.
  /// 지정되지 않은 이름(학과 게시판 등)은 이름 해시로 자동 배정되므로,
  /// 게시판이 늘어나도 손볼 필요가 없다.
  /// 잉크 팔레트에서 [index]번째 색. 게시판처럼 이름이 아니라 고정된 분류
  /// (학사일정 종류 등)에 색을 붙일 때 쓴다.
  static Color inkAt(int index, bool isDark) {
    final palette = isDark ? _categoryDark : _categoryLight;
    return palette[index % palette.length];
  }

  static Color categoryColor(String name, bool isDark) {
    final palette = isDark ? _categoryDark : _categoryLight;
    final fixed = _categoryOverrides[name];
    if (fixed != null) return palette[fixed % palette.length];
    // 문자 코드 합 — 같은 이름이면 항상 같은 색.
    var h = 0;
    for (final unit in name.codeUnits) {
      h = (h + unit * 31) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 펄(진주) 테마 — 테마색을 단색이 아니라 미묘한 광택으로 보여준다.
//
// themeColor의 타입은 그대로 Color다(앱 전역이 이 값 하나에 의존한다).
// 여기서는 "색이 넓게 깔리는 표면"에만 그라데이션을 입힌다 — 헤더, 앱바,
// 설정의 색상 스와치. 아이콘·텍스트 같은 작은 요소는 단색 그대로가 선명하다.
//
// ⚠️ 마음에 안 들면 [kPearlTheme]만 false로 두면 즉시 예전 단색/2단 그라데이션
//    으로 돌아간다. 호출부는 하나도 건드릴 필요 없다.
// ═══════════════════════════════════════════════════════════════════════════

/// 펄 효과 on/off. false면 모든 헬퍼가 기존 단색 계열 값을 그대로 돌려준다.
const bool kPearlTheme = true;

class KnuePearl {
  KnuePearl._();

  /// 씨드 색에서 "빛 받은 쪽" 색을 만든다. 광택의 정체는 밝기보다 **색상 회전**
  /// 이다 — 흰색을 섞으면 그냥 바래지만, 색상을 돌리면 진주처럼 어른거린다.
  ///
  /// 밝기는 기존 공식(흰색 8% 혼합)의 밝기를 넘지 않도록 잡아둔다. 팔레트에
  /// 노랑(#FDD835)처럼 이미 흰 글씨 대비가 1.4:1밖에 안 되는 색이 있어서,
  /// 광택을 넣느라 밝기를 더 올리면 헤더 글씨가 읽히지 않는다.
  static Color highlight(Color seed, {double intensity = 1.0}) {
    final hsl = HSLColor.fromColor(seed);
    final candidate = hsl
        .withHue((hsl.hue + 14 * intensity) % 360)
        .withSaturation((hsl.saturation - 0.06 * intensity).clamp(0.0, 1.0))
        // 남은 여유(1-lightness)에 비례해 올린다 — 이미 밝은 색은 조금만.
        .withLightness(
          (hsl.lightness + 0.14 * intensity * (1.0 - hsl.lightness))
              .clamp(0.0, 1.0),
        )
        .toColor();
    return _capLuminance(candidate, seed);
  }

  /// [candidate]의 밝기가 기존 공식의 상한을 넘으면 [seed] 쪽으로 되돌려 맞춘다.
  /// 색상 회전은 최대한 살리면서 밝기만 깎기 위해 이분 탐색을 쓴다.
  static Color _capLuminance(Color candidate, Color seed) {
    final ceiling =
        Color.lerp(seed, Colors.white, 0.08)!.computeLuminance();
    if (candidate.computeLuminance() <= ceiling) return candidate;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 6; i++) {
      final mid = (lo + hi) / 2;
      final probe = Color.lerp(seed, candidate, mid)!;
      if (probe.computeLuminance() > ceiling) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return Color.lerp(seed, candidate, lo)!;
  }

  /// 그늘진 쪽. 색상을 차가운 쪽으로 돌리고 채도를 살짝 올려 깊이를 준다.
  static Color shade(Color seed, {double intensity = 1.0}) {
    final hsl = HSLColor.fromColor(seed);
    return hsl
        .withHue((hsl.hue - 12 * intensity + 360) % 360)
        .withSaturation((hsl.saturation + 0.05 * intensity).clamp(0.0, 1.0))
        .withLightness((hsl.lightness - 0.13 * intensity).clamp(0.0, 1.0))
        .toColor();
  }

  /// 헤더·앱바용 그라데이션. 대각선으로 흘러 넓은 면에서 광택으로 읽힌다.
  /// [kPearlTheme]가 false면 기존 2단(흰색 8% / 어두운색 8%) 공식 그대로.
  static LinearGradient headerGradient(Color seed, bool isDark) {
    if (!kPearlTheme) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(seed, Colors.white, 0.08)!,
          Color.lerp(
            seed,
            isDark ? Colors.black : const Color(0xFF0F172A),
            0.08,
          )!,
        ],
      );
    }
    // 다크 모드에서는 광택을 약하게 — 어두운 화면에서 밝은 띠가 튀지 않게.
    final k = isDark ? 0.65 : 1.0;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        highlight(seed, intensity: k),
        seed,
        shade(seed, intensity: k),
      ],
      stops: const [0.0, 0.52, 1.0],
    );
  }

  /// 설정 화면의 동그란 색상 스와치용. 헤더보다 광택을 세게 줘서
  /// 고를 때 색의 성격이 한눈에 보이게 한다.
  static LinearGradient swatchGradient(Color seed) {
    if (!kPearlTheme) {
      return LinearGradient(colors: [seed, seed]);
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        highlight(seed, intensity: 1.25),
        seed,
        shade(seed, intensity: 1.15),
      ],
      stops: const [0.0, 0.55, 1.0],
    );
  }

  /// 스와치 위에 겹치는 하이라이트 반사. 진주 특유의 "빛 고인 점"을 만든다.
  static RadialGradient sheen() => RadialGradient(
        center: const Alignment(-0.45, -0.55),
        radius: 0.9,
        colors: [
          Colors.white.withValues(alpha: kPearlTheme ? 0.42 : 0.0),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      );
}

/// 날씨(비, 바람, 눈, 기온 등)에 따라 헤더와 카드의 앰비언스를 은은하게 조색하는 유틸리티
class KnueWeatherAtmosphere {
  KnueWeatherAtmosphere._();

  /// 날씨 감응형 헤더 그라데이션
  static LinearGradient headerGradient(
    Color seed,
    bool isDark,
    KnueWeatherInfo? weather,
  ) {
    if (weather == null) {
      return KnuePearl.headerGradient(seed, isDark);
    }

    Color tintColor;
    double tintStrength;

    if (weather.isRaining) {
      // 비: 촉촉한 청록·아쿠아 틴트
      tintColor = const Color(0xFF06B6D4);
      tintStrength = isDark ? 0.12 : 0.08;
    } else if (weather.isSnowing) {
      // 눈: 포근한 스노우 화이트/아이스 틴트
      tintColor = const Color(0xFFE0F2FE);
      tintStrength = isDark ? 0.14 : 0.10;
    } else if (weather.isColdOrWindy) {
      // 바람/추위: 맑고 쌀쌀한 쿨 실버 블루 틴트
      tintColor = const Color(0xFF94A3B8);
      tintStrength = isDark ? 0.10 : 0.06;
    } else if (weather.isHot) {
      // 무더위: 따뜻한 앰버 썬 틴트
      tintColor = const Color(0xFFF59E0B);
      tintStrength = isDark ? 0.08 : 0.05;
    } else if (weather.isSunny) {
      // 맑음: 싱그러운 골든 틴트
      tintColor = const Color(0xFFFEF08A);
      tintStrength = isDark ? 0.06 : 0.04;
    } else {
      return KnuePearl.headerGradient(seed, isDark);
    }

    final baseHighlight =
        KnuePearl.highlight(seed, intensity: isDark ? 0.65 : 1.0);
    final baseShade = KnuePearl.shade(seed, intensity: isDark ? 0.65 : 1.0);

    final tintedHighlight = Color.lerp(baseHighlight, tintColor, tintStrength)!;
    final tintedSeed = Color.lerp(seed, tintColor, tintStrength * 0.5)!;
    final tintedShade = Color.lerp(baseShade, tintColor, tintStrength * 0.7)!;

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        tintedHighlight,
        tintedSeed,
        tintedShade,
      ],
      stops: const [0.0, 0.52, 1.0],
    );
  }

  /// 날씨에 따른 히어로 타일 테두리 컬러
  static Color tileBorderColor(KnueWeatherInfo? weather) {
    if (weather == null) return Colors.white.withValues(alpha: 0.22);
    if (weather.isRaining) {
      return const Color(0xFF67E8F9).withValues(alpha: 0.38); // 아쿠아 이슬 테두리
    } else if (weather.isSnowing) {
      return const Color(0xFFF8FAFC).withValues(alpha: 0.45); // 프로스트 테두리
    } else if (weather.isColdOrWindy) {
      return const Color(0xFFE2E8F0).withValues(alpha: 0.36); // 쿨 실버 윈드 테두리
    } else if (weather.isHot || weather.isSunny) {
      return const Color(0xFFFEF08A).withValues(alpha: 0.30); // 썬샤인 테두리
    }
    return Colors.white.withValues(alpha: 0.22);
  }

  /// 날씨에 따른 히어로 타일 내부 미세 그라디언트/틴트
  static LinearGradient tileGradient(KnueWeatherInfo? weather) {
    if (weather == null) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.08),
        ],
      );
    }
    if (weather.isRaining) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF06B6D4).withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.08),
          const Color(0xFF3B82F6).withValues(alpha: 0.12),
        ],
      );
    } else if (weather.isSnowing) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFE0F2FE).withValues(alpha: 0.24),
          Colors.white.withValues(alpha: 0.10),
        ],
      );
    } else if (weather.isColdOrWindy) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF94A3B8).withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.07),
          const Color(0xFFCBD5E1).withValues(alpha: 0.14),
        ],
      );
    } else if (weather.isHot || weather.isSunny) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFFDE047).withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.08),
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.16),
        Colors.white.withValues(alpha: 0.08),
      ],
    );
  }
}

enum _WeatherParticleKind { rain, snow, wind }

/// 입자 하나의 초기 상태. 애니메이션은 [WeatherParticlesOverlay]가 컨트롤러
/// 하나로 전부 몰아 돌리고(입자마다 AnimationController를 두면 무겁다),
/// 각 입자는 [phase]로 서로 어긋난 시작점을 가진다.
class _WeatherParticle {
  final double x; // 0..1, 가로 위치(비·눈) 또는 세로 위치(바람)
  final double phase; // 0..1, 루프 안에서 어디서 시작하는지
  final double speed; // 클수록 빨리 떨어짐/지나감
  final double size; // 길이(비) 또는 반지름(눈) 또는 길이(바람), 논리 픽셀
  final double opacity;
  final double drift; // 눈이 좌우로 흔들리는 폭, 비/바람은 0

  const _WeatherParticle({
    required this.x,
    required this.phase,
    required this.speed,
    required this.size,
    required this.opacity,
    this.drift = 0,
  });

  factory _WeatherParticle.random(math.Random rng, _WeatherParticleKind kind) {
    switch (kind) {
      case _WeatherParticleKind.rain:
        return _WeatherParticle(
          x: rng.nextDouble(),
          phase: rng.nextDouble(),
          speed: 0.8 + rng.nextDouble() * 0.6,
          size: 10 + rng.nextDouble() * 8,
          opacity: 0.12 + rng.nextDouble() * 0.16,
        );
      case _WeatherParticleKind.snow:
        return _WeatherParticle(
          x: rng.nextDouble(),
          phase: rng.nextDouble(),
          speed: 0.18 + rng.nextDouble() * 0.16,
          size: 1.4 + rng.nextDouble() * 2.0,
          opacity: 0.25 + rng.nextDouble() * 0.35,
          drift: 6 + rng.nextDouble() * 10,
        );
      case _WeatherParticleKind.wind:
        return _WeatherParticle(
          x: rng.nextDouble(), // 바람은 세로 위치로 씀
          phase: rng.nextDouble(),
          speed: 0.5 + rng.nextDouble() * 0.4,
          size: 40 + rng.nextDouble() * 50,
          opacity: 0.08 + rng.nextDouble() * 0.08,
        );
    }
  }
}

/// 날씨에 맞춰 헤더 위에 은은하게 얹는 파티클(비/눈/바람) 애니메이션.
/// [KnueWeatherAtmosphere]가 이미 배경 색·그라디언트를 날씨에 맞게 조색하는데,
/// 그 위에 살짝 움직이는 결을 더해 "은은하게 비/눈/바람이 부는" 느낌을 낸다.
///
/// 입자 하나하나를 위젯으로 만들지 않고 CustomPainter 하나로 직접 그린다 —
/// 개수가 적어도(20~30개) 위젯 트리 방식보다 훨씬 가볍다. 눈에 잘 안 띄는
/// 헤더 배경 연출이라 실패해도 안전하게 아무것도 안 그리는 쪽을 택한다
/// (날씨가 없거나 맑음/흐림이면 SizedBox.shrink).
class WeatherParticlesOverlay extends StatefulWidget {
  final KnueWeatherInfo? weather;
  const WeatherParticlesOverlay({super.key, required this.weather});

  @override
  State<WeatherParticlesOverlay> createState() =>
      _WeatherParticlesOverlayState();
}

class _WeatherParticlesOverlayState extends State<WeatherParticlesOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _rng = math.Random();
  _WeatherParticleKind? _kind;
  List<_WeatherParticle> _particles = const [];

  @override
  void initState() {
    super.initState();
    // 긴 주기로 반복시키고(실제 낙하 속도는 입자별 speed가 결정) 진행률만
    // 0→1로 계속 순환시킨다 — 배터리를 아끼려고 입자마다 컨트롤러를 두지 않는다.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant WeatherParticlesOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newKind = _kindFor(widget.weather);
    if (newKind != _kind) _rebuild();
  }

  _WeatherParticleKind? _kindFor(KnueWeatherInfo? w) {
    if (w == null) return null;
    if (w.isSnowing) return _WeatherParticleKind.snow;
    if (w.isRaining) return _WeatherParticleKind.rain;
    if (w.isColdOrWindy) return _WeatherParticleKind.wind;
    return null; // 맑음/흐림/더위는 굳이 입자를 안 더한다 — 은은해야 하니까.
  }

  void _rebuild() {
    final kind = _kindFor(widget.weather);
    setState(() {
      _kind = kind;
      if (kind == null) {
        _particles = const [];
        return;
      }
      final count = kind == _WeatherParticleKind.wind ? 5 : 24;
      _particles = List.generate(
        count,
        (_) => _WeatherParticle.random(_rng, kind),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    if (kind == null || _particles.isEmpty) return const SizedBox.shrink();
    // 헤더 콘텐츠(텍스트·버튼)의 탭을 가로채면 안 되고, 자주 다시 그리는
    // 레이어라 RepaintBoundary로 나머지 트리와 리페인트를 분리한다.
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _WeatherParticlePainter(
              particles: _particles,
              progress: _controller.value,
              kind: kind,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _WeatherParticlePainter extends CustomPainter {
  final List<_WeatherParticle> particles;
  final double progress;
  final _WeatherParticleKind kind;

  _WeatherParticlePainter({
    required this.particles,
    required this.progress,
    required this.kind,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case _WeatherParticleKind.rain:
        _paintRain(canvas, size);
        break;
      case _WeatherParticleKind.snow:
        _paintSnow(canvas, size);
        break;
      case _WeatherParticleKind.wind:
        _paintWind(canvas, size);
        break;
    }
  }

  void _paintRain(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const slant = 0.18; // 살짝 비스듬히 떨어지는 빗줄기
    for (final p in particles) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final travel = size.height + p.size * 2;
      final headY = t * travel - p.size;
      final headX = p.x * size.width + headY * slant;
      paint.color = Colors.white.withValues(alpha: p.opacity);
      canvas.drawLine(
        Offset(headX, headY),
        Offset(headX - p.size * slant, headY - p.size),
        paint,
      );
    }
  }

  void _paintSnow(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final y = t * (size.height + p.size * 2) - p.size;
      final x = p.x * size.width +
          math.sin(t * 2 * math.pi + p.phase * 10) * p.drift;
      paint.color = Colors.white.withValues(alpha: p.opacity);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  void _paintWind(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final p in particles) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final travel = size.width + p.size * 2;
      final headX = t * travel - p.size;
      final y = p.x * size.height; // x를 세로 위치로 재사용
      paint.color = Colors.white.withValues(alpha: p.opacity);
      canvas.drawLine(
        Offset(headX - p.size, y),
        Offset(headX, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherParticlePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.kind != kind;
}

/// 섹션 캡션 헤더. 좌측 타이틀 + 우측 선택적 액션("전체보기" 등).
/// 액션 색은 themeColor를 따른다 — iOS 블루(0xFF007AFF) 하드코딩 금지.
class KnueSectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;
  final Color? actionColor;

  const KnueSectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onAction,
    this.actionColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = actionColor ?? Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: KnueTokens.captionDark, // 라이트/다크 공용 중간 그레이
            ),
          ),
          if (actionText != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionText!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 14, color: color),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 표준 카드 셸: 서피스 + 헤어라인 + 이중 소프트 섀도 + 라운드 14.
/// 홈/식단/버스에 제각각 복붙되어 있던 BoxDecoration의 단일 출처.
class KnueCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;

  const KnueCard({
    super.key,
    required this.child,
    required this.isDark,
    this.padding,
    this.margin,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: KnueTokens.surface(isDark),
        borderRadius: BorderRadius.circular(radius ?? KnueTokens.radiusCard),
        border: Border.all(color: KnueTokens.hairline(isDark), width: 0.5),
        boxShadow: KnueTokens.cardShadow(isDark),
      ),
      child: child,
    );
  }
}

/// 상태 캡슐. 기본은 그레이스케일, [warm]일 때만 보조색(앰버) —
/// "제공중", 임박 D-Day, 라이브 신호처럼 지금 시간에 얽힌 것만 warm으로 켠다.
class KnueStatusChip extends StatelessWidget {
  final String label;
  final bool warm;
  final bool isDark;

  const KnueStatusChip({
    super.key,
    required this.label,
    required this.isDark,
    this.warm = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = warm ? KnueTokens.warm(isDark) : KnueTokens.caption(isDark);
    final bg = warm
        ? KnueTokens.warm(isDark).withValues(alpha: isDark ? 0.16 : 0.10)
        : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
          color: fg,
        ),
      ),
    );
  }
}

/// 은은하게 맥동하는 스켈레톤 박스. 로딩 스피너 대신 콘텐츠 자리를 미리 잡아
/// 화면이 덜컹이지 않게 한다. (버스 탭의 정적 shimmer 박스를 일반화)
class KnueSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final bool isDark;

  const KnueSkeleton({
    super.key,
    required this.width,
    required this.height,
    required this.isDark,
    this.radius = 8,
  });

  @override
  State<KnueSkeleton> createState() => _KnueSkeletonState();
}

class _KnueSkeletonState extends State<KnueSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base =
        widget.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE);
    final hi =
        widget.isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF7F7F7);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(base, hi, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// 실시간 데이터 옆에 붙는 라이브 인디케이터 — 앰버 점이 은은하게 맥동한다.
class KnueLiveDot extends StatefulWidget {
  final bool isDark;
  const KnueLiveDot({super.key, required this.isDark});

  @override
  State<KnueLiveDot> createState() => _KnueLiveDotState();
}

class _KnueLiveDotState extends State<KnueLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warm = KnueTokens.warm(widget.isDark);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: warm.withValues(alpha: 0.45 + 0.55 * _c.value),
        ),
      ),
    );
  }
}

