import SwiftUI
import WidgetKit

// KNUE Mate 식단 홈 위젯 (iOS).
//
// 데이터는 Flutter 쪽 home_widget 패키지가 App Group UserDefaults에 넣어준다.
// 키 이름은 lib/constants.dart의 _updateWidgetDataInternal()과 반드시 같아야
// 한다 — 한쪽만 바꾸면 위젯이 조용히 빈 값으로 나온다.
//
//   widget_title  String  식당 이름   (예: "기숙사 식당")
//   widget_time   String  때          (예: "오늘 점심")
//   widget_menu   String  메뉴 본문   (줄바꿈 포함)
//   themeMode     Int     ThemeMode.index (0 system / 1 light / 2 dark)
//   transparency  String  0.0~1.0 (double을 문자열로 저장한다)
//
// ⚠️ home_widget은 키 앞에 접두사를 붙이지 않는다. Flutter에서 저장한 키를
// 그대로 읽는다.

private let appGroupId = "group.knue.meal"

struct MealEntry: TimelineEntry {
    let date: Date
    let title: String
    let time: String
    let menu: String
    /// Flutter의 ThemeMode.index. 0 = system, 1 = light, 2 = dark.
    let themeModeIndex: Int
    /// 배경 투명도 0.0(불투명) ~ 1.0(완전 투명).
    let transparency: Double

    static let placeholder = MealEntry(
        date: Date(),
        title: "기숙사 식당",
        time: "오늘 점심",
        menu: "메뉴 정보를\n불러오는 중입니다...",
        themeModeIndex: 0,
        transparency: 0.0
    )
}

struct MealProvider: TimelineProvider {
    func placeholder(in context: Context) -> MealEntry {
        MealEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MealEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealEntry>) -> Void) {
        let entry = readEntry()
        // 앱이 갱신할 때마다 WidgetCenter.reloadTimelines가 불리지만, 앱을 한동안
        // 안 열어도 끼니가 바뀌면 값이 낡아 보인다. 한 시간마다 한 번은 스스로
        // 다시 그리게 해 둔다(데이터 자체는 앱이 넣어준 것을 그대로 읽는다).
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> MealEntry {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return MealEntry.placeholder
        }
        let title = defaults.string(forKey: "widget_title") ?? "KNUE Mate"
        let time = defaults.string(forKey: "widget_time") ?? ""
        let menu = defaults.string(forKey: "widget_menu") ?? "앱을 한 번 열면\n식단을 불러옵니다."
        // Flutter가 int로 저장하므로 integer로 읽는다. 값이 없으면 0(system).
        let themeModeIndex = defaults.object(forKey: "themeMode") as? Int ?? 0
        // transparency는 문자열로 저장된다("0.0" 등).
        let transparency = Double(defaults.string(forKey: "transparency") ?? "") ?? 0.0

        return MealEntry(
            date: Date(),
            title: title,
            time: time,
            menu: menu,
            themeModeIndex: themeModeIndex,
            transparency: max(0, min(1, transparency))
        )
    }
}

struct MealWidgetEntryView: View {
    var entry: MealEntry
    @Environment(\.colorScheme) private var systemColorScheme

    /// 앱 설정의 위젯 테마를 우선하고, "시스템"이면 기기 설정을 따른다.
    private var isDark: Bool {
        switch entry.themeModeIndex {
        case 1: return false
        case 2: return true
        default: return systemColorScheme == .dark
        }
    }

    private var backgroundColor: Color {
        let base = isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color.white
        return base.opacity(1.0 - entry.transparency)
    }

    private var titleColor: Color { isDark ? .white : .black }
    private var menuColor: Color {
        isDark ? Color.white.opacity(0.8) : Color(red: 0.2, green: 0.2, blue: 0.2)
    }
    // 안드로이드 위젯과 같은 강조색.
    private var accentColor: Color { Color(red: 0.26, green: 0.52, blue: 0.96) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(entry.time)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentColor)
                    .lineLimit(1)
            }

            Text(entry.menu)
                .font(.system(size: 13))
                .foregroundColor(menuColor)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .widgetBackground(backgroundColor)
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

struct MealWidget: Widget {
    // ⚠️ 이 kind 문자열은 Flutter의 HomeWidget.updateWidget(iOSName:)과 같아야
    // 한다. 다르면 앱이 갱신해도 위젯이 다시 그려지지 않는다.
    let kind: String = "MealWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MealProvider()) { entry in
            MealWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("청람 밥상")
        .description("오늘의 학식 메뉴를 홈 화면에서 바로 봅니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MealWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealWidget()
    }
}
