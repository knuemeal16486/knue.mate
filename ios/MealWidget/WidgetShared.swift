import SwiftUI
import WidgetKit

// 식단·버스·공지 위젯이 같이 쓰는 것: App Group, 테마·투명도, 배경.
//
// 테마·투명도 키는 식단 위젯 설정(lib/constants.dart의
// _updateWidgetDataInternal)이 넣는다 — 모든 위젯에 같이 적용된다.
//
//   themeMode     Int     ThemeMode.index (0 system / 1 light / 2 dark)
//   transparency  String  0.0~1.0 (double을 문자열로 저장한다)
//   accent_light  String  "#RRGGBB" 앱 테마 색(흰 배경용) — lib/home_widgets.dart pushWidgetAccent
//   accent_dark   String  "#RRGGBB" 앱 테마 색(어두운 배경용)

let appGroupId = "group.knue.meal"

func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupId)
}

struct WidgetThemeSettings {
    /// Flutter의 ThemeMode.index. 0 = system, 1 = light, 2 = dark.
    var themeModeIndex: Int = 0
    /// 배경 투명도 0.0(불투명) ~ 1.0(완전 투명).
    var transparency: Double = 0.0
    /// 앱 테마 색. 없으면(앱이 아직 안 넣음) 기본 파랑.
    var accentLight: Color? = nil
    var accentDark: Color? = nil

    static func read(_ defaults: UserDefaults?) -> WidgetThemeSettings {
        guard let defaults = defaults else { return WidgetThemeSettings() }
        // Flutter가 int로 저장하므로 integer로 읽는다. 값이 없으면 0(system).
        let index = defaults.object(forKey: "themeMode") as? Int ?? 0
        // transparency는 문자열로 저장된다("0.0" 등).
        let t = Double(defaults.string(forKey: "transparency") ?? "") ?? 0.0
        return WidgetThemeSettings(themeModeIndex: index, transparency: max(0, min(1, t)),
                                   accentLight: widgetHexColor(defaults.string(forKey: "accent_light")),
                                   accentDark: widgetHexColor(defaults.string(forKey: "accent_dark")))
    }
}

/// "#RRGGBB" → Color. 형식이 틀리면 nil.
func widgetHexColor(_ hex: String?) -> Color? {
    guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
    h.removeFirst()
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return Color(red: Double((v >> 16) & 0xFF) / 255,
                 green: Double((v >> 8) & 0xFF) / 255,
                 blue: Double(v & 0xFF) / 255)
}

/// 투명도가 이 값 이상이면 배경화면 위 글씨로 보고 진하게 쓴다. Android WidgetColors와 같다.
let kWidgetOnWallpaperTransparency = 0.7

/// 앱 설정의 위젯 테마를 우선하고, "시스템"이면 기기 설정을 따른다.
struct WidgetPalette {
    let isDark: Bool
    let transparency: Double
    private let accentLight: Color?
    private let accentDark: Color?

    init(_ settings: WidgetThemeSettings, system: ColorScheme, env: WidgetEnv = WidgetEnv()) {
        // 배경이 빠진 자리(StandBy 등)는 시스템이 깐 바탕 위라 앱 테마(라이트 고정 등)를
        // 따르면 검은 바탕에 검은 글씨가 된다 — 그땐 기기 설정을 따른다.
        switch (env.showsBackground ? settings.themeModeIndex : 0) {
        case 1: isDark = false
        case 2: isDark = true
        default: isDark = system == .dark
        }
        transparency = env.showsBackground ? settings.transparency : 1
        accentLight = settings.accentLight
        accentDark = settings.accentDark
    }

    var background: Color {
        let base = isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color.white
        return base.opacity(1.0 - transparency)
    }

    var title: Color { isDark ? .white : .black }
    var body: Color {
        isDark ? Color.white.opacity(0.8) : Color(red: 0.2, green: 0.2, blue: 0.2)
    }
    /// 배경이 거의 투명해 배경화면 위에 글씨가 바로 놓이는지. 이때는 흐린 글씨·주황을
    /// 진하게 한다 — 밝은 배경화면에서 회색·연주황이 묻혀 안 읽혔다.
    var onWallpaper: Bool { transparency >= kWidgetOnWallpaperTransparency }

    var muted: Color {
        if onWallpaper {
            return isDark ? Color.white.opacity(0.8) : Color(red: 0.22, green: 0.22, blue: 0.22)
        }
        return isDark ? Color.white.opacity(0.5) : Color(red: 0.55, green: 0.55, blue: 0.55)
    }
    /// 머리글 강조색 — 앱 테마 색(없으면 기본 파랑, Android와 같은 값).
    var accent: Color {
        (isDark ? accentDark : accentLight) ?? Color(red: 0.26, green: 0.52, blue: 0.96)
    }
    /// 가장 먼저 오는 버스처럼 눈에 띄어야 하는 것. 공지 게시판 주황과 같은 값.
    var highlight: Color {
        if onWallpaper && !isDark { return Color(red: 0.72, green: 0.30, blue: 0.0) }  // #B84D00
        return isDark ? Color(red: 0.99, green: 0.68, blue: 0.44) : Color(red: 0.91, green: 0.44, blue: 0.04)
    }
}

// iOS 17부터 위젯 배경은 containerBackground로 줘야 한다. 16 이하에서는
// 그 API가 없어 예전 방식(ZStack 배경)을 쓴다 — 둘 다 지원하려면 분기가 필요.
extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }
}

// iOS 17부터 시스템이 위젯 가장자리에 여백(약 16pt)을 자동으로 넣는다. 각 위젯은
// 직접 .padding(14)을 주므로 그대로 두면 여백이 두 번 들어가 칸이 좁아진다
// (small 식단 위젯에 메뉴가 3줄밖에 안 보였다). 시스템 여백은 끄고 우리 여백만 쓴다 —
// iOS 16 이하는 원래 시스템 여백이 없어 같은 모양이 된다.
extension WidgetConfiguration {
    func ownContentMargins() -> some WidgetConfiguration {
        if #available(iOSApplicationExtension 17.0, *) {
            return contentMarginsDisabled()
        } else {
            return self
        }
    }
}

// ── 에브리타임식 공용 부품 ──
// 크고 굵은 머리글 + 흐린 보조 줄, 항목마다 왼쪽 옅은 색 막대.

/// 항목 왼쪽의 옅은 세로 막대. 높이는 쓰는 쪽에서 정한다.
/// 시스템이 색을 칠하는 모드(틴트 홈 화면·잠금화면)에선 옅으면 안 보여서 진하게,
/// 강조색 무리로 넣는다.
struct WidgetBar: View {
    let color: Color
    var env: WidgetEnv = WidgetEnv()
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color.opacity(env.fullColor ? 0.4 : 1))
            .frame(width: 3)
            .widgetAccentableCompat()
    }
}

/// 큰 굵은 머리글(예: "점심")과 그 아래 흐린 보조 줄.
struct WidgetBigHeader: View {
    let title: String
    let subs: [String]
    let palette: WidgetPalette
    var size: CGFloat = WidgetType.headerLarge
    /// 제목 바로 밑 짧은 가로 막대 색(식단 위젯 — 앱 테마 색). nil이면 없음.
    var underline: Color? = nil
    /// 가로 막대 길이(pt). 식단 small 48, medium 72(Android meal_top_line·meal_side_line과 같다).
    var underlineWidth: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(palette.title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentableCompat()
            if let underline {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(underline)
                    .frame(width: underlineWidth, height: 3)
                    .padding(.top, 3)
                    .padding(.bottom, 3)
                    .widgetAccentableCompat()
            }
            ForEach(Array(subs.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.system(size: WidgetType.sub))
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// "RRGGBB" 정수 → Color.
func widgetRGB(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255,
          green: Double((v >> 8) & 0xFF) / 255,
          blue: Double(v & 0xFF) / 255)
}

// ── 글자·여백 규칙 ──
// 세 위젯이 같은 값을 쓴다. Android res/values/widget_dimens.xml과 같다
// (test/native_id_consistency_test.dart가 맞춰 본다). 화면 코드에 숫자를 직접 쓰지 않는다.
enum WidgetType {
    /// 넓은 위젯 왼쪽 칸·큰 위젯 머리글("점심"·"버스"·"공지").
    static let headerLarge: CGFloat = 24
    /// 좁은 위젯·한 줄 머리글.
    static let headerSmall: CGFloat = 20
    /// 곧 떠나는 차(small)의 노선·시각.
    static let emphasis: CGFloat = 16
    static let emphasisSub: CGFloat = 14
    /// 본문 — 메뉴·노선·공지 제목·안내 문구.
    static let body: CGFloat = 13
    /// 머리글 아래 보조 줄.
    static let sub: CGFloat = 12
    /// 시각·게시판·"N분 뒤".
    static let caption: CGFloat = 11
}

enum WidgetSpace {
    static let padding: CGFloat = 14
}

// ── 시스템이 위젯을 어떻게 그리는지 ──

/// iOS 16+ 렌더링 모드(틴트 홈 화면·잠금화면은 fullColor가 아니다)와
/// iOS 17+ 배경 표시 여부(StandBy 등에선 시스템이 배경을 뺀다).
struct WidgetEnv {
    var fullColor = true
    var showsBackground = true
}

/// [WidgetEnv]를 읽어 넘긴다. 배포 대상이 iOS 15라 @Environment를 버전별로 가른다.
struct WidgetEnvReader<Content: View>: View {
    @ViewBuilder let content: (WidgetEnv) -> Content

    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            WidgetEnvReader17(content: content)
        } else if #available(iOSApplicationExtension 16.0, *) {
            WidgetEnvReader16(content: content)
        } else {
            content(WidgetEnv())
        }
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct WidgetEnvReader17<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let content: (WidgetEnv) -> Content
    var body: some View {
        content(WidgetEnv(fullColor: mode == .fullColor, showsBackground: showsBackground))
    }
}

@available(iOSApplicationExtension 16.0, *)
private struct WidgetEnvReader16<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    let content: (WidgetEnv) -> Content
    var body: some View {
        content(WidgetEnv(fullColor: mode == .fullColor))
    }
}

extension View {
    /// 틴트 모드에서 강조색으로 칠할 무리(머리글·막대·가장 먼저 오는 차). iOS 15는 그대로.
    @ViewBuilder
    func widgetAccentableCompat(_ on: Bool = true) -> some View {
        if #available(iOSApplicationExtension 16.0, *) {
            widgetAccentable(on)
        } else {
            self
        }
    }
}

/// 비어 있음·오래됨·운영 없음 안내. 세 위젯이 같은 모양이다.
struct WidgetMessage: View {
    let text: String
    let palette: WidgetPalette
    var body: some View {
        Text(text)
            .font(.system(size: WidgetType.body))
            .foregroundColor(palette.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
