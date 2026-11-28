import 'dart:async';
import 'package:flutter/material.dart';
import '../../ui_utils.dart';

/// 실시간 버스 목록 상단의 "N초 전 갱신 · 운행 중 N대" 상태 바.
///
/// 1초마다 경과 시간을 갱신하지만, 타이머와 `setState`를 이 작은 위젯 안에
/// 격리해 부모인 `BusAppScreen` 전체(2,300+줄)가 매초 리빌드되는 것을 막는다.
class BusLastUpdateBar extends StatefulWidget {
  final DateTime lastUpdateTime;
  final bool isRefreshing;
  final int totalBuses;
  final bool isDark;

  const BusLastUpdateBar({
    super.key,
    required this.lastUpdateTime,
    required this.isRefreshing,
    required this.totalBuses,
    required this.isDark,
  });

  @override
  State<BusLastUpdateBar> createState() => _BusLastUpdateBarState();
}

class _BusLastUpdateBarState extends State<BusLastUpdateBar>
    with WidgetsBindingObserver {
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _tickTimer?.cancel();
      _tickTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _startTicker();
      if (mounted) setState(() {});
    }
  }

  void _startTicker() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.isRefreshing) {
        setState(() {});
      }
    });
  }

  String _formatLastUpdate(Duration diff) {
    if (diff.inSeconds < 5) return "방금 갱신";
    if (diff.inSeconds < 60) return "${diff.inSeconds}초 전 갱신";
    if (diff.inMinutes < 5) return "${diff.inMinutes}분 전 갱신";
    return "${diff.inMinutes}분 전 (갱신 필요)";
  }

  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(widget.lastUpdateTime);
    final isStale = diff.inMinutes >= 3;
    final statusText = widget.isRefreshing
        ? "갱신 중..."
        : "${_formatLastUpdate(diff)} · 운행 중 ${widget.totalBuses}대";

    return Semantics(
      liveRegion: true,
      label: statusText,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(
          children: [
            if (widget.isRefreshing) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.isDark ? Colors.white24 : Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "갱신 중...",
                style: TextStyle(
                  fontSize: 11,
                  color: widget.isDark ? Colors.white38 : Colors.grey.shade500,
                ),
              ),
            ] else ...[
              // 살아있는 데이터라는 신호 — 맥동하는 앰버 점(보조색).
              KnueLiveDot(isDark: widget.isDark),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 11,
                  fontFeatures: KnueTokens.tabularFigures,
                  color: isStale
                      ? KnueTokens.warm(widget.isDark)
                      : (widget.isDark ? Colors.white38 : Colors.grey.shade500),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
