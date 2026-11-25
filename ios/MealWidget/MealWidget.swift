import AppIntents
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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
    /// 식당 바꾸기 버튼을 보일지(한 주치에 식당이 둘 이상, iOS 17+).
    var canToggleSource: Bool = false

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
        completion(readEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        // 한 주치(meal_week_json)가 있으면 끼니가 끝나는 때마다 엔트리를 넣어 위젯이
        // 스스로 점심 → 저녁 → 내일 아침으로 넘어간다. 앱을 안 열어도 된다.
        var dates: Set<Date> = [now]
        if let week = readMealWeek() {
            for d in mealWidgetSwitchDates(week, now: now, calendar: cal) { dates.insert(d) }
        }
        let entries = dates.sorted().map { readEntry(at: $0) }
        // 6시간마다는 다시 만든다(앱이 새 식단을 넣었는데 reload를 못 받은 경우 대비).
        let next = cal.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(21600)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func readMealWeek() -> [String: Any]? { readMealWeekJson() }

    private func readEntry(at date: Date) -> MealEntry {
        guard let defaults = sharedDefaults() else {
            return MealEntry.placeholder
        }
        let theme = WidgetThemeSettings.read(defaults)
        if let week = readMealWeek(),
           let r = resolveMealWidget(week, now: date, source: defaults.string(forKey: kMealWidgetSourceKey)) {
            return MealEntry(date: date, title: r.title, time: r.time, menu: r.menu, theme: theme,
                             canToggleSource: nextMealWidgetSource(week, current: nil) != nil)
        }
        // 옛 키 — 앱이 아직 한 주치를 넣지 않았을 때(업데이트 직후).
        let title = defaults.string(forKey: "widget_title") ?? "KNUE Mate"
        let time = defaults.string(forKey: "widget_time") ?? ""
        let menu = defaults.string(forKey: "widget_menu") ?? kMealWidgetNoData

        return MealEntry(date: date, title: title, time: time, menu: menu, theme: theme)
    }
}

// ── 한 주치 식단에서 끼니 고르기 ──
// Dart lib/meal_widget.dart의 resolveMealWidget과 같은 규칙이다(Kotlin
// MealWidgetProvider.resolve도). 기준 표는 test/meal_widget_test.dart:
//
// | 지금(기숙사) | 머리글 | 메뉴 |
// |---|---|---|
// | 수 08:00 | 오늘 아침 | 그날 아침 |
// | 수 09:00:00 / 09:00:01 | 오늘 아침 / 오늘 점심 | (끝나는 분 00초까지 그 끼니) |
// | 수 19:30 | 내일 아침 | 목 아침 |
// | 금 20:00, 토 closed | 내일 아침 | 내일은 식당을 운영하지 않아요 🥺 |
// | 그날 캐시 없음 | — | 앱을 한 번 열면 식단을 불러옵니다. |
// | 그 끼니 빈 목록 | — | 등록된 메뉴가 없습니다. |

let kMealWidgetNoMenu = "등록된 메뉴가 없습니다."
/// 위젯 버튼으로 고른 식당 id. Dart kMealWidgetSourceKey와 같다 — 앱에서 위젯 식당을 바꾸면 지운다.
let kMealWidgetSourceKey = "meal_widget_source"

func readMealWeekJson() -> [String: Any]? {
    guard let raw = sharedDefaults()?.string(forKey: "meal_week_json"),
          let data = raw.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// 식당 바꾸기 버튼을 누르면 갈 식당 id. Dart nextMealWidgetSource와 같다:
/// [current]가 없으면 selected에서 출발, JSON 식당 순서대로 다음(끝이면 처음),
/// 식당이 하나뿐이면 nil.
func nextMealWidgetSource(_ week: [String: Any], current: String?) -> String? {
    guard let sources = week["sources"] as? [[String: Any]] else { return nil }
    let ids = sources.compactMap { $0["id"] as? String }
    guard ids.count >= 2 else { return nil }
    let from = current ?? week["selected"] as? String
    let i = ids.firstIndex(of: from ?? "") ?? -1
    return ids[(i + 1) % ids.count]
}

/// 위젯 안 "식당 바꾸기" 버튼(iOS 17+). 앱을 열지 않고 고른 식당을 App Group에 적는다 —
/// 끝나면 WidgetKit이 타임라인을 다시 만든다.
@available(iOSApplicationExtension 17.0, *)
struct ToggleMealSourceIntent: AppIntent {
    static let title: LocalizedStringResource = "식당 바꾸기"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = sharedDefaults()
        if let week = readMealWeekJson(),
           let next = nextMealWidgetSource(week, current: defaults?.string(forKey: kMealWidgetSourceKey)) {
            defaults?.set(next, forKey: kMealWidgetSourceKey)
        }
        return .result()
    }
}
let kMealWidgetNoData = "앱을 한 번 열면\n식단을 불러옵니다."

func mealWidgetClosedText(_ tomorrow: Bool) -> String {
    "\(tomorrow ? "내일" : "오늘")은 식당을 운영하지 않아요 🥺"
}

func mealWidgetDayKey(_ d: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// [now]와 같은 날 "HH:mm".
private func mealWidgetAt(_ now: Date, _ hhmm: String, calendar: Calendar) -> Date? {
    guard let m = busMinutes(hhmm) else { return nil }
    return calendar.date(byAdding: .minute, value: m, to: calendar.startOfDay(for: now))
}

private func mealWidgetSource(_ week: [String: Any], source: String?) -> [String: Any]? {
    guard let sources = week["sources"] as? [[String: Any]], !sources.isEmpty else { return nil }
    let want = source ?? week["selected"] as? String
    return sources.first { $0["id"] as? String == want } ?? sources.first
}

/// 지금 그릴 (식당, "오늘 점심", 메뉴). JSON이 깨졌으면 nil — 옛 키로 그린다.
func resolveMealWidget(_ week: [String: Any], now: Date, source: String? = nil,
                       calendar: Calendar = .current) -> (title: String, time: String, menu: String)? {
    guard let src = mealWidgetSource(week, source: source),
          let meals = src["meals"] as? [[String: Any]] else { return nil }
    let title = src["label"] as? String ?? ""
    if meals.isEmpty { return (title, "", kMealWidgetNoData) }
    var pick: [String: Any]? = nil
    var tomorrow = false
    for m in meals {
        if let end = (m["end"] as? String).flatMap({ mealWidgetAt(now, $0, calendar: calendar) }), now <= end {
            pick = m
            break
        }
    }
    if pick == nil {
        pick = meals.first
        tomorrow = true
    }
    let label = pick?["label"] as? String ?? ""
    let time = "\(tomorrow ? "내일" : "오늘") \(label)"
    let date = calendar.date(byAdding: .day, value: tomorrow ? 1 : 0, to: calendar.startOfDay(for: now)) ?? now
    guard let day = (src["days"] as? [String: Any])?[mealWidgetDayKey(date, calendar: calendar)] as? [String: Any] else {
        return (title, time, kMealWidgetNoData)
    }
    if day["closed"] as? Bool == true { return (title, time, mealWidgetClosedText(tomorrow)) }
    let items = (pick?["key"] as? String).flatMap { day[$0] as? [String] } ?? []
    return (title, time, items.isEmpty ? kMealWidgetNoMenu : items.map { "· " + $0 }.joined(separator: "\n"))
}

/// 위젯 글이 바뀌는 때: 오늘·내일 끼니가 끝난 바로 뒤(1초)와 자정.
func mealWidgetSwitchDates(_ week: [String: Any], now: Date, calendar: Calendar = .current) -> [Date] {
    guard let src = mealWidgetSource(week, source: nil),
          let meals = src["meals"] as? [[String: Any]] else { return [] }
    let today = calendar.startOfDay(for: now)
    var out: [Date] = []
    for offset in 0...1 {
        guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
        if offset > 0 { out.append(day) }  // 자정: "내일 아침" → "오늘 아침"
        for m in meals {
            if let end = (m["end"] as? String).flatMap({ mealWidgetAt(day, $0, calendar: calendar) }) {
                out.append(end.addingTimeInterval(1))
            }
        }
    }
    return out.filter { $0 > now }
}

/// small 위젯 메뉴 줄. [rows]줄 안에 다 들어가면 한 줄에 하나씩("· " 머리).
/// 아니면 메뉴를 앞에서부터 " · "로 이어 붙이되 한 줄 폭([maxWidth])을
/// 넘기 전에 줄을 바꾼다 — 메뉴 이름이 줄 끝에서 끊기거나 줄 끝에 "·"가 남지 않는다.
/// 줄이 [rows]개를 넘으면 마지막 줄 끝을 "외 N개"로(들어가게 앞 메뉴를 뺀다).
/// 폭보다 긴 메뉴는 혼자 한 줄(그리는 쪽에서 글자를 줄인다).
/// [width]는 글자 폭을 재는 함수 — 위젯에선 13pt 시스템 글꼴로 잰다.
let kMealMenuSeparator = " · "

func mealMenuFlowLines(_ items: [String], rows: Int, maxWidth: CGFloat,
                       width: (String) -> CGFloat) -> [String] {
    // 다 들어가면 한 줄에 하나씩이 가장 읽기 쉽다.
    if items.count <= max(1, rows) { return items.map { "· " + $0 } }
    var lines: [[String]] = []
    for item in items {
        if var last = lines.last,
           width((last + [item]).joined(separator: kMealMenuSeparator)) <= maxWidth {
            last.append(item)
            lines[lines.count - 1] = last
        } else {
            lines.append([item])
        }
    }
    let rows = max(1, rows)
    if lines.count <= rows { return lines.map { $0.joined(separator: kMealMenuSeparator) } }
    var kept = Array(lines[..<rows])
    var last = kept.removeLast()
    // 줄이 넘쳤으니 rest는 1 이상이다.
    var rest = items.count - kept.reduce(0) { $0 + $1.count } - last.count
    while !last.isEmpty,
          width((last + ["외 \(rest)개"]).joined(separator: kMealMenuSeparator)) > maxWidth {
        last.removeLast()
        rest += 1
    }
    return kept.map { $0.joined(separator: kMealMenuSeparator) }
        + [(last + ["외 \(rest)개"]).joined(separator: kMealMenuSeparator)]
}

/// 큰 머리글로 쓸 끼니와 보조 줄로 쓸 날. "오늘 점심" → ("점심", "오늘").
/// 띄어쓰기가 없으면 통째로 끼니, 비었으면 "식단".
func mealHeaderParts(_ time: String) -> (meal: String, day: String) {
    let t = time.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return ("식단", "") }
    guard let sp = t.lastIndex(of: " ") else { return (t, "") }
    return (String(t[t.index(after: sp)...]), String(t[..<sp]).trimmingCharacters(in: .whitespaces))
}

/// 메뉴가 아니라 안내 문구인지("앱을 한 번 열면…", "내일은 식당을 운영하지 않아요").
/// 앱은 메뉴 줄마다 "· "를 붙여 넣는다.
func mealMenuIsMessage(_ menu: String) -> Bool {
    !menu.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("·") }
}

/// 메뉴 본문을 한 줄에 하나씩 나눈다. 앱이 붙인 "· " 머리는 뗀다.
func mealMenuItems(_ menu: String) -> [String] {
    menu.split(separator: "\n").map { line -> String in
        var item = line.trimmingCharacters(in: .whitespaces)
        if item.hasPrefix("·") { item.removeFirst() }
        return item.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
}

/// medium 위젯 메뉴 열. 한 열에 다 들어가면 한 열, 넘치면 두 열로 고르게
/// (왼쪽이 하나 더) 나눈다. 두 열에도 넘치면 마지막 칸을 "외 N개"로 — 줄바꿈으로
/// 이어 쓰면 메뉴 이름이 줄 끝에서 들쭉날쭉 끊겨 보였다.
func mealMenuColumns(_ items: [String], rows: Int) -> [[String]] {
    let rows = max(1, rows)
    if items.count <= rows { return [items] }
    if items.count <= rows * 2 {
        let left = (items.count + 1) / 2
        return [Array(items[..<left]), Array(items[left...])]
    }
    let shown = rows * 2 - 1
    return [Array(items[..<rows]),
            Array(items[rows..<shown]) + ["외 \(items.count - shown)개"]]
}

/// 메뉴가 적으면 글자를 키워 칸 아래가 비지 않게 한다. 이 크기들 중 메뉴가 다
/// 들어가는(“외 N개” 없이) 가장 큰 것을 쓰고, 다 안 들어가면 13pt에 “외 N개”.
let kMealMenuFontSizes: [CGFloat] = [16, 15, 14, 13]
let kMealMenuMinGap: CGFloat = 3
/// 남는 높이는 줄 사이에 나누되 이보다 벌리면 줄끼리 떨어져 보인다.
let kMealMenuMaxGap: CGFloat = 10

/// 글자 [size]pt 한 줄 높이.
func mealMenuLineHeight(_ size: CGFloat) -> CGFloat { size + 3 }

/// 줄 사이 간격 — 남는 높이를 나누되 [kMealMenuMinGap]~[kMealMenuMaxGap].
func mealMenuRowGap(height: CGFloat, lines: Int, lineHeight: CGFloat) -> CGFloat {
    guard lines > 1 else { return kMealMenuMinGap }
    let gap = (height - CGFloat(lines) * lineHeight) / CGFloat(lines - 1)
    return min(kMealMenuMaxGap, max(kMealMenuMinGap, gap))
}

/// 높이 [height]에 글자 [size]pt 줄이 몇 개 들어가는지(최소 간격 기준).
func mealMenuCapacity(height: CGFloat, size: CGFloat) -> Int {
    max(1, Int((height + kMealMenuMinGap) / (mealMenuLineHeight(size) + kMealMenuMinGap)))
}

struct MealMenuFit {
    let size: CGFloat
    let gap: CGFloat
    /// small: 한 열(줄 목록). medium: 한 열 또는 두 열.
    let columns: [[String]]
    var lines: [String] { columns.first ?? [] }
}

private func isOverflow(_ cells: [String]) -> Bool {
    guard let last = cells.last else { return false }
    return last.hasSuffix("개") && (last.hasPrefix("외 ") || last.contains(kMealMenuSeparator + "외 "))
}

/// small 위젯 메뉴 배치. [width]는 (글, 글자 크기) → 폭.
func mealMenuFitSmall(_ items: [String], height: CGFloat, maxWidth: CGFloat,
                      width: (String, CGFloat) -> CGFloat) -> MealMenuFit {
    var lines: [String] = []
    var size = kMealMenuFontSizes.last!
    for z in kMealMenuFontSizes {
        size = z
        lines = mealMenuFlowLines(items, rows: mealMenuCapacity(height: height, size: z),
                                  maxWidth: maxWidth, width: { width($0, z) })
        if !isOverflow(lines) { break }
    }
    let gap = mealMenuRowGap(height: height, lines: lines.count, lineHeight: mealMenuLineHeight(size))
    return MealMenuFit(size: size, gap: gap, columns: [lines])
}

/// medium 위젯 메뉴 배치(메뉴 하나에 한 줄, 넘치면 두 열).
func mealMenuFitMedium(_ items: [String], height: CGFloat) -> MealMenuFit {
    var columns: [[String]] = []
    var size = kMealMenuFontSizes.last!
    for z in kMealMenuFontSizes {
        size = z
        columns = mealMenuColumns(items, rows: mealMenuCapacity(height: height, size: z))
        if !isOverflow(columns.last ?? []) { break }
    }
    let gap = mealMenuRowGap(height: height, lines: columns.map(\.count).max() ?? 0,
                             lineHeight: mealMenuLineHeight(size))
    return MealMenuFit(size: size, gap: gap, columns: columns)
}

struct MealWidgetEntryView: View {
    var entry: MealEntry
    var env: WidgetEnv = WidgetEnv()
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.widgetFamily) private var family

    private var palette: WidgetPalette { WidgetPalette(entry.theme, system: systemColorScheme, env: env) }

    var body: some View {
        let header = mealHeaderParts(entry.time)
        let items = mealMenuItems(entry.menu)
        let isMessage = mealMenuIsMessage(entry.menu)
        Group {
            if family == .systemSmall {
                // small: 큰 끼니 머리글(밑에 테마 색 가로 막대) + 식당·날 한 줄, 아래에 메뉴 묶음.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 4) {
                        WidgetBigHeader(title: header.meal,
                                        subs: [[entry.title, header.day].filter { !$0.isEmpty }
                                            .joined(separator: " · ")],
                                        palette: palette, size: WidgetType.headerSmall, underline: palette.accent, underlineWidth: 48)
                        Spacer(minLength: 0)
                        sourceToggle
                    }
                    GeometryReader { geo in
                        if isMessage {
                            messageText
                        } else {
                            let fit = mealMenuFitSmall(items, height: geo.size.height,
                                                       maxWidth: geo.size.width,
                                                       width: { mealMenuTextWidth($0, size: $1) })
                            VStack(alignment: .leading, spacing: fit.gap) {
                                ForEach(Array(fit.lines.enumerated()), id: \.offset) { _, line in
                                    menuLine(line, size: fit.size)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
            } else {
                // medium: 왼쪽에 큰 끼니·식당·날, 오른쪽에 메뉴(하나에 한 줄, 넘치면 두 열).
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        WidgetBigHeader(title: header.meal,
                                        subs: [entry.title, header.day].filter { !$0.isEmpty },
                                        palette: palette, underline: palette.accent, underlineWidth: 72)
                        Spacer(minLength: 0)
                        sourceToggle
                    }
                    .frame(width: 84, alignment: .leading)
                    GeometryReader { geo in
                        if isMessage {
                            messageText
                        } else {
                            let fit = mealMenuFitMedium(items, height: geo.size.height)
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(Array(fit.columns.enumerated()), id: \.offset) { _, column in
                                    VStack(alignment: .leading, spacing: fit.gap) {
                                        ForEach(Array(column.enumerated()), id: \.offset) { _, item in
                                            menuLine(item, size: fit.size)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WidgetSpace.padding)
        .widgetBackground(palette.background)
        // 위젯을 누르면 앱이 이 URL로 열린다. Flutter 쪽(main.dart)이
        // home_widget의 클릭 스트림에서 이 host("meal")를 보고 식단 탭으로
        // 이동한다. 스킴은 Runner Info.plist의 CFBundleURLSchemes와 같아야 한다.
        .widgetURL(URL(string: "knuemate://meal?homeWidget"))
    }

    /// 식당 바꾸기 버튼(iOS 17+, 식당이 둘 이상일 때). 그 밖엔 아무것도 없다 —
    /// 위젯을 누르면 앱이 열리는 것은 그대로.
    @ViewBuilder
    private var sourceToggle: some View {
        if #available(iOSApplicationExtension 17.0, *), entry.canToggleSource {
            Button(intent: ToggleMealSourceIntent()) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: WidgetType.caption, weight: .semibold))
                    .foregroundColor(palette.muted)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(palette.muted.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("식당 바꾸기")
        }
    }

    /// 메뉴 대신 안내 문구(앱을 열어야 함·운영 안 함).
    private var messageText: some View {
        WidgetMessage(text: entry.menu, palette: palette)
            .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

extension MealWidgetEntryView {
    /// 한 줄. 끝의 "외 N개"는 흐리게, 구분점도 흐리게.
    @ViewBuilder
    func menuLine(_ line: String, size: CGFloat) -> some View {
        let parts = line.components(separatedBy: kMealMenuSeparator)
        parts.enumerated().reduce(Text("")) { acc, p in
            let (i, part) = p
            let sep = i == 0 ? Text("") : Text(kMealMenuSeparator).foregroundColor(palette.muted)
            let more = part.hasPrefix("외 ") && i == parts.count - 1 && part.hasSuffix("개")
            return acc + sep + Text(part).foregroundColor(more ? palette.muted : palette.title)
        }
        .font(.system(size: size, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(height: mealMenuLineHeight(size), alignment: .leading)
    }
}

/// [size]pt 시스템 글꼴(medium)로 잰 글자 폭(pt). 조금 여유를 둬서 실제 그릴 때 넘치지 않게.
func mealMenuTextWidth(_ s: String, size: CGFloat) -> CGFloat {
    #if canImport(UIKit)
    let font = UIFont.systemFont(ofSize: size, weight: .medium)
    #else
    let font = NSFont.systemFont(ofSize: size, weight: .medium)
    #endif
    return ceil((s as NSString).size(withAttributes: [.font: font]).width) + 2
}

struct MealWidget: Widget {
    // ⚠️ 이 kind 문자열은 Flutter의 HomeWidget.updateWidget(iOSName:)과 같아야
    // 한다. 다르면 앱이 갱신해도 위젯이 다시 그려지지 않는다.
    let kind: String = "MealWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MealProvider()) { entry in
            WidgetEnvReader { env in MealWidgetEntryView(entry: entry, env: env) }
        }
        .configurationDisplayName("청람 밥상")
        .description("오늘의 학식 메뉴를 홈 화면에서 바로 봅니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .ownContentMargins()
    }
}

@main
struct MealWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealWidget()
        BusWidget()
        BusNextWidget()
        NoticeWidget()
    }
}
