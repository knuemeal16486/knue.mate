import SwiftUI
import WidgetKit

// KNUE Mate 버스 시간표 위젯 (iOS) — 학교에서 나가는 차의 다음 출발 시각.
//
// 시간표는 앱이 위젯 저장소에 넣는다(lib/home_widgets.dart의
// busWidgetTimetableJson, 키 "bus_timetable_json"):
//
//   {"v":1,"routes":[{"label":"513","sub":"교원문화관",
//                     "weekday":["06:20",...],"holiday":[...]}, ...]}
//
// 위젯은 인터넷 없이 이 표로 스스로 다음 차를 고른다. 타임라인에 오늘 남은
// 출발 시각마다 엔트리를 넣어 두어, 차가 떠나는 분에 다음 차로 넘어간다.

/// Dart `nextDepartures`와 같은 규칙: "HH:mm" 중 지금 분보다 뒤인 것 앞에서
/// n대. 같은 분에 떠나는 차는 방금 떠난 차로 본다.
///
/// | 지금 | 시각표 06:20·14:27·15:35 | n | 결과 |
/// |---|---|---|---|
/// | 14:00 | | 2 | 14:27, 15:35 |
/// | 14:27:30 | | 2 | 15:35 |
/// | 00:05 | | 1 | 06:20 |
/// | 23:30 | | 2 | (없음) |
func nextDepartures(_ times: [String], now: Date, n: Int) -> [String] {
    let c = Calendar.current.dateComponents([.hour, .minute], from: now)
    let nowMin = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    var out: [String] = []
    for t in times {
        guard let m = busMinutes(t), m > nowMin else { continue }
        out.append(t)
        if out.count >= n { break }
    }
    return out
}

func busMinutes(_ hhmm: String) -> Int? {
    let parts = hhmm.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
    return h * 60 + m
}

/// 다음 차가 가장 먼저 오는 노선(같은 분이면 여럿). [firstMinutes]는 노선마다
/// 다음 차 출발 분(없으면 nil). Kotlin BusWidgetProvider.soonestRoutes와 같다.
func soonestRoutes(_ firstMinutes: [Int?]) -> Set<Int> {
    guard let best = firstMinutes.compactMap({ $0 }).min() else { return [] }
    return Set(firstMinutes.indices.filter { firstMinutes[$0] == best })
}

/// 모든 노선을 합쳐 지금 이후 떠나는 차를 시각 순으로 n대. 같은 분이면 노선 순서.
/// [routeTimes]는 노선마다 오늘 시각표. Kotlin BusWidgetProvider.upcomingDepartures와 같다.
///
/// | 지금 | 513: 14:27·15:35 / 518: 14:25·15:15 | n | 결과 |
/// |---|---|---|---|
/// | 14:00 | | 3 | 518 14:25, 513 14:27, 518 15:15 |
/// | 14:25 | | 2 | 513 14:27, 518 15:15 |
func upcomingDepartures(_ routeTimes: [[String]], now: Date, n: Int) -> [(route: Int, time: String)] {
    var all: [(route: Int, time: String, min: Int)] = []
    for (i, times) in routeTimes.enumerated() {
        for t in nextDepartures(times, now: now, n: n) {
            if let m = busMinutes(t) { all.append((i, t, m)) }
        }
    }
    all.sort { $0.min != $1.min ? $0.min < $1.min : $0.route < $1.route }
    return all.prefix(n).map { ($0.route, $0.time) }
}

/// 노선 막대 색 — 공지 게시판 색 목록(kNoticeBoardColors)에서 고른다:
/// 513 파랑, 514 초록, 518 주황, 913 평동행 보라, 913 미호행 분홍.
/// Kotlin BusWidgetProvider.ROUTE_COLOR_INDEX와 같다.
let kBusRouteColorIndex = [0, 1, 2, 3, 6]

func busRouteColor(_ route: Int, isDark: Bool) -> Color {
    let pair = kNoticeBoardColors[kBusRouteColorIndex[route % kBusRouteColorIndex.count]]
    return widgetRGB(isDark ? pair.dark : pair.light)
}

/// 앱 버스 화면과 같다: 토·일이면 주말 시간표.
func isBusHoliday(_ date: Date) -> Bool {
    let wd = Calendar.current.component(.weekday, from: date)  // 1 = 일, 7 = 토
    return wd == 1 || wd == 7
}

struct BusRoute: Decodable {
    let label: String
    let sub: String?
    let weekday: [String]
    let holiday: [String]

    func times(on date: Date) -> [String] { isBusHoliday(date) ? holiday : weekday }
}

private struct BusTimetable: Decodable {
    let v: Int
    let routes: [BusRoute]
}

struct BusEntry: TimelineEntry {
    let date: Date
    /// nil = 앱이 아직 시간표를 넣지 않았다.
    let routes: [BusRoute]?
    let theme: WidgetThemeSettings
}

struct BusProvider: TimelineProvider {
    func placeholder(in context: Context) -> BusEntry {
        BusEntry(date: Date(), routes: [], theme: WidgetThemeSettings())
    }

    func getSnapshot(in context: Context, completion: @escaping (BusEntry) -> Void) {
        let (routes, theme) = read()
        completion(BusEntry(date: Date(), routes: routes, theme: theme))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BusEntry>) -> Void) {
        let (routes, theme) = read()
        let now = Date()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let midnight = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? now.addingTimeInterval(3600)

        var dates: Set<Date> = [now]
        for route in routes ?? [] {
            for t in route.times(on: now) {
                guard let m = busMinutes(t),
                      let d = cal.date(byAdding: .minute, value: m, to: startOfDay),
                      d > now, d < midnight else { continue }
                // 떠나는 그 분에 넘어간다(같은 분은 지난 차 — 위 규칙).
                dates.insert(d)
            }
        }
        dates.insert(midnight)
        let entries = dates.sorted().map { BusEntry(date: $0, routes: routes, theme: theme) }
        // 자정 엔트리 뒤에 다시 만든다(그날 요일로).
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func read() -> ([BusRoute]?, WidgetThemeSettings) {
        let defaults = sharedDefaults()
        let theme = WidgetThemeSettings.read(defaults)
        guard let raw = defaults?.string(forKey: "bus_timetable_json"),
              let data = raw.data(using: .utf8),
              let table = try? JSONDecoder().decode(BusTimetable.self, from: data) else {
            return (nil, theme)
        }
        return (table.routes, theme)
    }
}

/// 버스 위젯 모양. 위젯 고르기 화면에 둘 다 있어 사용자가 고른다.
enum BusWidgetStyle {
    /// 노선마다 다음 차(노선 목록).
    case routes
    /// 가장 먼저 떠나는 차를 크게, 그다음 차들을 시각 순으로.
    case next
}

struct BusWidgetEntryView: View {
    var entry: BusEntry
    var style: BusWidgetStyle = .routes
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.widgetFamily) private var family

    private var palette: WidgetPalette { WidgetPalette(entry.theme, system: systemColorScheme) }
    private var isSmall: Bool { family == .systemSmall }
    private var dayLabel: String { isBusHoliday(entry.date) ? "주말" : "평일" }

    var body: some View {
        Group {
            if let routes = entry.routes, !routes.isEmpty {
                if isSmall {
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetBigHeader(title: "버스", subs: ["학교 출발 · " + dayLabel],
                                        palette: palette, size: 20)
                        if style == .next { nextSmall(routes) } else { routeRows(routes) }
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        WidgetBigHeader(title: "버스", subs: ["학교 출발", dayLabel], palette: palette)
                            .frame(width: 62, alignment: .leading)
                        Group {
                            if style == .next { nextRows(routes) } else { routeRows(routes) }
                        }
                        .padding(.top, 3)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetBigHeader(title: "버스", subs: ["학교 출발"], palette: palette, size: 20)
                    Text("앱을 한 번 열면\n시간표를 불러옵니다.")
                        .font(.system(size: 13))
                        .foregroundColor(palette.body)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground(palette.background)
        .widgetURL(URL(string: "knuemate://bus?homeWidget"))
    }

    // ── 노선 목록 ──

    private func routeRows(_ routes: [BusRoute]) -> some View {
        let soonest = soonestRoutes(routes.map { r in
            nextDepartures(r.times(on: entry.date), now: entry.date, n: 1).first.flatMap(busMinutes)
        })
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(routes.indices, id: \.self) { i in
                if i > 0 { Spacer(minLength: 2) }
                routeRow(routes[i], index: i, soonest: soonest.contains(i))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func routeRow(_ route: BusRoute, index: Int, soonest: Bool) -> some View {
        let next = nextDepartures(route.times(on: entry.date), now: entry.date, n: isSmall ? 1 : 2)
        HStack(alignment: .center, spacing: 6) {
            WidgetBar(color: busRouteColor(index, isDark: palette.isDark)).frame(height: 14)
            // small은 폭이 좁아 노선 이름이 시각을 밀어내지 않게 — 이름이 줄고 시각은 그대로.
            Text(route.label)
                .font(.system(size: isSmall ? 12 : 13, weight: .bold))
                .foregroundColor(palette.title)
                .minimumScaleFactor(0.75)
                .frame(width: isSmall ? nil : 66, alignment: .leading)
            if isSmall { Spacer(minLength: 4) }
            if next.isEmpty {
                Text(isSmall ? "운행 끝" : "오늘 운행 끝")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .fixedSize()
            } else {
                // 가장 먼저 오는 차는 주황으로 눈에 띄게.
                Text(next[0])
                    .font(.system(size: isSmall ? 12 : 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(soonest ? palette.highlight : palette.body)
                    .fixedSize()
                if !isSmall {
                    if next.count > 1 {
                        Text(next[1])
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundColor(palette.muted)
                            .fixedSize()
                    }
                    Spacer(minLength: 2)
                    eta(next[0], strong: soonest)
                }
            }
        }
        .lineLimit(1)
    }

    // ── 다음 버스 ──

    @ViewBuilder
    private func nextSmall(_ routes: [BusRoute]) -> some View {
        let up = upcomingDepartures(routes.map { $0.times(on: entry.date) }, now: entry.date, n: 3)
        if let first = up.first {
            HStack(alignment: .top, spacing: 7) {
                WidgetBar(color: busRouteColor(first.route, isDark: palette.isDark))
                VStack(alignment: .leading, spacing: 2) {
                    Text(routes[first.route].label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(palette.title)
                        .minimumScaleFactor(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(first.time)
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundColor(palette.highlight)
                        eta(first.time, strong: true)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(up.dropFirst().enumerated()), id: \.offset) { _, d in
                    Text("다음 \(routes[d.route].label) \(d.time)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        } else {
            Text("오늘 운행 끝")
                .font(.system(size: 13))
                .foregroundColor(palette.muted)
        }
    }

    @ViewBuilder
    private func nextRows(_ routes: [BusRoute]) -> some View {
        let up = upcomingDepartures(routes.map { $0.times(on: entry.date) }, now: entry.date, n: 5)
        if up.isEmpty {
            Text("오늘 운행 끝")
                .font(.system(size: 13))
                .foregroundColor(palette.muted)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(up.enumerated()), id: \.offset) { i, d in
                    if i > 0 { Spacer(minLength: 2) }
                    HStack(alignment: .center, spacing: 6) {
                        WidgetBar(color: busRouteColor(d.route, isDark: palette.isDark)).frame(height: 14)
                        Text(routes[d.route].label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(palette.title)
                            .minimumScaleFactor(0.75)
                            .frame(width: 72, alignment: .leading)
                        Text(d.time)
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(i == 0 ? palette.highlight : palette.body)
                            .fixedSize()
                        Spacer(minLength: 2)
                        eta(d.time, strong: i == 0)
                    }
                    .lineLimit(1)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// "N분 뒤" — 다음 엔트리를 기다리지 않고 분 단위로 저절로 줄어든다.
    @ViewBuilder
    private func eta(_ hhmm: String, strong: Bool) -> some View {
        if let d = departureDate(hhmm) {
            Text("\(Text(d, style: .relative)) 뒤")
                .font(.system(size: 11, weight: strong ? .bold : .regular))
                .foregroundColor(strong ? palette.highlight : palette.muted)
                .fixedSize()
        }
    }

    private func departureDate(_ hhmm: String) -> Date? {
        guard let m = busMinutes(hhmm) else { return nil }
        return Calendar.current.date(byAdding: .minute, value: m, to: Calendar.current.startOfDay(for: entry.date))
    }
}

struct BusWidget: Widget {
    // ⚠️ Flutter의 kIosBusWidgetKind(lib/home_widgets.dart)와 같아야 한다.
    let kind: String = "BusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BusProvider()) { entry in
            BusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("학교 출발 버스 · 노선별")
        .description("교원대에서 나가는 513·514·518·913 노선마다 다음 차 시각.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .ownContentMargins()
    }
}

struct BusNextWidget: Widget {
    // ⚠️ Flutter의 kIosBusNextWidgetKind(lib/home_widgets.dart)와 같아야 한다.
    let kind: String = "BusNextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BusProvider()) { entry in
            BusWidgetEntryView(entry: entry, style: .next)
        }
        .configurationDisplayName("학교 출발 버스 · 곧 떠나는 차")
        .description("교원대에서 가장 먼저 떠나는 버스와 그다음 차들.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .ownContentMargins()
    }
}
