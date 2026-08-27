import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'constants.dart';
import 'notice_model.dart';
import 'notice_service.dart';
import 'schedule_model.dart';

/// 청람일정 화면. 학사일정(월별 크롤링 캐시) + 개인일정을 캘린더에 표시하고,
/// 하단에는 D-day 카드 목록을 보여준다.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _scraper = KnueScraper();

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  /// 월별 학사일정 캐시. 키는 year * 100 + month.
  final Map<int, List<CalendarEvent>> _academicCache = {};
  bool _loadingCalendar = false;

  @override
  void initState() {
    super.initState();
    _loadMonth(_focusedDay.year, _focusedDay.month);
  }

  int _monthKey(int year, int month) => year * 100 + month;

  Future<void> _loadMonth(int year, int month) async {
    final key = _monthKey(year, month);
    if (_academicCache.containsKey(key)) return;
    setState(() => _loadingCalendar = true);
    try {
      final events = await _scraper.fetchCalendarEvents(year, month);
      if (!mounted) return;
      setState(() {
        _academicCache[key] = events;
        _loadingCalendar = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingCalendar = false);
    }
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<CalendarEvent> _academicEventsOn(DateTime day) {
    final events = _academicCache[_monthKey(day.year, day.month)] ?? [];
    final target = DateTime(day.year, day.month, day.day);
    return events.where((e) {
      final start = DateTime(e.startDate.year, e.startDate.month, e.startDate.day);
      final end = DateTime(e.endDate.year, e.endDate.month, e.endDate.day);
      return !target.isBefore(start) && !target.isAfter(end);
    }).toList();
  }

  List<PersonalEvent> _personalEventsOn(DateTime day) {
    return PreferencesService.personalEvents.value
        .where((e) => _isSameDate(e.date, day))
        .toList();
  }

  List<Object> _mergedEventsOn(DateTime day) => [
        ..._academicEventsOn(day),
        ..._personalEventsOn(day),
      ];

  Future<void> _deleteDday(DdayItem item) async {
    final list = List<DdayItem>.from(PreferencesService.ddayItems.value)
      ..removeWhere((e) => e.id == item.id);
    await PreferencesService.saveDdayItems(list);
  }

  Future<void> _deletePersonalEvent(PersonalEvent event) async {
    final list = List<PersonalEvent>.from(PreferencesService.personalEvents.value)
      ..removeWhere((e) => e.id == event.id);
    await PreferencesService.savePersonalEvents(list);
  }

  Future<void> _confirmDeletePersonalEvent(PersonalEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("일정 삭제"),
        content: Text("'${event.title}' 일정을 삭제할까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("삭제", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deletePersonalEvent(event);
  }

  Future<void> _showAddPersonalEventDialog(Color color) async {
    final day = _selectedDay;
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("${_formatShortDate(day)} 일정 추가"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "일정 제목 입력"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            child: const Text("추가"),
          ),
        ],
      ),
    );
    final title = controller.text.trim();
    controller.dispose();
    if (result == true && title.isNotEmpty) {
      final event = PersonalEvent(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        date: day,
      );
      final list = List<PersonalEvent>.from(PreferencesService.personalEvents.value)
        ..add(event);
      await PreferencesService.savePersonalEvents(list);
    }
  }

  Future<void> _showAddDdayDialog(Color color) async {
    final controller = TextEditingController();
    DateTime picked = DateTime.now();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("D-day 추가"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: "제목 입력"),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: picked,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setDialogState(() => picked = d);
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 8),
                        Text(_formatShortDate(picked)),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text("취소"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("추가"),
                ),
              ],
            );
          },
        );
      },
    );
    final title = controller.text.trim();
    controller.dispose();
    if (result == true && title.isNotEmpty) {
      final item = DdayItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        date: picked,
      );
      final list = List<DdayItem>.from(PreferencesService.ddayItems.value)..add(item);
      await PreferencesService.saveDdayItems(list);
    }
  }

  String _formatShortDate(DateTime d) =>
      "${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}";

  String _ddayLabel(int daysLeft) {
    if (daysLeft == 0) return "D-DAY";
    return daysLeft > 0 ? "D-$daysLeft" : "D+${-daysLeft}";
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: const Text("청람일정"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                onPressed: () => _showAddDdayDialog(color),
                icon: const Icon(Icons.add_alarm),
                tooltip: "D-day 추가",
              ),
            ],
          ),
          body: ValueListenableBuilder<List<PersonalEvent>>(
            valueListenable: PreferencesService.personalEvents,
            builder: (context, personalEvents, child) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loadingCalendar) const LinearProgressIndicator(minHeight: 2),
                    _buildCalendarCard(color, isDark),
                    _buildSelectedDayEvents(color, isDark),
                    const SizedBox(height: 8),
                    _buildDdaySection(color, isDark),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddPersonalEventDialog(color),
            backgroundColor: color,
            tooltip: "개인일정 추가",
            child: const Icon(Icons.add, color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildCalendarCard(Color color, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      child: TableCalendar<Object>(
        locale: 'ko_KR',
        firstDay: DateTime(2000, 1, 1),
        lastDay: DateTime(2100, 12, 31),
        focusedDay: _focusedDay,
        currentDay: DateTime.now(),
        selectedDayPredicate: (day) => _isSameDate(day, _selectedDay),
        eventLoader: _mergedEventsOn,
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          });
        },
        onPageChanged: (focused) {
          _focusedDay = focused;
          _loadMonth(focused.year, focused.month);
        },
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
          leftChevronIcon: Icon(
            Icons.chevron_left,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          rightChevronIcon: Icon(
            Icons.chevron_right,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekendStyle: TextStyle(color: Colors.redAccent),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          weekendTextStyle: const TextStyle(color: Colors.redAccent),
          todayDecoration: BoxDecoration(
            color: color.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          markerDecoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedDayEvents(Color color, bool isDark) {
    final academic = _academicEventsOn(_selectedDay);
    final personal = _personalEventsOn(_selectedDay);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
          Text(
            DateFormat('M월 d일 (E)', 'ko_KR').format(_selectedDay),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          if (academic.isEmpty && personal.isEmpty)
            Text(
              "일정이 없습니다",
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...academic.map((e) => Chip(
                      label: Text(e.title),
                      backgroundColor: color.withValues(alpha: 0.12),
                      labelStyle: TextStyle(color: color, fontSize: 12),
                      side: BorderSide.none,
                    )),
                ...personal.map((e) => GestureDetector(
                      onLongPress: () => _confirmDeletePersonalEvent(e),
                      child: Chip(
                        label: Text(e.title),
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.18),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        side: BorderSide.none,
                      ),
                    )),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDdaySection(Color color, bool isDark) {
    return ValueListenableBuilder<List<DdayItem>>(
      valueListenable: PreferencesService.ddayItems,
      builder: (context, items, child) {
        final now = DateTime.now();
        final sorted = List<DdayItem>.from(items)
          ..sort((a, b) => a.daysLeft(now).compareTo(b.daysLeft(now)));
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "D-day",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "등록된 D-day가 없습니다",
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                )
              else
                ...sorted.map((item) => _buildDdayCard(item, color, isDark, now)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDdayCard(DdayItem item, Color color, bool isDark, DateTime now) {
    final daysLeft = item.daysLeft(now);
    return Dismissible(
      key: ValueKey('dday-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      onDismissed: (_) => _deleteDday(item),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _ddayLabel(daysLeft),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            Text(
              _formatShortDate(item.date),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
