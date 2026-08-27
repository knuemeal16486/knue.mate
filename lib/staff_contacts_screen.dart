import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_staff_data.dart';
import 'constants.dart';

/// 교직원 연락처 화면. kAdminStaff를 부서별로 그룹핑해 ExpansionTile로
/// 보여주고, 상단 검색으로 직위/부서 기준 필터링한다. 항목을 탭하면
/// tel: 스킴으로 전화 연결을 시도한다.
class StaffContactsScreen extends StatefulWidget {
  const StaffContactsScreen({super.key});

  @override
  State<StaffContactsScreen> createState() => _StaffContactsScreenState();
}

class _StaffContactsScreenState extends State<StaffContactsScreen> {
  String _query = '';

  /// 부서별로 그룹핑된 직원 목록. 검색어가 있으면 직위(category)·부서(dept)에
  /// 부분일치하는 항목만 남긴다.
  Map<String, List<AdminStaff>> get _groupedFiltered {
    final q = _query.trim();
    final filtered = q.isEmpty
        ? kAdminStaff
        : kAdminStaff.where((s) {
            return s.category.contains(q) || s.dept.contains(q);
          }).toList();

    final grouped = <String, List<AdminStaff>>{};
    for (final s in filtered) {
      grouped.putIfAbsent(s.dept, () => []).add(s);
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
        final grouped = _groupedFiltered;
        final depts = grouped.keys.toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text("교직원 연락처"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: "직위 또는 부서로 검색",
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
              Expanded(
                child: depts.isEmpty
                    ? Center(
                        child: Text(
                          "검색 결과가 없습니다",
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: depts.length,
                        itemBuilder: (context, index) {
                          final dept = depts[index];
                          final members = grouped[dept]!;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Theme(
                              data: Theme.of(context)
                                  .copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                initiallyExpanded: _query.isNotEmpty,
                                title: Text(
                                  dept,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                subtitle: Text("${members.length}명"),
                                children: members
                                    .map((m) => ListTile(
                                          title: Text(m.category),
                                          subtitle: m.duties.isNotEmpty
                                              ? Text(
                                                  m.duties,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                )
                                              : null,
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                m.phone,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: color,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(Icons.call,
                                                  size: 18, color: color),
                                            ],
                                          ),
                                          onTap: () => _call(m.phone),
                                        ))
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
