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

/// 앞으로 몇 분 동안 매 분 엔트리를 넣는지("N분 뒤"가 줄어드는 구간).
let kBusMinuteEntries = 120

/// 남은 분 → "N분 뒤" / "H시간 M분 뒤". Kotlin BusWidgetProvider.etaText와 같다
/// (0 이하는 "곧" — 떠나는 분엔 다음 엔트리로 넘어가므로 거의 안 보인다).
///
/// | 분 | 결과 |
/// |---|---|
/// | 7 | 7분 뒤 |
/// | 75 | 1시간 15분 뒤 |
func busEtaLabel(_ minutes: Int) -> String {
    if minutes <= 0 { return "곧" }
    return minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분 뒤" : "\(minutes)분 뒤"
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
        // "N분 뒤"는 엔트리마다 고정 글자로 그린다(아래 eta). 앞으로
        // [kBusMinuteEntries]분은 매 분 엔트리를 넣어 저절로 줄어들게 한다.
        let thisMinute = cal.dateInterval(of: .minute, for: now)?.start ?? now
        for k in 1...kBusMinuteEntries {
            if let d = cal.date(byAdding: .minute, value: k, to: thisMinute), d < midnight {
                dates.insert(d)
            }
        }
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
        // 한 시간 뒤 다시 만든다(하루 24번 — 갱신 예산 안). 시스템이 늦게 불러도
        // 출발 시각 엔트리가 자정까지 있어 다음 차는 맞게 넘어간다. 자정이 먼저면
        // 그날 요일로 다시 만든다.
        let reload = min(cal.date(byAdding: .hour, value: 1, to: now) ?? midnight, midnight)
        completion(Timeline(entries: entries, policy: .after(reload)))
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
    /// 가장 먼저 떠나는 차를 크게, 그다음 차들을 시각 순으로. small·잠금화면만
    /// (medium은 노선별과 겹쳐 뺐다 — 2026-11-25 사용자 결정).
    case next
}

struct BusWidgetEntryView: View {
    var entry: BusEntry
    var style: BusWidgetStyle = .routes
    var env: WidgetEnv = WidgetEnv()
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.widgetFamily) private var family

    private var palette: WidgetPalette { WidgetPalette(entry.theme, system: systemColorScheme, env: env) }
    private var isSmall: Bool { family == .systemSmall }
    private var dayLabel: String { isBusHoliday(entry.date) ? "주말" : "평일" }

    var body: some View {
        if #available(iOSApplicationExtension 16.0, *), family.isAccessory {
            BusLockView(entry: entry, family: family)
                .widgetBackground(Color.clear)
                .widgetURL(URL(string: "knuemate://bus?homeWidget"))
        } else {
            homeBody
        }
    }

    @ViewBuilder
    private var homeBody: some View {
        Group {
            if let routes = entry.routes, !routes.isEmpty {
                if isSmall {
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetBigHeader(title: "버스", subs: ["학교 출발 · " + dayLabel],
                                        palette: palette, size: WidgetType.headerSmall)
                        if style == .next { nextSmall(routes) } else { routeRows(routes) }
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        WidgetBigHeader(title: "버스", subs: ["학교 출발", dayLabel], palette: palette)
                            .frame(width: 62, alignment: .leading)
                        Group {
                            routeRows(routes)  // 곧 떠나는 차는 small·잠금화면만 있다
                        }
                        .padding(.top, 3)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetBigHeader(title: "버스", subs: ["학교 출발"], palette: palette,
                                    size: WidgetType.headerSmall)
                    WidgetMessage(text: "앱을 한 번 열면\n시간표를 불러옵니다.", palette: palette)
                }
            }
        }
        .padding(WidgetSpace.padding)
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
            WidgetBar(color: busRouteColor(index, isDark: palette.isDark), env: env).frame(height: 14)
            // small은 폭이 좁아 노선 이름이 시각을 밀어내지 않게 — 이름이 줄고 시각은 그대로.
            Text(route.label)
                .font(.system(size: isSmall ? WidgetType.sub : WidgetType.body, weight: .bold))
                .foregroundColor(palette.title)
                .minimumScaleFactor(0.75)
                .frame(width: isSmall ? nil : 66, alignment: .leading)
            if isSmall { Spacer(minLength: 4) }
            if next.isEmpty {
                Text(isSmall ? "운행 끝" : "오늘 운행 끝")
                    .font(.system(size: WidgetType.sub))
                    .foregroundColor(palette.muted)
                    .fixedSize()
            } else {
                // 가장 먼저 오는 차는 주황으로 눈에 띄게.
                Text(next[0])
                    .font(.system(size: isSmall ? WidgetType.sub : WidgetType.body, weight: .semibold).monospacedDigit())
                    .foregroundColor(soonest ? palette.highlight : palette.body)
                    .widgetAccentableCompat(soonest)
                    .fixedSize()
                if !isSmall {
                    if next.count > 1 {
                        Text(next[1])
                            .font(.system(size: WidgetType.body).monospacedDigit())
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
                WidgetBar(color: busRouteColor(first.route, isDark: palette.isDark), env: env)
                VStack(alignment: .leading, spacing: 2) {
                    Text(routes[first.route].label)
                        .font(.system(size: WidgetType.emphasis, weight: .bold))
                        .foregroundColor(palette.title)
                        .minimumScaleFactor(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(first.time)
                            .font(.system(size: WidgetType.emphasisSub, weight: .semibold).monospacedDigit())
                            .foregroundColor(palette.highlight)
                            .widgetAccentableCompat()
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
                        .font(.system(size: WidgetType.caption).monospacedDigit())
                        .foregroundColor(palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        } else {
            Text("오늘 운행 끝")
                .font(.system(size: WidgetType.body))
                .foregroundColor(palette.muted)
        }
    }

    /// "N분 뒤". 엔트리 시각 기준 고정 글자다 — 매 분 엔트리(getTimeline)로 줄어든다.
    /// 예전엔 `Text(date, style: .relative)`를 문자열에 끼워 넣었는데, 이걸 쓰는
    /// 위젯(노선별 medium·곧 떠나는 차 둘 다)만 iPad에서 통째로 흰 화면이었다.
    @ViewBuilder
    private func eta(_ hhmm: String, strong: Bool) -> some View {
        if let m = busMinutesUntil(hhmm, now: entry.date) {
            Text(busEtaLabel(m))
                .font(.system(size: WidgetType.caption, weight: strong ? .bold : .regular).monospacedDigit())
                .foregroundColor(strong ? palette.highlight : palette.muted)
                .fixedSize()
        }
    }
}

/// [now]부터 오늘 "HH:mm" 출발까지 남은 분(올림). 엔트리가 분 경계라 정수로 떨어진다.
func busMinutesUntil(_ hhmm: String, now: Date, calendar: Calendar = .current) -> Int? {
    guard let m = busMinutes(hhmm),
          let d = calendar.date(byAdding: .minute, value: m, to: calendar.startOfDay(for: now)) else { return nil }
    return Int((d.timeIntervalSince(now) / 60).rounded(.up))
}

/// 노선 이름의 번호만("913 평동행" → "913") — 잠금화면 동그라미용.
func busRouteNumber(_ label: String) -> String {
    String(label.split(separator: " ").first ?? Substring(label))
}

/// 잠금화면 버스(곧 떠나는 차). 시스템이 한 색으로 칠하므로 글자만 쓴다.
///
/// | 크기 | 모양 |
/// |---|---|
/// | inline | 🚌 513 14:27 · 7분 뒤 |
/// | circular | 513 / 7 / 분 (1시간 넘으면 14:27) |
/// | rectangular | 버스 · 평일 / 다음 차 두 대(노선 시각 N분 뒤) |
@available(iOSApplicationExtension 16.0, *)
struct BusLockView: View {
    let entry: BusEntry
    let family: WidgetFamily

    private var upcoming: [(route: Int, time: String)] {
        guard let routes = entry.routes else { return [] }
        return upcomingDepartures(routes.map { $0.times(on: entry.date) }, now: entry.date, n: 2)
    }

    private func label(_ i: Int) -> String { entry.routes?[i].label ?? "" }

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        default: rectangular
        }
    }

    private var inline: some View {
        if let first = upcoming.first, let m = busMinutesUntil(first.time, now: entry.date) {
            return Text("\(Image(systemName: "bus.fill")) \(label(first.route)) \(first.time) · \(busEtaLabel(m))")
        }
        return Text("\(Image(systemName: "bus.fill")) \(entry.routes == nil ? "앱을 열어 주세요" : "오늘 운행 끝")")
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let first = upcoming.first, let m = busMinutesUntil(first.time, now: entry.date) {
                VStack(spacing: 0) {
                    Text(busRouteNumber(label(first.route)))
                        .font(.system(size: WidgetType.caption, weight: .semibold))
                        .widgetAccentable()
                    Text(m < 60 ? "\(m)" : first.time)
                        .font(.system(size: m < 60 ? WidgetType.headerSmall : WidgetType.body, weight: .bold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                    if m < 60 {
                        Text("분").font(.system(size: WidgetType.caption))
                    }
                }
                .lineLimit(1)
                .padding(4)
            } else {
                Image(systemName: "bus.fill").font(.system(size: WidgetType.headerSmall))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(Image(systemName: "bus.fill")) 학교 출발 · \(isBusHoliday(entry.date) ? "주말" : "평일")")
                .font(.system(size: WidgetType.body, weight: .bold))
                .widgetAccentable()
            if entry.routes == nil {
                Text("앱을 한 번 열면 시간표를 불러옵니다.").font(.system(size: WidgetType.body))
            } else if upcoming.isEmpty {
                Text("오늘 운행 끝").font(.system(size: WidgetType.body))
            } else {
                ForEach(Array(upcoming.enumerated()), id: \.offset) { _, d in
                    HStack(spacing: 4) {
                        Text(label(d.route)).font(.system(size: WidgetType.body, weight: .semibold))
                        Text(d.time).font(.system(size: WidgetType.body).monospacedDigit())
                        Spacer(minLength: 2)
                        if let m = busMinutesUntil(d.time, now: entry.date) {
                            Text(busEtaLabel(m)).font(.system(size: WidgetType.caption).monospacedDigit())
                        }
                    }
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BusWidget: Widget {
    // ⚠️ Flutter의 kIosBusWidgetKind(lib/home_widgets.dart)와 같아야 한다.
    let kind: String = "BusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BusProvider()) { entry in
            WidgetEnvReader { env in BusWidgetEntryView(entry: entry, env: env) }
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
            WidgetEnvReader { env in BusWidgetEntryView(entry: entry, style: .next, env: env) }
        }
        .configurationDisplayName("학교 출발 버스 · 곧 떠나는 차")
        .description("교원대에서 가장 먼저 떠나는 버스와 그다음 차들. 잠금화면에도 둘 수 있습니다.")
        .supportedFamilies(widgetFamilies(home: [.systemSmall],
                                          lock: [.inline, .circular, .rectangular]))
        .ownContentMargins()
    }
}
