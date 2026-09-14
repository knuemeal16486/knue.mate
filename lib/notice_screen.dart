import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'keyword_alert_service.dart';
import 'notice_model.dart';
import 'notice_service.dart';
import 'ui_utils.dart';

/// 청람공지 화면. KnueScraper로 크롤링한 전체 게시판 공지를 게시판 그룹별로
/// 모아 보여주고, 즐겨찾기 게시판/키워드 알림을 관리한다.
class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key});
  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  final _scraper = KnueScraper();
  List<Notice> _notices = [];
  bool _loading = true;
  bool _loadInFlight = false; // 중복 새로고침(연타)이 서로 다른 결과로 캐시를 덮어쓰지 않도록
  String? _selectedCategory; // null = 전체
  DateTime? _lastUpdated;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // ── 파생 상태 캐시 ────────────────────────────────────────────────────
  //
  // 아래 값들은 모두 (_notices, _selectedCategory, _searchQuery)에서만 나온다.
  // 예전에는 getter로 두어 **매 프레임마다** 공지 500건을 toLowerCase()로
  // 훑고, 게시판 50개를 정렬해 칩을 전부 다시 만들었다. 스크롤·타이핑 때
  // 눈에 띄게 버벅인 원인이라 입력이 바뀔 때만 계산하도록 바꿨다.
  List<Notice> _filtered = const [];
  bool _failedBoard = false;
  /// 제목 소문자 사본. 검색할 때마다 새로 만들지 않도록 미리 계산해 둔다.
  final Map<String, String> _lowerTitleCache = {};
  List<MapEntry<String, String>> _boardEntries = const [];
  List<String> _boardEntriesFavKey = const [];

  @override
  void initState() {
    super.initState();
    _load();
    // fetchAllNotices()는 캐시를 먼저 반환하고 백그라운드로 갱신한다(await 없이).
    // 그 갱신이 끝났을 때 화면이 최신 데이터를 반영하도록 구독.
    NoticeCache.revision.addListener(_onCacheUpdated);
  }

  @override
  void dispose() {
    NoticeCache.revision.removeListener(_onCacheUpdated);
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _onCacheUpdated() async {
    if (_loadInFlight) return; // 직접 요청한 갱신 결과는 _load()가 이미 반영함
    final list = await NoticeCache.load();
    final ts = await NoticeCache.lastUpdated();
    if (mounted && list != null) {
      setState(() {
        _notices = list;
        _lastUpdated = ts;
        _recomputeDerived();
      });
    }
  }

  /// 타이핑할 때마다 500건을 훑으면 입력이 밀린다. 잠깐 멈췄을 때만 거른다.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value;
        _recomputeDerived();
      });
    });
  }

  Future<void> _load({bool force = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    setState(() => _loading = true);
    try {
      final list = await _scraper.fetchAllNotices(forceRefresh: force);
      final ts = await NoticeCache.lastUpdated();
      if (mounted) {
        setState(() {
          _notices = list;
          _recomputeDerived();
          _lastUpdated = ts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _loadInFlight = false;
    }
  }

  /// 실제로 크롤링되는 게시판 카테고리 이름 집합 (실패 게시판 판정에 사용).
  /// 'LINK:' 접두사가 붙은 게시판(예: 외부 카페 링크)은 의도적으로 크롤링 대상에서
  /// 제외되어 항상 0건을 반환하므로, 실패 판정 대상에서도 제외한다.
  Set<String> get _allCategories {
    final names = <String>{};
    for (final group in _scraper.boardGroups.values) {
      for (final entry in group.entries) {
        if (!entry.value.startsWith('LINK:')) {
          names.add(entry.key);
        }
      }
    }
    return names;
  }

  /// 크롤링하지 않고 외부 사이트로 넘기는 게시판의 주소.
  /// (초등교육과는 학과 공지를 다음 카페에서만 올린다.)
  String? _linkOnlyUrl(String? category) {
    if (category == null) return null;
    for (final group in _scraper.boardGroups.values) {
      final url = group[category];
      if (url != null && url.startsWith('LINK:')) return url.substring(5);
    }
    return null;
  }

  /// 선택된 카테고리(또는 전체) + 검색어로 걸러낸 공지 목록.
  /// 검색은 선택된 게시판 범위 안에서만 적용된다(MoA의 검색 범위 동작과 동일).
  /// 목록·배너를 다시 계산한다. 입력(_notices/_selectedCategory/_searchQuery)이
  /// 바뀌는 지점에서만 부르고, build에서는 결과만 읽는다.
  void _recomputeDerived() {
    final base = _selectedCategory == null
        ? _notices
        : _notices.where((n) => n.category == _selectedCategory).toList();

    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = base;
    } else {
      _filtered = base.where((n) {
        final lower =
            _lowerTitleCache[n.title] ??= n.title.toLowerCase();
        return lower.contains(q);
      }).toList();
    }

    // 선택 게시판이 크롤링 결과 0건인지(=크롤링 실패 가능성) 판정.
    // fetchAllNotices의 개별 게시판 catchError는 빈 리스트를 반환하므로,
    // "카테고리가 전체 목록엔 있는데 결과가 0건"이면 실패로 간주한다.
    if (_loading) {
      _failedBoard = false;
    } else if (_selectedCategory != null) {
      // LINK 게시판은 크롤링 대상이 아니라 0건이 정상이다.
      _failedBoard = _linkOnlyUrl(_selectedCategory) == null &&
          !_notices.any((n) => n.category == _selectedCategory);
    } else {
      final present = _notices.map((n) => n.category).toSet();
      _failedBoard = _allCategories.any((c) => !present.contains(c));
    }
  }

  /// 게시판 칩 목록. 즐겨찾기가 바뀔 때만 다시 정렬한다.
  List<MapEntry<String, String>> _boardEntriesFor(List<String> favBoards) {
    if (_boardEntries.isNotEmpty &&
        _boardEntriesFavKey.length == favBoards.length &&
        _boardEntriesFavKey.every(favBoards.contains)) {
      return _boardEntries;
    }
    final entries = <MapEntry<String, String>>[]; // category -> group
    for (final groupEntry in _scraper.boardGroups.entries) {
      for (final catEntry in groupEntry.value.entries) {
        entries.add(MapEntry(catEntry.key, groupEntry.key));
      }
    }
    // 즐겨찾기를 앞으로. 나머지는 원래 그룹 순서를 지키도록 안정 정렬.
    entries.sort((a, b) {
      final aFav = favBoards.contains(a.key);
      final bFav = favBoards.contains(b.key);
      if (aFav != bFav) return aFav ? -1 : 1;
      return 0;
    });
    _boardEntries = entries;
    _boardEntriesFavKey = List.of(favBoards);
    return entries;
  }

  Future<void> _openNotice(Notice notice) async {
    final uri = Uri.tryParse(notice.link);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 실행 실패는 조용히 무시 (외부 브라우저 부재 등)
    }
  }

  void _toggleFavoriteBoard(String category) {
    final current = List<String>.from(PreferencesService.favoriteBoards.value);
    if (current.contains(category)) {
      current.remove(category);
    } else {
      current.add(category);
    }
    PreferencesService.saveFavoriteBoards(current);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            centerTitle: (!kIsWeb && Platform.isIOS) ? false : null,
            title: const Text("청람공지"),
            backgroundColor: Colors.transparent,
            flexibleSpace: AppleAppBarFlexibleSpace(
              themeColor: color,
              isDark: isDark,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                onPressed: () => _showKeywordSheet(context, color),
                icon: const Icon(Icons.notifications_outlined),
                tooltip: "키워드 관리",
              ),
              IconButton(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh),
                tooltip: "새로고침",
              ),
            ],
          ),
          body: Column(
            children: [
              _buildSearchField(color, isDark),
              _buildBoardChips(color),
              if (_failedBoard) _buildFailureBanner(isDark),
              Expanded(child: _buildNoticeList(color, isDark)),
              _buildFooter(isDark),
            ],
          ),
        );
      },
    );
  }

  /// 외부 사이트에만 공지를 올리는 게시판 안내. 이 안내가 없으면
  /// "표시할 공지가 없습니다"만 뜨고 어디로 가야 하는지 알 길이 없다.
  Widget _buildExternalBoardNotice(String url, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.open_in_new, size: 36, color: color.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            "$_selectedCategory 공지는 외부 사이트에만 올라옵니다",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final uri = Uri.tryParse(url);
              if (uri == null) return;
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {
                // 브라우저가 없으면 조용히 무시 (_openNotice와 동일)
              }
            },
            icon: const Icon(Icons.launch, size: 18),
            label: const Text("바로 가기"),
            style: FilledButton.styleFrom(backgroundColor: color),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureBanner(bool isDark) {
    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: isDark ? 0.15 : 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "일부 게시판을 불러오지 못했습니다",
              style: TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// 제목 검색창. 선택된 게시판 범위 안에서만 걸러내며, 이미 받아온 목록을
  /// 로컬에서 필터링하므로 재크롤링 없이 즉시 반영된다.
  Widget _buildSearchField(Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: _selectedCategory == null
              ? "전체 공지에서 제목 검색"
              : "$_selectedCategory에서 제목 검색",
          hintStyle: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: "검색어 지우기",
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _searchQuery = "";
                      _recomputeDerived();
                    });
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildBoardChips(Color color) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: PreferencesService.favoriteBoards,
      builder: (context, favBoards, child) {
        // 즐겨찾기 게시판을 먼저 배치하고, 나머지는 그룹 순서대로.
        // 목록 자체는 즐겨찾기가 바뀔 때만 다시 만든다.
        final entries = _boardEntriesFor(favBoards);

        return SizedBox(
          height: 44,
          // ListView.builder — 게시판이 50개라 전부 미리 만들면 화면에 들어오지도
          // 않는 칩까지 매번 생성된다. 보이는 것만 만들게 바꿨다.
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: entries.length + 1, // +1 = "전체"
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildChip(
                  label: "전체",
                  selected: _selectedCategory == null,
                  color: color,
                  onTap: () => setState(() {
                    _selectedCategory = null;
                    _recomputeDerived();
                  }),
                );
              }
              final category = entries[index - 1].key;
              return _buildChip(
                label: category,
                selected: _selectedCategory == category,
                color: color,
                onTap: () => setState(() {
                  _selectedCategory = category;
                  _recomputeDerived();
                }),
                isFavorite: favBoards.contains(category),
                onStarTap: () => _toggleFavoriteBoard(category),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
    bool? isFavorite,
    VoidCallback? onStarTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : Colors.grey.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onStarTap != null)
                GestureDetector(
                  onTap: onStarTap,
                  child: Icon(
                    isFavorite == true ? Icons.star : Icons.star_border,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : (isFavorite == true ? Colors.amber : Colors.grey),
                  ),
                ),
              if (onStarTap != null) const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : null,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoticeList(Color color, bool isDark) {
    if (_loading && _notices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = _filtered;
    if (list.isEmpty) {
      final searching = _searchQuery.trim().isNotEmpty;
      final linkUrl = searching ? null : _linkOnlyUrl(_selectedCategory);
      return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: linkUrl == null
                  ? Text(searching ? "검색 결과가 없습니다" : "표시할 공지가 없습니다")
                  : _buildExternalBoardNotice(linkUrl, color),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: list.length,
        itemBuilder: (context, index) =>
            _buildNoticeCard(list[index], color, isDark),
      ),
    );
  }

  Widget _buildNoticeCard(Notice notice, Color color, bool isDark) {
    return GestureDetector(
      onTap: () => _openNotice(notice),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 날짜는 고정 폭으로 먼저 자리를 잡고, 배지 묶음이 남는 폭을
                // 가져간다. 예전에는 배지가 Flexible 없이 Spacer와 함께 있어
                // "지구과학교육과" 같은 긴 이름에서 Row가 넘치고 글씨가 잘렸다.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            notice.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (notice.isNew) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "NEW",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  notice.date,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontFeatures: KnueTokens.tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notice.title,
              // 공지 제목은 길다. 2줄에서 자르면 핵심이 잘려나가는 경우가 많아
              // 3줄까지 허용하고 줄간격을 넓혔다.
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    final text = _lastUpdated == null
        ? "갱신 기록 없음"
        : "마지막 갱신: ${_formatTimestamp(_lastUpdated!)}";
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return "방금 전";
    if (diff.inMinutes < 60) return "${diff.inMinutes}분 전";
    if (diff.inHours < 24) return "${diff.inHours}시간 전";
    return "${dt.year}.${dt.month.toString().padLeft(2, '0')}."
        "${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _showKeywordSheet(BuildContext context, Color color) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _KeywordSheet(color: color),
    );
  }
}

/// 키워드 관리 bottom sheet. 현재 키워드를 칩으로 보여주고 추가/삭제 시
/// PreferencesService.saveNoticeKeywords + KeywordAlertService.syncRegistration을 호출한다.
class _KeywordSheet extends StatefulWidget {
  final Color color;
  const _KeywordSheet({required this.color});

  @override
  State<_KeywordSheet> createState() => _KeywordSheetState();
}

class _KeywordSheetState extends State<_KeywordSheet> {
  late List<String> _keywords;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _keywords = List.from(PreferencesService.noticeKeywords.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    await PreferencesService.saveNoticeKeywords(_keywords);
    await KeywordAlertService.syncRegistration();
  }

  void _addKeyword() {
    final text = _controller.text.trim();
    if (text.isEmpty || _keywords.contains(text)) return;
    setState(() {
      _keywords.add(text);
      _controller.clear();
    });
    _persist();
  }

  void _removeKeyword(String keyword) {
    setState(() => _keywords.remove(keyword));
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              "키워드 알림 관리",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              "등록한 키워드가 포함된 새 공지가 올라오면 알려드려요.",
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            if (_keywords.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  "등록된 키워드가 없습니다. 키워드가 없으면 즐겨찾기 게시판의 모든 새 글을 알려드려요.",
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _keywords
                    .map((kw) => Chip(
                          label: Text(kw),
                          onDeleted: () => _removeKeyword(kw),
                          backgroundColor: widget.color.withValues(alpha: 0.12),
                          labelStyle: TextStyle(color: widget.color),
                          deleteIconColor: widget.color,
                        ))
                    .toList(),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: "키워드 입력 (예: 장학금)",
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => _addKeyword(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addKeyword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  child: const Text("추가"),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}
