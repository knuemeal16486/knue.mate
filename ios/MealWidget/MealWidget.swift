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
//   themeMode·transparency는 WidgetShared.swift
//
// ⚠️ home_widget은 키 앞에 접두사를 붙이지 않는다. Flutter에서 저장한 키를
// 그대로 읽는다.

struct MealEntry: TimelineEntry {
    let date: Date
    let title: String
    let time: String
    let menu: String
    let theme: WidgetThemeSettings

    static let placeholder = MealEntry(
        date: Date(),
        title: "기숙사 식당",
        time: "오늘 점심",
        menu: "메뉴 정보를\n불러오는 중입니다...",
        theme: WidgetThemeSettings()
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
        guard let defaults = sharedDefaults() else {
            return MealEntry.placeholder
        }
        let title = defaults.string(forKey: "widget_title") ?? "KNUE Mate"
        let time = defaults.string(forKey: "widget_time") ?? ""
        let menu = defaults.string(forKey: "widget_menu") ?? "앱을 한 번 열면\n식단을 불러옵니다."

        return MealEntry(
            date: Date(),
            title: title,
            time: time,
            menu: menu,
            theme: WidgetThemeSettings.read(defaults)
        )
    }
}

/// 한 줄에 하나씩 [maxLines]개가 넘으면 " · "로 이어 쓴다 — 넘친 메뉴가
/// 말없이 잘리지 않게. 메뉴 안에서는 줄이 바뀌지 않게 글자 사이에 U+2060
/// (WORD JOINER)을, 낱말 사이에 NBSP를 넣는다. Android MealWidgetProvider.fitMenu와
/// 같은 방식이다.
func fitMealMenu(_ menu: String, maxLines: Int) -> String {
    let lines = menu.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    if lines.count <= maxLines { return lines.joined(separator: "\n") }
    return lines.map { line -> String in
        var item = line
        if item.hasPrefix("·") { item.removeFirst() }
        item = item.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "\u{00A0}")
        return item.map { String($0) }.joined(separator: "\u{2060}")
    }.joined(separator: "\u{00A0}· ")
}

/// 메뉴 칸 높이(pt)에 들어가는 줄 수. 13pt 한 줄은 줄 간격까지 약 19pt.
/// small 위젯 높이가 기기마다 141~170pt라 크기 종류(family)로는 못 정하고,
/// 실제 칸 높이(GeometryReader)로 정한다.
func mealMenuCapacity(menuHeight: CGFloat) -> Int {
    max(1, Int(menuHeight / 19))
}

struct MealWidgetEntryView: View {
    var entry: MealEntry
    @Environment(\.colorScheme) private var systemColorScheme

    private var palette: WidgetPalette { WidgetPalette(entry.theme, system: systemColorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 끼니를 식당 이름 위에 둔다 — 한 줄에 나란히 두면 small에서
            // 이름이 "기숙…"처럼 잘린다(Android 2×2에서 실제로 났다).
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.time)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.accent)
                    .lineLimit(1)
                Text(entry.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(palette.title)
                    .lineLimit(1)
            }

            GeometryReader { geo in
                Text(fitMealMenu(entry.menu, maxLines: mealMenuCapacity(menuHeight: geo.size.height)))
                    .font(.system(size: 13))
                    .foregroundColor(palette.body)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(14)
        .widgetBackground(palette.background)
        // 위젯을 누르면 앱이 이 URL로 열린다. Flutter 쪽(main.dart)이
        // home_widget의 클릭 스트림에서 이 host("meal")를 보고 식단 탭으로
        // 이동한다. 스킴은 Runner Info.plist의 CFBundleURLSchemes와 같아야 한다.
        .widgetURL(URL(string: "knuemate://meal?homeWidget"))
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
        BusWidget()
        NoticeWidget()
    }
}
