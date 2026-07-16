import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'club_event_model.dart';
import 'club_event_service.dart';
import 'constants.dart';

/// 동아리 공연·행사 학생용 전체 목록 화면.
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
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      final list = await ClubEventService.fetchAll(forceRefresh: force);
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
    }
  }

  List<ClubEvent> get _featuredEvents =>
      _events.where((e) => e.isFeatured).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

  List<ClubEvent> get _regularEvents =>
      _events.where((e) => !e.isFeatured).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

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
            centerTitle: (!kIsWeb && Platform.isIOS) ? false : null,
            title: const Text("동아리 공연·행사"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh),
                tooltip: "새로고침",
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
                  Icon(Icons.error_outline,
                      size: 40,
                      color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(height: 12),
                  Text(
                    "불러오기 실패",
                    style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54),
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

    final featured = _featuredEvents;
    final regular = _regularEvents;

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (featured.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                "녹출",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            ...featured.map((e) => _buildCard(e, color, isDark, featured: true)),
            const SizedBox(height: 8),
          ],
          ...regular.map((e) => _buildCard(e, color, isDark, featured: false)),
        ],
      ),
    );
  }

  Widget _buildCard(ClubEvent event, Color color, bool isDark,
      {required bool featured}) {
    final dateFmt = DateFormat('M월 d일 HH:mm', 'ko_KR');
    return GestureDetector(
      onTap: () => _showDetail(event, color, isDark),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: featured
                ? color
                : (isDark ? Colors.white12 : const Color(0xFFE5E7EB)),
            width: featured ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPosterThumb(event.posterUrl, color, isDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (featured) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "녹출",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.clubName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 13,
                          color: isDark ? Colors.white38 : Colors.black38),
                      const SizedBox(width: 4),
                      Text(
                        dateFmt.format(event.startDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 13,
                          color: isDark ? Colors.white38 : Colors.black38),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterThumb(String? posterUrl, Color color, bool isDark) {
    const size = 56.0;
    if (posterUrl == null || posterUrl.isEmpty) {
      return _posterPlaceholder(color, isDark, size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        posterUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _posterPlaceholder(color, isDark, size),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _posterPlaceholder(color, isDark, size);
        },
      ),
    );
  }

  Widget _posterPlaceholder(Color color, bool isDark, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.theater_comedy_outlined, color: color, size: 26),
    );
  }

  void _showDetail(ClubEvent event, Color color, bool isDark) {
    final dateFmt = DateFormat('M월 d일 HH:mm', 'ko_KR');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
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
                  if (event.posterUrl != null && event.posterUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        event.posterUrl!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        },
                      ),
                    ),
                  if (event.posterUrl != null && event.posterUrl!.isNotEmpty)
                    const SizedBox(height: 16),
                  if (event.isFeatured)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "녹출",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    event.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.clubName,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow(
                    Icons.schedule,
                    event.endDate != null
                        ? "${dateFmt.format(event.startDate)} ~ ${dateFmt.format(event.endDate!)}"
                        : dateFmt.format(event.startDate),
                    isDark,
                  ),
                  const SizedBox(height: 6),
                  _detailRow(Icons.place_outlined, event.location, isDark),
                  const SizedBox(height: 16),
                  Text(
                    event.description.isEmpty
                        ? "상세 설명이 없습니다."
                        : event.description,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  if (event.externalLink != null &&
                      event.externalLink!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            _openExternalLink(event.externalLink!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text("신청/문의"),
                      ),
                    ),
                  ],
                  SizedBox(height: MediaQuery.of(sheetContext).padding.bottom + 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: isDark ? Colors.white54 : Colors.black54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
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
