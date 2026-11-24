import SwiftUI
import WidgetKit

// 식단·버스·공지 위젯이 같이 쓰는 것: App Group, 테마·투명도, 배경.
//
// 테마·투명도 키는 식단 위젯 설정(lib/constants.dart의
// _updateWidgetDataInternal)이 넣는다 — 모든 위젯에 같이 적용된다.
//
//   themeMode     Int     ThemeMode.index (0 system / 1 light / 2 dark)
//   transparency  String  0.0~1.0 (double을 문자열로 저장한다)

let appGroupId = "group.knue.meal"

func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupId)
}

struct WidgetThemeSettings {
    /// Flutter의 ThemeMode.index. 0 = system, 1 = light, 2 = dark.
    var themeModeIndex: Int = 0
    /// 배경 투명도 0.0(불투명) ~ 1.0(완전 투명).
    var transparency: Double = 0.0

    static func read(_ defaults: UserDefaults?) -> WidgetThemeSettings {
        guard let defaults = defaults else { return WidgetThemeSettings() }
        // Flutter가 int로 저장하므로 integer로 읽는다. 값이 없으면 0(system).
        let index = defaults.object(forKey: "themeMode") as? Int ?? 0
        // transparency는 문자열로 저장된다("0.0" 등).
        let t = Double(defaults.string(forKey: "transparency") ?? "") ?? 0.0
        return WidgetThemeSettings(themeModeIndex: index, transparency: max(0, min(1, t)))
    }
}

/// 앱 설정의 위젯 테마를 우선하고, "시스템"이면 기기 설정을 따른다.
struct WidgetPalette {
    let isDark: Bool
    let transparency: Double

    init(_ settings: WidgetThemeSettings, system: ColorScheme) {
        switch settings.themeModeIndex {
        case 1: isDark = false
        case 2: isDark = true
        default: isDark = system == .dark
        }
        transparency = settings.transparency
    }

    var background: Color {
        let base = isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color.white
        return base.opacity(1.0 - transparency)
    }

    var title: Color { isDark ? .white : .black }
    var body: Color {
        isDark ? Color.white.opacity(0.8) : Color(red: 0.2, green: 0.2, blue: 0.2)
    }
    var muted: Color {
        isDark ? Color.white.opacity(0.5) : Color(red: 0.55, green: 0.55, blue: 0.55)
    }
    // 안드로이드 위젯과 같은 강조색.
    var accent: Color { Color(red: 0.26, green: 0.52, blue: 0.96) }
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
