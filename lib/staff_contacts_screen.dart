import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_staff_data.dart';
import 'constants.dart';
import 'ui_utils.dart';

/// 연락처 화면에서 보여줄 범위.
enum ContactScope {
  all('전체'),
  admin('행정'),
  dept('과 사무실');

  final String label;
  const ContactScope(this.label);
}

/// 한 줄로 표시할 연락처. 행정 직원([AdminStaff])과 과 사무실([DeptOffice])은
/// 필드가 다르지만 화면에서는 같은 모양으로 보여주므로 여기로 통일한다.
class _ContactRow {
  final String title; // 직위 또는 학과명
  final String? subtitle; // 담당 업무 또는 위치
  final String phone;
  final String group; // 묶음 제목(부서 / 단과대학)
  final bool isDept;

  const _ContactRow({
    required this.title,
    required this.subtitle,
    required this.phone,
    required this.group,
    required this.isDept,
  });
}

/// 교직원 연락처 화면.
///
/// 행정 부서([kAdminStaff])와 과 사무실([kDeptOffices])을 한 화면에 모았다.
/// 예전에는 과 사무실이 캠퍼스맵 안에 따로 있어서, 번호를 찾으려면 두 화면을
/// 오가야 했고 어느 쪽이 최신인지도 알 수 없었다.
class StaffContactsScreen extends StatefulWidget {
  /// 과 사무실만 보이는 상태로 열지 여부. 캠퍼스맵에서 넘어올 때 쓴다.
  final bool initialDeptOnly;

  const StaffContactsScreen({super.key, this.initialDeptOnly = false});

  @override
  State<StaffContactsScreen> createState() => _StaffContactsScreenState();
}

class _StaffContactsScreenState extends State<StaffContactsScreen> {
  String _query = '';
  late ContactScope _scope =
      widget.initialDeptOnly ? ContactScope.dept : ContactScope.all;

  /// 검색 범위에 맞는 연락처를 묶음별로 그룹핑한다.
  /// 검색어는 직위·부서·학과·업무·건물 어디에 걸려도 잡히게 한다.
  Map<String, List<_ContactRow>> get _grouped {
    final q = _query.trim();
    final rows = <_ContactRow>[];

    if (_scope != ContactScope.dept) {
      for (final s in kAdminStaff) {
        rows.add(_ContactRow(
          title: s.category,
          subtitle: s.duties.isNotEmpty ? s.duties : null,
          phone: s.phone,
          group: s.dept,
          isDept: false,
        ));
      }
    }
    if (_scope != ContactScope.admin) {
      for (final d in kDeptOffices) {
        rows.add(_ContactRow(
          title: d.dept,
          subtitle: '${d.building} ${d.room}',
          phone: d.phone,
          group: d.college,
          isDept: true,
        ));
      }
    }

    final filtered = q.isEmpty
        ? rows
        : rows
            .where((r) =>
                r.title.contains(q) ||
                r.group.contains(q) ||
                (r.subtitle?.contains(q) ?? false))
            .toList();

    final grouped = <String, List<_ContactRow>>{};
    for (final r in filtered) {
      grouped.putIfAbsent(r.group, () => []).add(r);
    }
    return grouped;
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      // 실행 실패는 조용히 무시 (전화 앱 부재 등)
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final grouped = _grouped;
        final groups = grouped.keys.toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text("교직원 연락처"),
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: "학과·부서·직위로 검색",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              _buildScopeToggle(color, isDark),
              Expanded(
                child: groups.isEmpty
                    ? Center(
                        child: Text(
                          "검색 결과가 없습니다",
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final members = grouped[group]!;
                          return _buildGroupCard(
                              group, members, color, isDark);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 전체 / 행정 / 과 사무실 전환. 과 사무실 번호만 훑어보고 싶을 때가 많아
  /// 검색어를 지우지 않고도 범위를 좁힐 수 있게 했다.
  Widget _buildScopeToggle(Color color, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: ContactScope.values.map((scope) {
          final active = scope == _scope;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _scope = scope),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: active
                      ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.3 : 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    scope.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? color
                          : (isDark ? Colors.white54 : Colors.black54),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGroupCard(
    String group,
    List<_ContactRow> members,
    Color color,
    bool isDark,
  ) {
    // 과 사무실 묶음은 잉크색으로 구분해, 섞여 있어도 한눈에 갈린다.
    final isDeptGroup = members.first.isDept;
    final accent =
        isDeptGroup ? KnueTokens.inkAt(1, isDark) : color; // 1 = teal

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _query.isNotEmpty,
          leading: Icon(
            isDeptGroup ? Icons.school_rounded : Icons.apartment_rounded,
            size: 20,
            color: accent,
          ),
          title: Text(
            group,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text(
            isDeptGroup ? "학과 ${members.length}곳" : "${members.length}명",
          ),
          children: members
              .map((m) => ListTile(
                    title: Text(
                      m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: m.subtitle == null
                        ? null
                        : Text(
                            m.subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          m.phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: accent,
                            fontWeight: FontWeight.w600,
                            fontFeatures: KnueTokens.tabularFigures,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.call, size: 18, color: accent),
                      ],
                    ),
                    onTap: () => _call(m.phone),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
