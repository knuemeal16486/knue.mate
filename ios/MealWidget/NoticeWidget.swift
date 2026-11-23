import SwiftUI
import WidgetKit

// KNUE Mate 공지 위젯 (iOS) — 즐겨찾기 게시판마다 최신 글, 남는 자리는 다음 글.
//
// 앱이 위젯 저장소에 넣는 값 (lib/home_widgets.dart의 pushNoticeWidget):
//
//   notice_rows_json    String  [{"b":게시판,"t":제목,"d":"yyyy-MM-dd","l":링크}]
//   notice_boards_json  String  ["학사공지", ...] 대상 게시판
//   notice_feed_base    String  수집 파일 주소(GitHub Pages)
//   notice_feed_direct  Bool    비상 직접 모드 — 켜져 있으면 위젯은 받지 않는다
//
// iOS 백그라운드는 몇 시간씩 안 돌 수 있어서, 위젯이 수집 파일을 직접 받는다
// (index.json을 보고 지문(hash)이 바뀐 게시판 파일만). 학교 서버·Firestore에는
// 절대 요청하지 않는다 — 받는 곳은 notice_feed_base(https)뿐이다.
// 고르는 규칙은 Dart noticeWidgetRows와 같다: 게시판마다 날짜가 가장 늦은 글
// 1개를 먼저(게시판끼리는 그 날짜가 늦은 것부터, 같으면 대상 게시판 순서),
// 자리가 남으면 나머지 글을 최신순으로 채운다.

struct NoticeRow: Codable, Equatable {
    let b: String
    let t: String
    let d: String
    let l: String
}

/// 위젯이 받은 결과. App Group 폴더의 notice_widget_cache.json.
private struct NoticeWidgetCache: Codable {
    /// 수집 파일(b/<id>.json)마다 마지막으로 받은 지문·최신 글들.
    var files: [String: CachedBoardFile] = [:]
}

private struct CachedBoardFile: Codable {
    let category: String
    let hash: String
    let fetchedAt: String?
    /// 예전 캐시(최신 글 1개). 새 캐시는 top을 쓴다.
    let latest: NoticeRow?
    /// 날짜가 늦은 글부터 최대 kNoticeWidgetMaxRows개.
    let top: [NoticeRow]?

    var rows: [NoticeRow] { top ?? latest.map { [$0] } ?? [] }
}

private struct FeedIndex: Decodable {
    let boards: [FeedIndexBoard]
}

private struct FeedIndexBoard: Decodable {
    let category: String
    let file: String
    let fetchedAt: String?
    let hash: String?
}

private struct FeedBoardFile: Decodable {
    let items: [FeedItem]
}

private struct FeedItem: Decodable {
    let t: String
    let l: String
    let d: String
}

/// Dart widgetLinkAllowed와 같은 규칙.
func noticeLinkAllowed(_ link: String) -> Bool {
    guard let url = URL(string: link), url.scheme == "https", let host = url.host?.lowercased() else {
        return false
    }
    return host == "knue.ac.kr" || host.hasSuffix(".knue.ac.kr")
}

let kNoticeWidgetMaxRows = 8

/// Dart noticeWidgetRows와 같은 규칙. 게시판마다 최신 1개를 먼저(날짜 늦은
/// 게시판부터, 같으면 boards 순서), 남는 자리는 나머지 글을 최신순으로.
/// 같은 글(게시판·링크·제목)은 한 번만.
func pickNoticeRows(_ all: [NoticeRow], boards: [String], max: Int) -> [NoticeRow] {
    var seen = Set<String>()
    var posts: [NoticeRow] = []
    for r in all where boards.contains(r.b) {
        if seen.insert(r.b + "|" + r.l + "|" + r.t).inserted { posts.append(r) }
    }
    let sorted = posts.enumerated().sorted { x, y in
        let a = x.element, b = y.element
        if a.d != b.d { return a.d > b.d }
        let ia = boards.firstIndex(of: a.b) ?? 0, ib = boards.firstIndex(of: b.b) ?? 0
        return ia != ib ? ia < ib : x.offset < y.offset
    }.map { $0.element }
    var used = Set<String>()
    var firsts: [NoticeRow] = [], rest: [NoticeRow] = []
    for r in sorted {
        if used.insert(r.b).inserted { firsts.append(r) } else { rest.append(r) }
    }
    return Array((firsts + rest).prefix(max))
}

struct NoticeEntry: TimelineEntry {
    let date: Date
    /// nil = 앱이 아직 아무것도 넣지 않았다.
    let rows: [NoticeRow]?
    /// 대상 게시판 중 가장 오래된 마지막 수집 시각.
    let collectedAt: Date?
    let theme: WidgetThemeSettings
}

private func parseFeedDate(_ s: String?) -> Date? {
    guard let s = s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}

struct NoticeProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoticeEntry {
        NoticeEntry(date: Date(), rows: [], collectedAt: nil, theme: WidgetThemeSettings())
    }

    func getSnapshot(in context: Context, completion: @escaping (NoticeEntry) -> Void) {
        completion(NoticeLoader.entry(fetched: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoticeEntry>) -> Void) {
        NoticeLoader.fetch { cache in
            let entry = NoticeLoader.entry(fetched: cache)
            // iOS가 예산에 따라 더 늦출 수 있다.
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

private enum NoticeLoader {
    static var cacheURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("notice_widget_cache.json")
    }

    static func loadCache() -> NoticeWidgetCache? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NoticeWidgetCache.self, from: data)
    }

    static func saveCache(_ cache: NoticeWidgetCache) {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func targetBoards(_ defaults: UserDefaults?) -> [String] {
        guard let raw = defaults?.string(forKey: "notice_boards_json"),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    static func appRows(_ defaults: UserDefaults?) -> [NoticeRow]? {
        guard let raw = defaults?.string(forKey: "notice_rows_json"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([NoticeRow].self, from: data)
    }

    /// 수집 파일을 받아 캐시를 갱신한다. 받지 않거나 실패하면 지난 캐시를 준다.
    /// 10초 안에 끝나지 않으면 그때까지의 캐시로 끝낸다.
    static func fetch(completion: @escaping (NoticeWidgetCache?) -> Void) {
        let defaults = sharedDefaults()
        let old = loadCache()
        let boards = Set(targetBoards(defaults))
        // 비상 직접 모드면 앱이 넣은 값만 그린다(위젯이 학교로 가지 않게).
        let direct = defaults?.bool(forKey: "notice_feed_direct") ?? false
        let base = defaults?.string(forKey: "notice_feed_base") ?? ""
        guard !direct, base.hasPrefix("https://"), !boards.isEmpty,
              let indexURL = URL(string: base + "/index.json") else {
            completion(old)
            return
        }

        var done = false
        let lock = NSLock()
        func finish(_ c: NoticeWidgetCache?) {
            lock.lock(); defer { lock.unlock() }
            if done { return }
            done = true
            completion(c)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { finish(old) }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        session.dataTask(with: indexURL) { data, _, error in
            guard error == nil, let data = data,
                  let index = try? JSONDecoder().decode(FeedIndex.self, from: data) else {
                finish(old)
                return
            }
            var cache = old ?? NoticeWidgetCache()
            let wanted = index.boards.filter { boards.contains($0.category) }
            // 대상이 아닌 게시판 캐시는 버린다(즐겨찾기를 바꿨을 때).
            cache.files = cache.files.filter { k, _ in wanted.contains { $0.file == k } }

            let group = DispatchGroup()
            let resultLock = NSLock()
            for b in wanted {
                let hash = b.hash ?? ""
                if let c = cache.files[b.file], c.hash == hash, !hash.isEmpty {
                    // 내용은 그대로 — 수집 시각만 새로.
                    cache.files[b.file] = CachedBoardFile(
                        category: b.category, hash: hash, fetchedAt: b.fetchedAt,
                        latest: c.latest, top: c.top)
                    continue
                }
                guard let url = URL(string: base + "/" + b.file) else { continue }
                group.enter()
                session.dataTask(with: url) { data, _, error in
                    defer { group.leave() }
                    guard error == nil, let data = data,
                          let file = try? JSONDecoder().decode(FeedBoardFile.self, from: data) else { return }
                    // 날짜 내림차순이지만 믿지 않고 다시 정렬한다(같으면 앞의 것).
                    let top = file.items.enumerated()
                        .sorted { $0.element.d != $1.element.d ? $0.element.d > $1.element.d : $0.offset < $1.offset }
                        .prefix(kNoticeWidgetMaxRows)
                        .map { NoticeRow(b: b.category, t: $0.element.t, d: $0.element.d, l: $0.element.l) }
                    resultLock.lock()
                    cache.files[b.file] = CachedBoardFile(
                        category: b.category, hash: hash, fetchedAt: b.fetchedAt,
                        latest: nil, top: top)
                    resultLock.unlock()
                }.resume()
            }
            group.notify(queue: .global()) {
                saveCache(cache)
                finish(cache)
            }
        }.resume()
    }

    /// 위젯이 받은 것과 앱이 넣은 것을 합쳐 고른다(같은 글은 한 번만).
    static func entry(fetched: NoticeWidgetCache?) -> NoticeEntry {
        let defaults = sharedDefaults()
        let theme = WidgetThemeSettings.read(defaults)
        let boards = targetBoards(defaults)
        let fromApp = appRows(defaults)
        let cache = fetched ?? loadCache()

        var all: [NoticeRow] = fromApp ?? []
        var oldest: Date?
        for file in (cache?.files ?? [:]).values {
            guard boards.contains(file.category) else { continue }
            all += file.rows
            if let at = parseFeedDate(file.fetchedAt), oldest == nil || at < oldest! { oldest = at }
        }
        if fromApp == nil && cache == nil {
            return NoticeEntry(date: Date(), rows: nil, collectedAt: nil, theme: theme)
        }
        return NoticeEntry(
            date: Date(),
            rows: pickNoticeRows(all, boards: boards, max: kNoticeWidgetMaxRows),
            collectedAt: oldest,
            theme: theme
        )
    }
}

struct NoticeWidgetEntryView: View {
    var entry: NoticeEntry
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.widgetFamily) private var family

    private var palette: WidgetPalette { WidgetPalette(entry.theme, system: systemColorScheme) }
    private var maxRows: Int { family == .systemLarge ? 8 : 4 }
    /// 줄 간격은 고정 — 글이 적어도 위에 모여 있게(Spacer로 벌리지 않는다).
    private var rowSpacing: CGFloat { family == .systemLarge ? 16 : 9 }

    /// 앱 공지 화면과 같은 기준: 마지막 수집이 3시간 넘으면 늦어짐.
    private var isStale: Bool {
        guard let at = entry.collectedAt else { return false }
        return entry.date.timeIntervalSince(at) > 3 * 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Link(destination: URL(string: "knuemate://notice?homeWidget")!) {
                HStack(spacing: 4) {
                    Text("공지")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(palette.accent)
                    Spacer(minLength: 0)
                    if isStale {
                        Text("갱신이 늦어지고 있어요")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    } else if let at = entry.collectedAt {
                        Text(Self.timeFormatter.string(from: at) + " 기준")
                            .font(.system(size: 11))
                            .foregroundColor(palette.muted)
                    }
                }
                .lineLimit(1)
            }
            .padding(.bottom, 6)

            if let rows = entry.rows {
                if rows.isEmpty {
                    Text("즐겨찾기 게시판의 글이 아직 없어요.")
                        .font(.system(size: 13))
                        .foregroundColor(palette.body)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(Array(rows.prefix(maxRows).enumerated()), id: \.offset) { _, row in
                            rowView(row)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("앱을 한 번 열면\n공지를 불러옵니다.")
                    .font(.system(size: 13))
                    .foregroundColor(palette.body)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground(palette.background)
        .widgetURL(URL(string: "knuemate://notice?homeWidget"))
    }

    @ViewBuilder
    private func rowView(_ row: NoticeRow) -> some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(Text("[\(row.b)] ").foregroundColor(palette.accent).fontWeight(.semibold))\(Text(row.t).foregroundColor(palette.title))")
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(Self.shortDate(row.d))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(palette.muted)
        }
        if let url = Self.openURL(row.l) {
            Link(destination: url) { content }
        } else {
            content
        }
    }

    /// 위젯 Link는 앱으로만 URL을 넘긴다 — 앱(main.dart)이 u를 꺼내 브라우저로 연다.
    static func openURL(_ link: String) -> URL? {
        guard noticeLinkAllowed(link) else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = link.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "knuemate://notice?homeWidget&u=" + encoded)
    }

    /// "2026-11-20" → "11/20"
    static func shortDate(_ d: String) -> String {
        let p = d.split(separator: "-")
        guard p.count == 3 else { return d }
        return "\(p[1])/\(p[2])"
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()
}

struct NoticeWidget: Widget {
    // ⚠️ Flutter의 kIosNoticeWidgetKind(lib/home_widgets.dart)와 같아야 한다.
    let kind: String = "NoticeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NoticeProvider()) { entry in
            NoticeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("공지")
        .description("즐겨찾기 게시판마다 가장 최신 글을 봅니다.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
