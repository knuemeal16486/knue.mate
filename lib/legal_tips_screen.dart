import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'legal_tips.dart';
import 'ui_utils.dart';

/// 주제마다 잉크색 하나. 탭·카드 그림 바탕·상세 창의 강조에 같이 쓴다.
Color _topicInk(LegalTopic topic, bool isDark) => KnueTokens.inkAt(
      switch (topic) {
        LegalTopic.housing => 1, // teal
        LegalTopic.tutoring => 6, // indigo
        LegalTopic.partTime => 2, // clay
        LegalTopic.life => 3, // plum
      },
      isDark,
    );

/// 주제 탭의 그림. 이모지는 기기마다 모양이 다르고 화면이 요란해져서
/// 선으로 된 아이콘만 쓴다.
IconData _topicIcon(LegalTopic topic) => switch (topic) {
      LegalTopic.housing => Icons.home_outlined,
      LegalTopic.tutoring => Icons.school_outlined,
      LegalTopic.partTime => Icons.storefront_outlined,
      LegalTopic.life => Icons.backpack_outlined,
    };

Color _softText(bool isDark) =>
    isDark ? Colors.white60 : const Color(0xFF6B6B70);

Color _strongText(bool isDark) =>
    isDark ? const Color(0xFFF2F2F7) : const Color(0xFF2C2C2E);

Future<void> _openUri(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // 실행 실패는 조용히 무시 (브라우저·전화 앱 부재 등)
  }
}

/// 법률상식 화면.
///
/// 목록은 제목과 한 줄 요약만 보이는 가벼운 카드로 두고, 본문은 카드를
/// 눌렀을 때 아래에서 올라오는 창에서 읽는다 — 목록에서 본문까지 펼치면
/// 글이 벽처럼 쌓여 읽기 싫어진다. 내용은 전부 [kLegalTips]에 있고 서버에서
/// 받는 것이 없다.
class LegalTipsScreen extends StatefulWidget {
  const LegalTipsScreen({super.key});

  @override
  State<LegalTipsScreen> createState() => _LegalTipsScreenState();
}

class _LegalTipsScreenState extends State<LegalTipsScreen> {
  String _query = '';
  LegalTopic _topic = LegalTopic.housing;
  String? _group; // null = 전체

  void _selectTopic(LegalTopic topic) {
    if (topic == _topic) return;
    setState(() {
      _topic = topic;
      _group = null; // 묶음 이름은 주제마다 다르다
    });
  }

  void _showTip(LegalTip tip) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LegalTipSheet(tip: tip, topic: _topic),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final ink = _topicInk(_topic, isDark);
        // 묶음 칩은 검색어와 상관없이 그 주제의 묶음을 전부 보여 준다.
        final groups =
            groupLegalTips(filterLegalTips(kLegalTips, topic: _topic))
                .keys
                .toList();
        final tips = filterLegalTips(
          kLegalTips,
          topic: _topic,
          group: _group,
          query: _query,
        );
        final grouped = groupLegalTips(tips);

        return Scaffold(
          appBar: AppBar(
            title: const Text("법률상식"),
            backgroundColor: Colors.transparent,
            flexibleSpace: AppleAppBarFlexibleSpace(
              themeColor: color,
              isDark: isDark,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: "궁금한 걸 검색해 보세요",
                    hintStyle: TextStyle(color: _softText(isDark)),
                    prefixIcon: Icon(Icons.search, color: _softText(isDark)),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              _buildTopicTabs(isDark),
              _buildGroupChips(groups, ink, isDark),
              Expanded(
                child: ListView(
                  // 주제나 묶음을 바꾸면 맨 위에서 다시 시작한다.
                  key: ValueKey('$_topic-$_group'),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                      child: Text(
                        _topic.intro,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: _softText(isDark),
                        ),
                      ),
                    ),
                    if (tips.isEmpty) _buildEmpty(ink, isDark),
                    for (final entry in grouped.entries) ...[
                      _buildGroupHeader(entry.key, isDark),
                      for (final t in entry.value) _buildTipCard(t, isDark),
                    ],
                    _buildContacts(ink, isDark),
                    _buildNotice(isDark),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 주제 전환. 테두리나 칸막이 없이, 고른 칸만 그 주제 색으로 옅게 물든다.
  Widget _buildTopicTabs(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: LegalTopic.values.map((topic) {
          final active = topic == _topic;
          final ink = _topicInk(topic, isDark);
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _selectTopic(topic),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
                decoration: BoxDecoration(
                  color: active
                      ? ink.withValues(alpha: isDark ? 0.24 : 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _topicIcon(topic),
                      size: 22,
                      color: active ? ink : _softText(isDark),
                    ),
                    const SizedBox(height: 4),
                    // "학원강사(과외)"가 좁은 폰에서 칸을 넘지 않게 줄인다.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        topic.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: -0.2,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? ink : _softText(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 주제 안의 묶음으로 좁힌다. 집 계약은 25개라 한 번에 훑기엔 길다.
  Widget _buildGroupChips(List<String> groups, Color ink, bool isDark) {
    Widget chip(String label, String? group) {
      final active = _group == group;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => setState(() => _group = group),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: active
                  ? ink.withValues(alpha: isDark ? 0.30 : 0.14)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? (isDark ? Colors.white : ink)
                    : _softText(isDark),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 10, 8),
        children: [
          chip('전체', null),
          for (final g in groups) chip(g, g),
        ],
      ),
    );
  }

  /// 결과가 없을 때. 다른 주제에 걸리는 것이 있으면 바로 건너가게 해 준다.
  Widget _buildEmpty(Color ink, bool isDark) {
    final elsewhere = countLegalMatchesByTopic(kLegalTips, _query)
      ..remove(_topic);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 30,
            color: _softText(isDark).withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            "여기에는 없어요",
            style: TextStyle(fontSize: 14.5, color: _softText(isDark)),
          ),
          if (_group != null && elsewhere.isEmpty)
            TextButton(
              onPressed: () => setState(() => _group = null),
              style: TextButton.styleFrom(foregroundColor: ink),
              child: const Text("묶음을 전체로 넓히기"),
            ),
          for (final entry in elsewhere.entries)
            TextButton(
              onPressed: () => _selectTopic(entry.key),
              style: TextButton.styleFrom(
                foregroundColor: _topicInk(entry.key, isDark),
              ),
              child: Text(
                "${entry.key.label}에서 ${entry.value}건 보기",
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String group, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 20, 6, 10),
      child: Text(
        group,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: _softText(isDark),
        ),
      ),
    );
  }

  /// 목록 카드: 제목 + 한 줄 요약. 누르면 상세 창이 올라온다.
  Widget _buildTipCard(LegalTip t, bool isDark) {
    final radius = BorderRadius.circular(18);
    return KnueCard(
      isDark: isDark,
      radius: 18,
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: () => _showTip(t),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 10, 15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        keepKoreanWords(t.title),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: _strongText(isDark),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        keepKoreanWords(t.summary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: _softText(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: _softText(isDark).withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 혼자 풀기 어려울 때 물어볼 곳. 고른 주제에 맞는 곳만, 검색어와 상관없이
  /// 늘 목록 아래에 둔다.
  Widget _buildContacts(Color ink, bool isDark) {
    final contacts =
        kLegalContacts.where((c) => c.topics.contains(_topic)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupHeader("혼자 풀기 어려울 땐 여기에 물어봐요", isDark),
        KnueCard(
          isDark: isDark,
          radius: 18,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  for (final c in contacts)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        c.name,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: _strongText(isDark),
                        ),
                      ),
                      subtitle: Text(
                        c.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _softText(isDark),
                        ),
                      ),
                      trailing: c.tel != null
                          ? Text(
                              c.tel!,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: ink,
                                fontWeight: FontWeight.w700,
                                fontFeatures: KnueTokens.tabularFigures,
                              ),
                            )
                          : Icon(
                              Icons.open_in_new_rounded,
                              size: 17,
                              color: ink,
                            ),
                      onTap: () => _openUri(
                        c.tel != null
                            ? Uri(scheme: 'tel', path: c.tel)
                            : Uri.parse(c.url!),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 맨 아래 안내문. 법은 바뀌므로 언제 확인한 내용인지와, 자문이 아니라는
  /// 점을 적어 둔다. 같은 말을 상세 창 끝에도 한 줄로 붙인다.
  Widget _buildNotice(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 20, 6, 0),
      child: Text(
        "$kLegalTipsAsOf 기준으로 정리한 일반 정보예요. 법률 자문이 아니고, "
        "금액과 기한은 바뀔 수 있으니 중요한 결정 전에 한 번 더 확인하세요.",
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: KnueTokens.caption(isDark),
        ),
      ),
    );
  }
}

/// 항목 하나의 본문. 아래에서 올라오고, 끌어서 키우거나 닫는다.
class _LegalTipSheet extends StatelessWidget {
  final LegalTip tip;
  final LegalTopic topic;

  const _LegalTipSheet({required this.tip, required this.topic});

  Future<void> _copy(BuildContext context, String text) async {
    // 시트 위에서는 SnackBar가 가려지므로 오버레이 토스트를 쓴다.
    final overlay = overlayOf(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (overlay != null) showOverlayToastOn(overlay, '문구를 복사했어요');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = _topicInk(topic, isDark);
    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, controller) {
        return Container(
          key: const Key('legal-tip-sheet'),
          decoration: BoxDecoration(
            color: KnueTokens.surface(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              // 어느 묶음의 글인지 작은 이름표로만 알린다.
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: isDark ? 0.24 : 0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tip.group,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                keepKoreanWords(tip.title),
                style: TextStyle(
                  fontSize: 21,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: _strongText(isDark),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                keepKoreanWords(tip.summary),
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: _softText(isDark),
                ),
              ),
              const SizedBox(height: 18),
              for (final p in tip.points) _buildPoint(context, p, ink, isDark),
              if (tip.basis != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                    keepKoreanWords("근거 · ${tip.basis}"),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: KnueTokens.caption(isDark),
                    ),
                  ),
                ),
              if (tip.linkUrl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextButton(
                    onPressed: () => _openUri(Uri.parse(tip.linkUrl!)),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : ink,
                      backgroundColor:
                          ink.withValues(alpha: isDark ? 0.26 : 0.11),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text("${tip.linkLabel} 열어 보기"),
                  ),
                ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  "$kLegalTipsAsOf 기준 · 일반 정보이며 법률 자문이 아니에요",
                  style: TextStyle(
                    fontSize: 11.5,
                    color: KnueTokens.caption(isDark),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 본문 한 줄. 줄마다 옅은 칸에 담아 한 번에 하나씩 읽히게 한다.
  Widget _buildPoint(
    BuildContext context,
    String point,
    Color ink,
    bool isDark,
  ) {
    final base = TextStyle(
      fontSize: 14.5,
      height: 1.6,
      letterSpacing: -0.1,
      color: isDark ? const Color(0xFFD8D8DC) : const Color(0xFF3A3A3C),
    );
    final bold = TextStyle(
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
    );
    final softFill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF6F6F9);
    final label = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: ink,
    );

    switch (legalPointKind(point)) {
      case LegalPointKind.example:
        final body = plainLegalText(point).trim().substring(2).trim();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          decoration: BoxDecoration(
            color: softFill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("계산해 보면", style: label),
              const SizedBox(height: 3),
              Text(
                keepKoreanWords(body),
                style: base.copyWith(fontFeatures: KnueTokens.tabularFigures),
              ),
            ],
          ),
        );
      case LegalPointKind.quote:
        final body = plainLegalText(point).trim();
        final sentence = body.substring(1, body.length - 1);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 11, 6, 12),
          decoration: BoxDecoration(
            color: ink.withValues(alpha: isDark ? 0.18 : 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("이대로 써도 돼요", style: label),
                    const SizedBox(height: 3),
                    Text(keepKoreanWords(sentence), style: base),
                  ],
                ),
              ),
              IconButton(
                tooltip: "문구 복사",
                onPressed: () => _copy(context, sentence),
                icon: const Icon(Icons.copy_rounded, size: 17),
                color: ink,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        );
      case LegalPointKind.normal:
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 12),
          decoration: BoxDecoration(
            color: softFill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 10),
                child: Icon(Icons.check_circle_rounded, size: 17, color: ink),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      for (final s in legalDisplaySpans(point))
                        TextSpan(text: s.text, style: s.bold ? bold : null),
                    ],
                  ),
                  style: base,
                ),
              ),
            ],
          ),
        );
    }
  }
}
