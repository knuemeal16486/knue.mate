import re

with open(r"c:\Users\user\knue.mate\lib\campus_map_screen.dart", "r", encoding="utf-8") as f:
    code = f.read()

# 1. State variables
code = code.replace(
    'List<String> _favoriteDepts = [];',
    'List<String> _favoriteDepts = [];\n  List<String> _favoriteAdmins = [];\n  String adminSearchQuery = \'\';'
)

# 2. _tabController
code = code.replace('TabController(length: 5, vsync: this)', 'TabController(length: 6, vsync: this)')

# 3. _loadFavorites / _saveFavorites
code = code.replace("if (f != null) _favoriteDepts = f;", "if (f != null) _favoriteDepts = f;\n    final fa = prefs.getStringList('knue_fav_admins');\n    if (fa != null) _favoriteAdmins = fa;")
code = code.replace("await prefs.setStringList('knue_fav_depts', _favoriteDepts);", "await prefs.setStringList('knue_fav_depts', _favoriteDepts);\n    await prefs.setStringList('knue_fav_admins', _favoriteAdmins);")

# 4. TabBarView
old_tabbarview = """              TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMapTab(primary, isDark),
                  _buildBuildingTab(primary, isDark),
                  _buildTrailTab(primary, isDark),
                  _buildDeptOfficeTab(isDark),
                  _buildAdminOfficeTab(isDark),
                ],
              )"""
new_tabbarview = """              TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMapTab(primary, isDark),
                  _buildBuildingTab(primary, isDark),
                  _buildFacilityTab(primary, isDark),
                  _buildTrailTab(primary, isDark),
                  _buildDeptOfficeTab(isDark),
                  _buildAdminOfficeTab(isDark),
                ],
              )"""
code = code.replace(old_tabbarview, new_tabbarview)

# 5. TabBar
old_tabs = """                  tabs: const [
                    Tab(text: '지도', height: 32),
                    Tab(text: '건물', height: 32),
                    Tab(text: '산책로', height: 32),
                    Tab(text: '과 사무실', height: 32),
                    Tab(text: '행정 부서', height: 32),
                  ],"""
new_tabs = """                  tabs: const [
                    Tab(text: '지도', height: 32),
                    Tab(text: '건물', height: 32),
                    Tab(text: '부속시설', height: 32),
                    Tab(text: '산책로', height: 32),
                    Tab(text: '과 사무실', height: 32),
                    Tab(text: '행정 부서', height: 32),
                  ],"""
code = code.replace(old_tabs, new_tabs)

# 6. delay in startListener
code = code.replace('ReorderableDelayedDragStartListener', '_CustomReorderableDragStartListener')

# 7. padding replacement height: 114 -> MediaQuery...
code = code.replace('SizedBox(height: 114)', 'SizedBox(height: MediaQuery.of(context).padding.top + 96)')

# 8. buildAdminOfficeTab replacement
old_admin = '''  Widget _buildAdminOfficeTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24, left: 16, right: 16),
      itemCount: kAdminOffices.length,
      itemBuilder: (ctx, idx) {
        final d = kAdminOffices[idx];
        final color = themeColor.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Icons.business_center_rounded,
                  color: color,
                  size: 20,
                ),
              ),
            ),
            title: Text(
              d.dept,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              '${d.building} ${d.room}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: d.phone.split(',').map((p) {
                final phoneNum = p.trim();
                return GestureDetector(
                  onTap: () async {
                    final uri = Uri.parse('tel:$phoneNum');
                    if (await canLaunchUrl(uri)) launchUrl(uri);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call_rounded, size: 13, color: color),
                        const SizedBox(height: 2),
                        Text(
                          phoneNum.replaceFirst('043-', ''),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }'''

new_admin = '''  Widget _buildAdminOfficeTab(bool isDark) {
    final primary = themeColor.value;
    return StatefulBuilder(
      builder: (ctx, setLocalState) {
        final query = adminSearchQuery.trim();
        List<Widget> tabItems = [];

        tabItems.add(SizedBox(height: MediaQuery.of(context).padding.top + 96));
        tabItems.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: isDark ? Colors.white38 : Colors.black38,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (v) {
                        setLocalState(() => adminSearchQuery = v);
                      },
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: '행정 부서 이름 검색',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setLocalState(() => adminSearchQuery = '');
                      },
                      child: Icon(
                        Icons.cancel_rounded,
                        color: isDark ? Colors.white38 : Colors.black38,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        Widget buildAdminItem(DeptOffice d) {
          final isFav = _favoriteAdmins.contains(d.dept);
          final color = primary;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              leading: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isFav) {
                      _favoriteAdmins.remove(d.dept);
                    } else {
                      if (_favoriteAdmins.length >= 5) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('관심 부서는 최대 5개까지 가능합니다.')));
                      } else {
                        _favoriteAdmins.add(d.dept);
                      }
                    }
                    _saveFavoritesAndCategories();
                  });
                  setLocalState(() {});
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(
                      isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFav ? Colors.amber : color,
                      size: 20,
                    ),
                  ),
                ),
              ),
              title: Text(d.dept, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text('${d.building} ${d.room}', style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w500)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: d.phone.split(',').map((p) {
                  final phoneNum = p.trim();
                  return GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse('tel:$phoneNum');
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.call_rounded, size: 13, color: color),
                          const SizedBox(height: 2),
                          Text(phoneNum.replaceFirst('043-', ''), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }

        if (query.isEmpty && _favoriteAdmins.isNotEmpty) {
          final favs = kAdminOffices.where((d) => _favoriteAdmins.contains(d.dept)).toList();
          if (favs.isNotEmpty) {
            tabItems.add(
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8, left: 16, right: 16),
                child: Row(
                  children: [
                    Container(width: 28, height: 28, decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.star_rounded, size: 15, color: Colors.amber)),
                    const SizedBox(width: 8),
                    Text('나의 관심 부서', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
                  ],
                ),
              ),
            );
            tabItems.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: favs.map((d) => buildAdminItem(d)).toList())));
          }
        }

        final admins = kAdminOffices.where((d) {
          if (query.isEmpty) return true;
          return d.dept.contains(query) || d.building.contains(query);
        }).toList();

        if (admins.isNotEmpty) {
          tabItems.add(
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8, left: 16, right: 16),
              child: Row(
                children: [
                  Container(width: 28, height: 28, decoration: BoxDecoration(color: primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.business_center_rounded, size: 15, color: primary)),
                  const SizedBox(width: 8),
                  Text('행정 부서 목록', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(width: 6),
                  Text('${admins.length}개 부서', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                ],
              ),
            ),
          );
          tabItems.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: admins.map((d) => buildAdminItem(d)).toList())));
        }

        return ListView(padding: const EdgeInsets.only(bottom: 24), children: tabItems);
      },
    );
  }'''
code = code.replace(old_admin, new_admin)

# 9. Modify delay to 300 for Image Sharing
code = code.replace("Future.delayed(const Duration(milliseconds: 1000))", "Future.delayed(const Duration(milliseconds: 300))")

# 10. Remove creation text string
code = code.replace("""          Text(
            '산책로가 전체 다 보이는 1:1 이미지를 생성합니다...',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(height: 16),""", "const SizedBox(height: 16),")

facility_tab = '''
  // ─── 부속시설 탭 ───
  Widget _buildFacilityTab(Color primary, bool isDark) {
    final orderedFacilities = _facilityOrder
        .map((i) => (i, kFacilities[i]))
        .toList();
    final visibleFacilities = orderedFacilities
        .where((e) => !_hiddenFacilityIdx.contains(e.$1))
        .toList();
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 96),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                '부속시설 목록',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              if (_hiddenFacilityIdx.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _hiddenFacilityIdx.clear()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '숨김 ${_hiddenFacilityIdx.length}개 해제',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showFacilityReorderSheet(isDark, primary),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit_rounded, size: 12, color: primary),
                      const SizedBox(width: 4),
                      Text(
                        '편집',
                        style: TextStyle(
                          fontSize: 11,
                          color: primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: visibleFacilities.length,
            itemBuilder: (ctx, i) {
              final idx = visibleFacilities[i].$1;
              final f = visibleFacilities[i].$2;
              final displayedName = _customFacilityNames[idx] ?? f.name;
              final isCustom = _customFacilityNames.containsKey(idx);

              return GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() {
                    _searchOpen = false;
                    _searchQuery = '';
                  });
                  _tabController.animateTo(0);
                  Future.delayed(
                    const Duration(milliseconds: 200),
                    () => _animatedMove(f.position, 18.5),
                  );
                  _showFacilityDetail(f);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: f.type.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(f.type.icon, color: f.type.color, size: 20)
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayedName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  if (isCustom)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.edit_note_rounded,
                                        size: 14,
                                        color: primary,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                f.type.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark ? Colors.white38 : Colors.black26,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
'''
if "_buildFacilityTab" not in code:
    code = code.replace("Widget _buildBuildingTab(Color primary, bool isDark) {", facility_tab + "\n  Widget _buildBuildingTab(Color primary, bool isDark) {")


reorder_sheet = '''
  void _showFacilityReorderSheet(bool isDark, Color primary) {
    final tempOrder = List<int>.from(_facilityOrder);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: BoxDecoration(color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: [
                    Container(width: 3, height: 16, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text('부속시설 편집', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87)),
                    const Spacer(),
                    TextButton(onPressed: () => setLocalState(() => tempOrder.setAll(0, List.generate(kFacilities.length, (i) => i))), child: Text('초기화', style: TextStyle(color: primary, fontWeight: FontWeight.w600))),
                    TextButton(onPressed: () { setState(() => _facilityOrder = List.from(tempOrder)); _saveFavoritesAndCategories(); Navigator.pop(ctx); }, child: Text('완료', style: TextStyle(color: primary, fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: tempOrder.length,
                  onReorder: (o, n) { setLocalState(() { if (n > o) n--; final t = tempOrder.removeAt(o); tempOrder.insert(n, t); }); },
                  itemBuilder: (_, i) {
                    final idx = tempOrder[i];
                    final f = kFacilities[idx];
                    final displayedName = _customFacilityNames[idx] ?? f.name;
                    return ListTile(
                      key: ValueKey(idx),
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: f.type.color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(f.type.icon, color: Colors.white, size: 17),
                      ),
                      title: Text(displayedName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                      subtitle: Text(f.type.label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(_hiddenFacilityIdx.contains(idx) ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: _hiddenFacilityIdx.contains(idx) ? Colors.redAccent : (isDark ? Colors.white54 : Colors.black54), size: 20),
                            onPressed: () {
                              setLocalState(() { setState(() { if (_hiddenFacilityIdx.contains(idx)) _hiddenFacilityIdx.remove(idx); else _hiddenFacilityIdx.add(idx); }); });
                            },
                          ),
                          Icon(Icons.drag_handle_rounded, color: isDark ? Colors.white38 : Colors.black26),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
'''
if "_showFacilityReorderSheet" not in code:
    code = code.replace("void _showReorderSheet(bool isDark, Color primary) {", reorder_sheet + "\n  void _showReorderSheet(bool isDark, Color primary) {")


custom_listener = '''
class _CustomReorderableDragStartListener extends ReorderableDragStartListener {
  final Duration delay;
  const _CustomReorderableDragStartListener({
    super.key,
    required super.child,
    required super.index,
    super.enabled,
    this.delay = const Duration(milliseconds: 700),
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(delay: delay, debugOwner: this);
  }
}
'''
if "_CustomReorderableDragStartListener" not in code:
    code = code.replace("class _SearchItem {", custom_listener + "\nclass _SearchItem {")
    code = "import 'package:flutter/gestures.dart';\n" + code

with open(r"c:\Users\user\knue.mate\lib\campus_map_screen.dart", "w", encoding="utf-8") as f:
    f.write(code)
