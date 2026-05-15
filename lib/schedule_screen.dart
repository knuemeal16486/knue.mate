import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'constants.dart';

// ─── 학사일정 데이터 모델 ────────────────────────────────────────────────────

enum AcademicEventType {
  semester,
  exam,
  holiday,
  vacation,
  registration,
  other,
}

class AcademicEvent {
  final String title;
  final DateTime start;
  final DateTime? end;
  final AcademicEventType type;

  const AcademicEvent({
    required this.title,
    required this.start,
    this.end,
    required this.type,
  });

  bool get isMultiDay => end != null && !isSameDate(start, end!);

  Color get color {
    switch (type) {
      case AcademicEventType.semester:
        return const Color(0xFF2563EB);
      case AcademicEventType.exam:
        return const Color(0xFFEF5350);
      case AcademicEventType.holiday:
        return const Color(0xFF43A047);
      case AcademicEventType.vacation:
        return const Color(0xFF00897B);
      case AcademicEventType.registration:
        return const Color(0xFFFF8F00);
      case AcademicEventType.other:
        return const Color(0xFF7E57C2);
    }
  }

  IconData get icon {
    switch (type) {
      case AcademicEventType.semester:
        return Icons.school_rounded;
      case AcademicEventType.exam:
        return Icons.edit_note_rounded;
      case AcademicEventType.holiday:
        return Icons.flag_rounded;
      case AcademicEventType.vacation:
        return Icons.beach_access_rounded;
      case AcademicEventType.registration:
        return Icons.app_registration_rounded;
      case AcademicEventType.other:
        return Icons.event_rounded;
    }
  }

  String get typeLabel {
    switch (type) {
      case AcademicEventType.semester:
        return '학사';
      case AcademicEventType.exam:
        return '시험';
      case AcademicEventType.holiday:
        return '공휴일';
      case AcademicEventType.vacation:
        return '방학';
      case AcademicEventType.registration:
        return '수강';
      case AcademicEventType.other:
        return '기타';
    }
  }
}

// ─── 2025 한국교원대학교 학사일정 ────────────────────────────────────────────

const List<AcademicEvent> _kAcademicEvents2025 = [
  // ─ 1학기 ─
  AcademicEvent(
    title: '1학기 개강',
    start: DateTime(2025, 3, 3),
    type: AcademicEventType.semester,
  ),
  AcademicEvent(
    title: '수강신청 정정기간',
    start: DateTime(2025, 3, 3),
    end: DateTime(2025, 3, 7),
    type: AcademicEventType.registration,
  ),
  AcademicEvent(
    title: '삼일절',
    start: DateTime(2025, 3, 1),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '개교기념일',
    start: DateTime(2025, 4, 1),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '중간고사',
    start: DateTime(2025, 4, 21),
    end: DateTime(2025, 4, 25),
    type: AcademicEventType.exam,
  ),
  AcademicEvent(
    title: '어린이날',
    start: DateTime(2025, 5, 5),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '부처님 오신 날',
    start: DateTime(2025, 5, 5),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '현충일',
    start: DateTime(2025, 6, 6),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '기말고사',
    start: DateTime(2025, 6, 16),
    end: DateTime(2025, 6, 20),
    type: AcademicEventType.exam,
  ),
  AcademicEvent(
    title: '1학기 종강',
    start: DateTime(2025, 6, 20),
    type: AcademicEventType.semester,
  ),

  // ─ 하계방학 ─
  AcademicEvent(
    title: '하계방학',
    start: DateTime(2025, 6, 21),
    end: DateTime(2025, 8, 29),
    type: AcademicEventType.vacation,
  ),

  // ─ 2학기 ─
  AcademicEvent(
    title: '2학기 개강',
    start: DateTime(2025, 9, 1),
    type: AcademicEventType.semester,
  ),
  AcademicEvent(
    title: '수강신청 정정기간',
    start: DateTime(2025, 9, 1),
    end: DateTime(2025, 9, 5),
    type: AcademicEventType.registration,
  ),
  AcademicEvent(
    title: '추석 연휴',
    start: DateTime(2025, 10, 5),
    end: DateTime(2025, 10, 7),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '개천절',
    start: DateTime(2025, 10, 3),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '한글날',
    start: DateTime(2025, 10, 9),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '중간고사',
    start: DateTime(2025, 10, 20),
    end: DateTime(2025, 10, 24),
    type: AcademicEventType.exam,
  ),
  AcademicEvent(
    title: '기말고사',
    start: DateTime(2025, 12, 15),
    end: DateTime(2025, 12, 19),
    type: AcademicEventType.exam,
  ),
  AcademicEvent(
    title: '2학기 종강',
    start: DateTime(2025, 12, 19),
    type: AcademicEventType.semester,
  ),

  // ─ 동계방학 ─
  AcademicEvent(
    title: '동계방학',
    start: DateTime(2025, 12, 20),
    end: DateTime(2026, 2, 27),
    type: AcademicEventType.vacation,
  ),

  // ─ 2026 1학기 ─
  AcademicEvent(
    title: '삼일절',
    start: DateTime(2026, 3, 1),
    type: AcademicEventType.holiday,
  ),
  AcademicEvent(
    title: '1학기 개강',
    start: DateTime(2026, 3, 2),
    type: AcademicEventType.semester,
  ),
];

// ─── 메인 화면 ────────────────────────────────────────────────────────────────

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final teal = Colors.teal;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            backgroundColor: teal,
            scrolledUnderElevation: 0,
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '학사 · 캠퍼스 일정',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '한국교원대학교 학사일정 및 캠퍼스 소식',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: '학사일정'),
                Tab(text: '캠퍼스 소식'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: const [
            _AcademicCalendarTab(),
            _CampusEventsTab(),
          ],
        ),
      ),
    );
  }
}

// ─── 학사일정 탭 ──────────────────────────────────────────────────────────────

class _AcademicCalendarTab extends StatelessWidget {
  const _AcademicCalendarTab();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sorted = List<AcademicEvent>.from(_kAcademicEvents2025)
      ..sort((a, b) => a.start.compareTo(b.start));

    // Split: upcoming vs past
    final upcoming = sorted
        .where((e) => (e.end ?? e.start).isAfter(now.subtract(const Duration(days: 1))))
        .toList();
    final past = sorted
        .where((e) => (e.end ?? e.start).isBefore(now.subtract(const Duration(days: 1))))
        .toList()
        .reversed
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: [
        // ─ 다가오는 일정 ─
        if (upcoming.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.upcoming_rounded,
            label: '다가오는 일정',
            color: Colors.teal,
          ),
          const SizedBox(height: 12),
          ...upcoming.take(6).map((e) => _AcademicEventCard(event: e, now: now)),
          if (upcoming.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: _ShowMoreButton(
                count: upcoming.length - 6,
                onTap: () => _showAllDialog(context, upcoming, '다가오는 일정'),
              ),
            )
          else
            const SizedBox(height: 16),
        ],

        // ─ 지난 일정 ─
        if (past.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.history_rounded,
            label: '지난 일정',
            color: Colors.grey,
          ),
          const SizedBox(height: 12),
          ...past.take(4).map((e) => _AcademicEventCard(event: e, now: now, isPast: true)),
          if (past.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ShowMoreButton(
                count: past.length - 4,
                onTap: () => _showAllDialog(context, past, '지난 일정'),
              ),
            ),
        ],
      ],
    );
  }

  void _showAllDialog(BuildContext context, List<AcademicEvent> events, String title) {
    final now = DateTime.now();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: events.length,
                  itemBuilder: (_, i) => _AcademicEventCard(
                    event: events[i],
                    now: now,
                    isPast: (events[i].end ?? events[i].start).isBefore(now),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcademicEventCard extends StatelessWidget {
  final AcademicEvent event;
  final DateTime now;
  final bool isPast;

  const _AcademicEventCard({
    required this.event,
    required this.now,
    this.isPast = false,
  });

  String get _dDayText {
    if (isPast) return '완료';
    final diff = event.start.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 0) return 'D-Day';
    if (diff < 0) {
      if (event.end != null && event.end!.isAfter(now)) return '진행 중';
      return '완료';
    }
    return 'D-$diff';
  }

  Color get _dDayColor {
    if (isPast) return Colors.grey;
    final diff = event.start.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 0) return Colors.redAccent;
    if (diff < 0) {
      if (event.end != null && event.end!.isAfter(now)) return Colors.orange;
      return Colors.grey;
    }
    if (diff <= 7) return Colors.orange;
    return event.color;
  }

  String get _dateText {
    final m = '${event.start.month.toString().padLeft(2, '0')}';
    final d = '${event.start.day.toString().padLeft(2, '0')}';
    if (event.end == null || isSameDate(event.start, event.end!)) {
      return '$m/$d';
    }
    final em = '${event.end!.month.toString().padLeft(2, '0')}';
    final ed = '${event.end!.day.toString().padLeft(2, '0')}';
    return '$m/$d ~ $em/$ed';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ddText = _dDayText;
    final ddColor = _dDayColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPast
              ? (isDark ? Colors.white10 : Colors.grey.shade200)
              : event.color.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: isPast
            ? []
            : [
                BoxShadow(
                  color: event.color.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isPast
                  ? (isDark ? Colors.grey.shade800 : Colors.grey.shade100)
                  : event.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              event.icon,
              color: isPast ? Colors.grey : event.color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isPast
                        ? (isDark ? Colors.grey.shade500 : Colors.grey.shade500)
                        : null,
                    decoration: isPast ? TextDecoration.none : null,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isPast ? Colors.grey : event.color).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        event.typeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isPast ? Colors.grey : event.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _dateText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ddColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ddColor.withOpacity(0.3), width: 1),
            ),
            child: Text(
              ddText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: ddColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 캠퍼스 소식 탭 ──────────────────────────────────────────────────────────

class _CampusEventsTab extends StatelessWidget {
  const _CampusEventsTab();

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return const _EmptyCampusEvents();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('campus_events')
          .orderBy('eventDate', descending: false)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const _EmptyCampusEvents();
        }

        final docs = snapshot.data!.docs;
        final now = DateTime.now();

        final upcoming = <QueryDocumentSnapshot>[];
        final past = <QueryDocumentSnapshot>[];

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = data['eventDate'];
          DateTime? date;
          if (ts is Timestamp) date = ts.toDate();
          if (date == null) continue;
          if (date.isAfter(now.subtract(const Duration(days: 1)))) {
            upcoming.add(doc);
          } else {
            past.add(doc);
          }
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          children: [
            if (upcoming.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.campaign_rounded,
                label: '다가오는 캠퍼스 소식',
                color: Colors.teal,
              ),
              const SizedBox(height: 12),
              ...upcoming.map((doc) => _CampusEventCard(
                    doc: doc.data() as Map<String, dynamic>,
                    now: now,
                  )),
              const SizedBox(height: 16),
            ],
            if (past.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.history_rounded,
                label: '지난 소식',
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              ...past.reversed
                  .take(5)
                  .map((doc) => _CampusEventCard(
                        doc: doc.data() as Map<String, dynamic>,
                        now: now,
                        isPast: true,
                      )),
            ],
          ],
        );
      },
    );
  }
}

class _CampusEventCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final DateTime now;
  final bool isPast;

  const _CampusEventCard({
    required this.doc,
    required this.now,
    this.isPast = false,
  });

  static const Map<String, Color> _categoryColors = {
    '동아리': Color(0xFF7C4DFF),
    '공연': Color(0xFFE91E63),
    '축제': Color(0xFFFF6F00),
    '학교행사': Color(0xFF0288D1),
    '스포츠': Color(0xFF43A047),
    '기타': Color(0xFF78909C),
  };

  static const Map<String, IconData> _categoryIcons = {
    '동아리': Icons.groups_rounded,
    '공연': Icons.music_note_rounded,
    '축제': Icons.celebration_rounded,
    '학교행사': Icons.account_balance_rounded,
    '스포츠': Icons.sports_rounded,
    '기타': Icons.event_note_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = doc['title'] as String? ?? '제목 없음';
    final category = doc['category'] as String? ?? '기타';
    final description = doc['description'] as String? ?? '';
    final location = doc['location'] as String? ?? '';

    final ts = doc['eventDate'];
    DateTime? date;
    if (ts is Timestamp) date = ts.toDate();

    final color = _categoryColors[category] ?? const Color(0xFF78909C);
    final icon = _categoryIcons[category] ?? Icons.event_note_rounded;

    String dDayText = '';
    if (date != null && !isPast) {
      final diff = date.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (diff == 0) {
        dDayText = 'D-Day';
      } else if (diff > 0) {
        dDayText = 'D-$diff';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPast
              ? (isDark ? Colors.white10 : Colors.grey.shade200)
              : color.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: isPast
            ? []
            : [
                BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              color: isPast ? Colors.grey.shade400 : color,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: isPast ? Colors.grey : color, size: 18),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isPast ? Colors.grey : color).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPast ? Colors.grey : color,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (dDayText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: dDayText == 'D-Day'
                                ? Colors.redAccent.withOpacity(0.1)
                                : color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: dDayText == 'D-Day'
                                  ? Colors.redAccent.withOpacity(0.3)
                                  : color.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            dDayText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: dDayText == 'D-Day' ? Colors.redAccent : color,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isPast
                          ? (isDark ? Colors.grey.shade500 : Colors.grey.shade500)
                          : null,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (date != null || location.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (date != null)
                          _InfoChip(
                            icon: Icons.calendar_today_rounded,
                            text:
                                '${date.month}월 ${date.day}일 (${_weekdayLabel(date.weekday)})',
                          ),
                        if (location.isNotEmpty)
                          _InfoChip(
                            icon: Icons.place_rounded,
                            text: location,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekdayLabel(int w) {
    const labels = ['', '월', '화', '수', '목', '금', '토', '일'];
    return labels[w];
  }
}

// ─── 빈 화면 ─────────────────────────────────────────────────────────────────

class _EmptyCampusEvents extends StatelessWidget {
  const _EmptyCampusEvents();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_note_rounded,
                size: 52,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '등록된 캠퍼스 소식이 없어요',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '동아리 공연, 축제 등 캠퍼스 이벤트가\n이곳에 표시됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 공통 위젯 ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: color,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _ShowMoreButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ShowMoreButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.teal.withOpacity(0.2)),
        ),
        child: Text(
          '+ $count개 더 보기',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.teal,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
