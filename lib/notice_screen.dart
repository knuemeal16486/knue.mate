import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'keyword_alert_service.dart';
import 'notice_model.dart';
import 'notice_service.dart';

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
      });
    }
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

  /// 선택된 카테고리(또는 전체) + 검색어로 걸러낸 공지 목록.
  /// 검색은 선택된 게시판 범위 안에서만 적용된다(MoA의 검색 범위 동작과 동일).
  List<Notice> get _filteredNotices {
    var list = _selectedCategory == null
        ? _notices
        : _notices.where((n) => n.category == _selectedCategory).toList();
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((n) => n.title.toLowerCase().contains(q)).toList();
  }

  /// 선택 게시판이 크롤링 결과 0건인지(=크롤링 실패 가능성) 판정.
  /// fetchAllNotices의 개별 게시판 catchError는 빈 리스트를 반환하므로,
  /// "해당 카테고리가 전체 게시판 목록엔 존재하지만 결과가 0건"이면 실패로 간주한다.
  bool get _hasFailedBoard {
    if (_loading) return false;
    if (_selectedCategory != null) {
      return _notices.where((n) => n.category == _selectedCategory).isEmpty;
    }
    // 전체 보기: 카테고리 중 하나라도 결과가 없으면 일부 실패로 간주.
    final present = _notices.map((n) => n.category).toSet();
    return _allCategories.any((c) => !present.contains(c));
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
            backgroundColor: color,
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
              if (_hasFailedBoard) _buildFailureBanner(isDark),
              Expanded(child: _buildNoticeList(color, isDark)),
              _buildFooter(isDark),
            ],
          ),
        );
      },
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
        onChanged: (v) => setState(() => _searchQuery = v),
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
                    setState(() => _searchQuery = '');
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
        final entries = <MapEntry<String, String>>[]; // category -> group
        for (final groupEntry in _scraper.boardGroups.entries) {
          for (final catEntry in groupEntry.value.entries) {
            entries.add(MapEntry(catEntry.key, groupEntry.key));
          }
        }
        entries.sort((a, b) {
          final aFav = favBoards.contains(a.key);
          final bFav = favBoards.contains(b.key);
          if (aFav != bFav) return aFav ? -1 : 1;
          return 0;
        });

        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _buildChip(
                label: "전체",
                selected: _selectedCategory == null,
                color: color,
                onTap: () => setState(() => _selectedCategory = null),
              ),
              ...entries.map((entry) {
                final category = entry.key;
                final isFav = favBoards.contains(category);
                return _buildChip(
                  label: category,
                  selected: _selectedCategory == category,
                  color: color,
                  onTap: () => setState(() => _selectedCategory = category),
                  isFavorite: isFav,
                  onStarTap: () => _toggleFavoriteBoard(category),
                );
              }),
            ],
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
    final list = _filteredNotices;
    if (list.isEmpty) {
      final searching = _searchQuery.trim().isNotEmpty;
      return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                searching ? "검색 결과가 없습니다" : "표시할 공지가 없습니다",
              ),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    notice.category,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
                const Spacer(),
                Text(
                  notice.date,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notice.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                height: 1.3,
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
