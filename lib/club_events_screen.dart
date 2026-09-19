import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'club_event_admin_screen.dart';
import 'club_event_model.dart';
import 'club_event_service.dart';
import 'constants.dart';
import 'ui_utils.dart';

/// 학과 행사 및 동아리 공연 전체 목록 화면.
/// 녹출(isFeatured) 항목을 상단에 강조하고, 나머지는 시작일 오름차순으로 보여준다.
class ClubEventsScreen extends StatefulWidget {
  const ClubEventsScreen({super.key});
  @override
  State<ClubEventsScreen> createState() => _ClubEventsScreenState();
}

class _ClubEventsScreenState extends State<ClubEventsScreen> {
  List<ClubEvent> _events = [];
  bool _loading = true;
  bool _error = false;
  bool _loadInFlight = false; // 중복 새로고침(연타)이 서로 다른 결과로 캐시를 덮어쓰지 않도록
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _load();
    // fetchAll()은 캐시를 먼저 반환하고 백그라운드로 갱신한다(await 없이).
    // 그 갱신이 끝났을 때 화면이 최신 데이터를 반영하도록 구독.
    ClubEventCache.revision.addListener(_onCacheUpdated);
  }

  @override
  void dispose() {
    ClubEventCache.revision.removeListener(_onCacheUpdated);
    super.dispose();
  }

  Future<void> _onCacheUpdated() async {
    if (_loadInFlight) return; // 직접 요청한 갱신 결과는 _load()가 이미 반영함
    final list = await ClubEventCache.load();
    final ts = await ClubEventCache.lastUpdated();
    if (mounted && list != null) {
      setState(() {
        _events = list;
        _lastUpdated = ts;
      });
    }
  }

  Future<void> _load({bool force = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      // 앱 시작 직후 진입하면 Firebase 초기화·다른 탭 로딩과 네트워크를
      // 나눠 쓰는 타이밍이라 기본 4초 타임아웃이 빠듯하다. 여기는 사용자가
      // 이 화면만 보고 기다리는 전용 목록이라 넉넉히 준다.
      final list = await ClubEventService.fetchAll(
        forceRefresh: force,
        timeout: const Duration(seconds: 8),
      );
      final ts = await ClubEventCache.lastUpdated();
      if (!mounted) return;
      setState(() {
        _events = list;
        _lastUpdated = ts;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    } finally {
      _loadInFlight = false;
    }
  }

  /// 진행중인 행사가 맨 위, 아래로 갈수록 시작이 먼 순.
  /// 끝난 행사는 ClubEventService.fetchAll이 이미 걸러낸다.
  List<ClubEvent> _sortedEvents(DateTime now) =>
      List<ClubEvent>.of(_events)
        ..sort((a, b) => ClubEvent.compareForList(a, b, now));

  Future<void> _openExternalLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showToast(context, "링크를 열 수 없습니다");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: const Text("공연·행사"),
            backgroundColor: Colors.transparent,
            flexibleSpace: AppleAppBarFlexibleSpace(
              themeColor: color,
              isDark: isDark,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh),
                tooltip: "새로고침",
              ),
              // 등록 화면(ClubEventAdminScreen)이 개발자 코드를 직접 묻는다.
              // 메뉴 자체는 숨기지 않는다 — 막는 것은 코드이지 메뉴가 아니고,
              // 숨겨두면 정작 등록할 사람이 들어갈 길을 못 찾는다.
              PopupMenuButton<String>(
                tooltip: "행사 관리",
                onSelected: (_) async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ClubEventAdminScreen(),
                    ),
                  );
                  if (mounted) _load(force: true);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'admin',
                    child: Row(
                      children: [
                        Icon(Icons.edit_calendar_outlined, size: 18),
                        SizedBox(width: 10),
                        Text("행사 등록·수정"),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(child: _buildList(color, isDark)),
              _buildFooter(isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(Color color, bool isDark) {
    if (_loading && _events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error && _events.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 40,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "불러오기 실패",
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _load(force: true),
                    child: const Text("다시 시도"),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text("예정된 공연·행사가 없습니다")),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final sorted = _sortedEvents(now);
    final ongoing = sorted.where((e) => e.isOngoing(now)).toList();
    final upcoming = sorted.where((e) => !e.isOngoing(now)).toList();

    // 예전에는 위쪽이 4초마다 저절로 넘어가는 가로 캐러셀이었다. 읽는 중에
    // 카드가 바뀌고, 몇 개가 있는지도 알 수 없었다. 전부 세로로 쌓는다.
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24, top: 8),
        children: [
          if (ongoing.isNotEmpty) ...[
            _buildSectionTitle("지금 열리는 중", isDark),
            ...ongoing.map((e) => _buildHighlightCard(e, color, isDark, now)),
          ],
          if (upcoming.isNotEmpty) ...[
            _buildSectionTitle(ongoing.isEmpty ? "다가오는 행사" : "이후 예정", isDark),
            ...upcoming.map((e) => _buildModernCard(e, color, isDark, now)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text, bool isDark) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black87,
      ),
    ),
  );

  /// 종류 딱지. 학교 행사·동아리 공연·버스킹·학과 행사를 한눈에 가른다.
  Widget _categoryBadge(
    ClubEventCategory c,
    bool isDark, {
    bool onImage = false,
  }) {
    final ink = KnueTokens.inkAt(c.inkIndex, isDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onImage
            ? Colors.black.withValues(alpha: 0.45)
            : ink.withValues(alpha: isDark ? 0.24 : 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        c.label,
        style: TextStyle(
          color: onImage ? Colors.white : ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// 카드에 쓸 짧은 날짜. 기간 행사는 "9월 20일 (토) ~ 9월 22일".
  String _whenText(ClubEvent e) {
    final full = DateFormat('M월 d일 (E)', 'ko_KR');
    final end = e.endDate;
    if (end != null && !DateUtils.isSameDay(e.startDate, end)) {
      return "${full.format(e.startDate)} ~ "
          "${DateFormat('M월 d일', 'ko_KR').format(end)}";
    }
    final hhmm = DateFormat('HH:mm').format(e.startDate);
    // 시각 없이 등록하면 00:00이 되는데, 그대로 보이면 새벽 행사처럼 읽힌다.
    return hhmm == '00:00'
        ? full.format(e.startDate)
        : "${full.format(e.startDate)} $hhmm";
  }

  String _ddayText(ClubEvent e, DateTime now) {
    if (e.isOngoing(now)) return '진행중';
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      e.startDate.year,
      e.startDate.month,
      e.startDate.day,
    );
    final days = start.difference(today).inDays;
    if (days <= 0) return '오늘';
    if (days == 1) return '내일';
    return "D-$days";
  }

  /// 진행중인 행사 카드. 포스터를 배경으로 깔고 종류 딱지와 제목,
  /// 날짜·장소만 얹는다. 세로로 쌓이므로 스크롤로 전부 훑을 수 있다.
  Widget _buildHighlightCard(
    ClubEvent event,
    Color color,
    bool isDark,
    DateTime now,
  ) {
    return GestureDetector(
      onTap: () => _showDetail(event, color, isDark),
      child: Container(
        height: 190,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isDark ? 0.18 : 0.22),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (event.posterUrl != null && event.posterUrl!.isNotEmpty)
                Image.network(
                  event.posterUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      _buildPosterFallback(color),
                )
              else
                _buildPosterFallback(color),
              // 글씨가 포스터 위에서 묻히지 않도록 아래쪽만 어둡게.
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black12,
                      Colors.black87,
                    ],
                    stops: [0.3, 0.6, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _categoryBadge(event.category, isDark, onImage: true),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            _ddayText(event, now),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 12,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _whenText(event),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        if (event.location.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.place,
                            size: 12,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterFallback(Color color) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.7), color.withValues(alpha: 0.3)],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.festival_rounded,
        size: 64,
        color: Colors.white.withValues(alpha: 0.4),
      ),
    ),
  );

  Widget _buildModernCard(
    ClubEvent event,
    Color color,
    bool isDark,
    DateTime now,
  ) {
    return GestureDetector(
      onTap: () => _showDetail(event, color, isDark),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
            width: 1,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            _buildPosterThumb(event.posterUrl, color, isDark),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _categoryBadge(event.category, isDark),
                        const Spacer(),
                        Text(
                          _ddayText(event, now),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _cardMetaRow(Icons.schedule, _whenText(event), isDark),
                    if (event.location.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _cardMetaRow(
                        Icons.place_outlined,
                        event.location,
                        isDark,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 카드 아래쪽 한 줄(날짜·장소). 아이콘과 글씨 크기를 한 곳에서 맞춘다.
  Widget _cardMetaRow(IconData icon, String text, bool isDark) {
    final sub = isDark ? Colors.white54 : Colors.black54;
    return Row(
      children: [
        Icon(icon, size: 12, color: sub),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: sub),
          ),
        ),
      ],
    );
  }

  Widget _buildPosterThumb(String? posterUrl, Color color, bool isDark) {
    const size = 96.0;
    Widget placeholder = Container(
      width: size,
      height: size,
      color: color.withValues(alpha: isDark ? 0.2 : 0.1),
      child: Icon(
        Icons.festival_rounded,
        color: color.withValues(alpha: 0.5),
        size: 28,
      ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: posterUrl != null && posterUrl.isNotEmpty
            ? Image.network(
                posterUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => placeholder,
              )
            : placeholder,
      ),
    );
  }

  void _showDetail(ClubEvent event, Color color, bool isDark) {
    final dateFmt = DateFormat('M월 d일 HH:mm', 'ko_KR');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Edge-to-edge Header
              Stack(
                children: [
                  if (event.posterUrl != null && event.posterUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      child: Image.network(
                        event.posterUrl!,
                        width: double.infinity,
                        height: 260,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildDetailPlaceholder(color),
                      ),
                    )
                  else
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      child: _buildDetailPlaceholder(color),
                    ),
                  // Close button
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        shape: const CircleBorder(),
                      ),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (event.isFeatured)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "🔥 오늘의 추천",
                            style: TextStyle(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _categoryBadge(event.category, isDark),
                          if (event.clubName.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                event.clubName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 28),
                      _detailRow(
                        Icons.schedule,
                        event.endDate != null
                            ? "${dateFmt.format(event.startDate)} ~ ${dateFmt.format(event.endDate!)}"
                            : dateFmt.format(event.startDate),
                        isDark,
                      ),
                      const SizedBox(height: 12),
                      _detailRow(Icons.place_outlined, event.location, isDark),
                      const SizedBox(height: 28),
                      const Divider(),
                      const SizedBox(height: 20),
                      Text(
                        event.description.isEmpty
                            ? "상세 설명이 없습니다."
                            : event.description,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      if (event.externalLink != null &&
                          event.externalLink!.isNotEmpty) ...[
                        const SizedBox(height: 36),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () =>
                                _openExternalLink(event.externalLink!),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              "신청 및 문의하기",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(
                        height: MediaQuery.of(sheetContext).padding.bottom + 24,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailPlaceholder(Color color) {
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.4)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.festival_rounded,
          size: 80,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: isDark ? Colors.white54 : Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black87,
              height: 1.3,
            ),
          ),
        ),
      ],
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
}
