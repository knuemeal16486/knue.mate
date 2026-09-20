import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'admin_auth_service.dart';
import 'constants.dart';
import 'housing_iso.dart';
import 'housing_model.dart';
import 'housing_service.dart';

/// 자취방 건물·제보 관리자 화면.
///
/// 건물 이름·구역은 학생 제보 다수결로 정해지고, 시세·특징은 학생이 남긴
/// 제보 그대로 집계된다. 잘못된 값이 섞였을 때 학생이 직접 고칠 방법이
/// 없어서, [ClubEventAdminScreen]과 같은 비밀번호로 보호되는 관리 화면을
/// 하나 더 둔다 — "건물 정보"는 다수결을 덮어쓰고, "제보 관리"는 개별
/// 제보를 직접 수정·삭제한다.
class HousingAdminScreen extends StatefulWidget {
  const HousingAdminScreen({super.key});
  @override
  State<HousingAdminScreen> createState() => _HousingAdminScreenState();
}

class _HousingAdminScreenState extends State<HousingAdminScreen>
    with SingleTickerProviderStateMixin {
  /// 이 기기가 이미 관리자면 비밀번호를 다시 묻지 않는다.
  bool _granted = AdminAuthService.isAdmin.value;
  bool _verifying = false;

  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (!_granted) _recheckGrant();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// 앱이 막 켜졌다면 권한 확인이 아직 안 끝났을 수 있다. 한 번 더 물어보고
  /// 이미 권한이 있으면 비밀번호 없이 통과시킨다.
  Future<void> _recheckGrant() async {
    final ok = await AdminAuthService.refreshAdminStatus();
    if (!mounted || !ok) return;
    setState(() => _granted = true);
  }

  /// 비밀번호가 맞는지는 **서버(보안 규칙)가** 판단한다. 앱은 정답을 갖고
  /// 있지 않으므로 쓰기가 받아들여졌는지로만 통과 여부를 안다.
  Future<void> _submitPassword() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    final result = await AdminAuthService.unlock(_passwordController.text);
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _granted = result == AdminUnlockResult.ok;
    });
    if (result == AdminUnlockResult.wrongPassword) {
      _passwordController.clear();
      showToast(context, "비밀번호가 일치하지 않습니다");
    } else if (result == AdminUnlockResult.failed) {
      showToast(context, "확인에 실패했습니다. 연결을 확인해주세요");
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
            title: const Text("자취방 정보 관리"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
            bottom: _granted
                ? TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: const [
                      Tab(text: "건물 정보"),
                      Tab(text: "제보 관리"),
                    ],
                  )
                : null,
          ),
          body: _buildBody(color, isDark),
        );
      },
    );
  }

  Widget _buildBody(Color color, bool isDark) {
    if (!_granted) {
      return _buildPasswordGate(color, isDark);
    }
    return TabBarView(
      controller: _tabController,
      children: [
        _BuildingOverrideTab(color: color, isDark: isDark),
        _ReportManageTab(color: color, isDark: isDark),
      ],
    );
  }

  Widget _buildPasswordGate(Color color, bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined, size: 44, color: color),
            const SizedBox(height: 16),
            const Text(
              "관리자 비밀번호를 입력하세요",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofocus: true,
              onSubmitted: (_) => _submitPassword(),
              decoration: InputDecoration(
                hintText: "비밀번호",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _verifying ? null : _submitPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _verifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("확인"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 탭 1 — 건물 정보 (이름·구역·준공연도를 관리자가 직접 덮어쓴다)
// ═══════════════════════════════════════════════════════════════════════

class _BuildingOverrideTab extends StatefulWidget {
  final Color color;
  final bool isDark;
  const _BuildingOverrideTab({required this.color, required this.isDark});

  @override
  State<_BuildingOverrideTab> createState() => _BuildingOverrideTabState();
}

class _BuildingOverrideTabState extends State<_BuildingOverrideTab> {
  bool _loading = true;
  List<BaseBuilding> _candidates = const [];
  Map<String, HousingSummary> _summaries = const {};
  Map<String, HousingBuildingOverride> _overrides = const {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final base = await CampusBase.load();
    final results = await Future.wait([
      HousingService.fetchSummaries(),
      HousingService.fetchOverrides(),
    ]);
    if (!mounted) return;
    final summaries = results[0] as Map<String, HousingSummary>;
    final overrides = results[1] as Map<String, HousingBuildingOverride>;
    setState(() {
      _summaries = summaries;
      _overrides = overrides;
      _candidates = base.buildings
          .where((b) => looksLikeOneRoom(b, summaries))
          .toList();
      _loading = false;
    });
  }

  OneRoomName? _resolvedKnown(String buildingId) {
    final override = _overrides[buildingId];
    if (override != null) return override.toOneRoomName();
    final oneRoomId = _summaries[buildingId]?.oneRoomId;
    return oneRoomId == null ? null : kOneRoomNameById[oneRoomId];
  }

  List<BaseBuilding> get _filtered {
    if (_query.isEmpty) return _candidates;
    final q = _query.toLowerCase();
    return _candidates.where((b) {
      final known = _resolvedKnown(b.id);
      final name = known?.name ?? b.officialName ?? b.id;
      return name.toLowerCase().contains(q) ||
          b.addressLabel.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openEdit(BaseBuilding b) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _BuildingEditPage(
          building: b,
          current: _resolvedKnown(b.id),
          hasOverride: _overrides.containsKey(b.id),
        ),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = _filtered
      ..sort((a, b) {
        final an = _resolvedKnown(a.id)?.name ?? a.officialName ?? a.id;
        final bn = _resolvedKnown(b.id)?.name ?? b.officialName ?? b.id;
        return an.compareTo(bn);
      });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: "건물 이름·주소 검색",
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: list.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text("해당하는 건물이 없습니다")),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final b = list[i];
                      final known = _resolvedKnown(b.id);
                      final overridden = _overrides.containsKey(b.id);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              (known?.zone.color ?? Colors.grey).withValues(alpha: 0.18),
                          child: Icon(
                            overridden ? Icons.edit_note_rounded : Icons.apartment_rounded,
                            color: known?.zone.color ?? Colors.grey,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          known?.name ?? b.officialName ?? '이름 미확인',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            if (known != null) known.zone.label,
                            b.addressLabel,
                            if (overridden) '관리자 지정됨',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                        onTap: () => _openEdit(b),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _BuildingEditPage extends StatefulWidget {
  final BaseBuilding building;
  final OneRoomName? current;
  final bool hasOverride;

  const _BuildingEditPage({
    required this.building,
    required this.current,
    required this.hasOverride,
  });

  @override
  State<_BuildingEditPage> createState() => _BuildingEditPageState();
}

class _BuildingEditPageState extends State<_BuildingEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _yearController;
  late final TextEditingController _noteController;
  late HousingZone _zone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _nameController = TextEditingController(text: c?.name ?? '');
    _yearController = TextEditingController(text: c?.builtYear?.toString() ?? '');
    _noteController = TextEditingController(text: c?.note ?? '');
    _zone = c?.zone ?? HousingZone.values.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showToast(context, "이름을 입력하세요");
      return;
    }
    setState(() => _saving = true);
    try {
      await HousingService.setOverride(
        HousingBuildingOverride(
          buildingId: widget.building.id,
          name: name,
          zone: _zone,
          builtYear: int.tryParse(_yearController.text.trim()),
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, "저장 실패");
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    try {
      await HousingService.clearOverride(widget.building.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, "초기화 실패");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.building;
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("건물 정보 수정"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (widget.hasOverride)
                IconButton(
                  onPressed: _saving ? null : _clear,
                  icon: const Icon(Icons.restart_alt_rounded),
                  tooltip: "학생 제보 다수결로 되돌리기",
                ),
            ],
          ),
          body: AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  b.addressLabel,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  '지상 ${b.floors}층 · 건물 id ${b.id}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: "원룸 이름",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<HousingZone>(
                  initialValue: _zone,
                  decoration: const InputDecoration(
                    labelText: "구역",
                    border: OutlineInputBorder(),
                  ),
                  items: HousingZone.values
                      .map((z) => DropdownMenuItem(value: z, child: Text(z.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _zone = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _yearController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "건축물 사용승인 연도 (선택)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: "설명 (예: 1층 카페 MAY, 선택)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text("저장"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 탭 2 — 제보 관리 (학생이 남긴 시세·특징 제보를 직접 수정·삭제)
// ═══════════════════════════════════════════════════════════════════════

class _ReportManageTab extends StatefulWidget {
  final Color color;
  final bool isDark;
  const _ReportManageTab({required this.color, required this.isDark});

  @override
  State<_ReportManageTab> createState() => _ReportManageTabState();
}

class _ReportManageTabState extends State<_ReportManageTab> {
  bool _loading = true;
  List<HousingReport> _reports = const [];
  Map<String, HousingBuildingOverride> _overrides = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        HousingService.fetchAllReportsRaw(),
        HousingService.fetchOverrides(),
      ]);
      if (!mounted) return;
      setState(() {
        _reports = results[0] as List<HousingReport>;
        _overrides = results[1] as Map<String, HousingBuildingOverride>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _buildingLabel(HousingReport r) {
    final override = _overrides[r.buildingId];
    if (override != null) return override.name;
    final guessed = r.oneRoomId == null ? null : kOneRoomNameById[r.oneRoomId];
    return guessed?.name ?? r.buildingId;
  }

  Future<void> _confirmDelete(HousingReport r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("제보 삭제"),
        content: Text("'${_buildingLabel(r)}' 제보(보증금 ${r.deposit}/월세 ${r.monthlyRent})를 삭제하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("삭제", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || r.id == null) return;
    try {
      await HousingService.deleteReport(r.id!);
      if (mounted) showToast(context, "삭제되었습니다");
      await _load();
    } catch (e) {
      if (mounted) showToast(context, "삭제 실패");
    }
  }

  Future<void> _openEdit(HousingReport r) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ReportEditPage(report: r)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reports.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text("등록된 제보가 없습니다")),
          ],
        ),
      );
    }
    final dateFmt = DateFormat('yyyy.MM.dd', 'ko_KR');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _reports.length,
        itemBuilder: (context, i) {
          final r = _reports[i];
          return Container(
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
                    Expanded(
                      child: Text(
                        _buildingLabel(r),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Text(
                      dateFmt.format(r.reportedAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '보증금 ${r.deposit}만원 · 월세 ${r.monthlyRent}만원'
                  '${r.maintenanceFee != null ? ' · 관리비 ${r.maintenanceFee}만원' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                if (r.features.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: r.features
                        .map((f) => Chip(
                              label: Text(f, style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide.none,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openEdit(r),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text("수정"),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmDelete(r),
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      label: const Text("삭제", style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReportEditPage extends StatefulWidget {
  final HousingReport report;
  const _ReportEditPage({required this.report});

  @override
  State<_ReportEditPage> createState() => _ReportEditPageState();
}

class _ReportEditPageState extends State<_ReportEditPage> {
  late final TextEditingController _deposit;
  late final TextEditingController _rent;
  late final TextEditingController _fee;
  late final Set<String> _features;
  String? _oneRoomId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.report;
    _deposit = TextEditingController(text: r.deposit.toString());
    _rent = TextEditingController(text: r.monthlyRent.toString());
    _fee = TextEditingController(text: r.maintenanceFee?.toString() ?? '');
    _features = Set.of(r.features);
    _oneRoomId = r.oneRoomId;
  }

  @override
  void dispose() {
    _deposit.dispose();
    _rent.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final deposit = int.tryParse(_deposit.text.trim());
    final rent = int.tryParse(_rent.text.trim());
    if (deposit == null || rent == null) {
      showToast(context, "보증금·월세는 숫자로 입력하세요");
      return;
    }
    setState(() => _saving = true);
    try {
      await HousingService.updateReport(
        id: widget.report.id!,
        deposit: deposit,
        monthlyRent: rent,
        maintenanceFee: int.tryParse(_fee.text.trim()),
        features: _features.toList(),
        oneRoomId: _oneRoomId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, "저장 실패");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("제보 수정"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _oneRoomId,
                  decoration: const InputDecoration(
                    labelText: '원룸 이름 (알고 있다면)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('목록에 없음 / 모름')),
                    ...kOneRoomNames.map((r) => DropdownMenuItem(
                          value: r.id,
                          child: Text('${r.name} (${r.zone.label})'),
                        )),
                  ],
                  onChanged: (v) => setState(() => _oneRoomId = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _deposit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '보증금 (만원)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _rent,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '월세 (만원)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _fee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '관리비 (만원, 선택)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('특징', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kHousingFeatures.map((f) {
                    final selected = _features.contains(f);
                    return FilterChip(
                      label: Text(f, style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _features.add(f);
                          } else {
                            _features.remove(f);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text("저장"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
