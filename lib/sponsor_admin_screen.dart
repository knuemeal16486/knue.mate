import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'admin_auth_service.dart';
import 'constants.dart';
import 'sponsor_model.dart';
import 'sponsor_service.dart';

/// 제휴/광고 관리자 화면. 공연·행사 관리와 같은 비밀번호를 쓴다 — 앱에
/// 관리자가 한 사람(팀)뿐이라 화면마다 다른 비밀번호를 만들면 관리만 늘어난다.
/// 통과 후 광고 목록을 조회·추가·수정·삭제하고 활성 여부를 토글할 수 있다.
class SponsorAdminScreen extends StatefulWidget {
  const SponsorAdminScreen({super.key});
  @override
  State<SponsorAdminScreen> createState() => _SponsorAdminScreenState();
}

class _SponsorAdminScreenState extends State<SponsorAdminScreen> {
  /// 이 기기가 이미 관리자면 비밀번호를 다시 묻지 않는다.
  bool _granted = AdminAuthService.isAdmin.value;
  bool _verifying = false;

  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  List<Sponsor> _sponsors = [];
  bool _loadingList = true;

  @override
  void initState() {
    super.initState();
    if (_granted) {
      _loadSponsors();
    } else {
      _recheckGrant();
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  /// 앱이 막 켜졌다면 권한 확인이 아직 안 끝났을 수 있다. 한 번 더 물어보고
  /// 이미 권한이 있으면 비밀번호 없이 통과시킨다.
  Future<void> _recheckGrant() async {
    final ok = await AdminAuthService.refreshAdminStatus();
    if (!mounted || !ok) return;
    setState(() => _granted = true);
    _loadSponsors();
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
    if (result == AdminUnlockResult.ok) {
      _loadSponsors();
    } else if (result == AdminUnlockResult.wrongPassword) {
      _passwordController.clear();
      showToast(context, result.message);
    } else {
      showToast(context, result.message);
    }
  }

  Future<void> _loadSponsors() async {
    if (mounted) setState(() => _loadingList = true);
    try {
      final list = await SponsorService.fetchAll();
      if (!mounted) return;
      setState(() {
        _sponsors = list;
        _loadingList = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _toggleActive(Sponsor sponsor, bool value) async {
    setState(() {
      _sponsors = _sponsors
          .map((s) => s.id == sponsor.id ? s.copyWith(isActive: value) : s)
          .toList();
    });
    try {
      await SponsorService.setActive(sponsor.id, value);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sponsors = _sponsors
            .map((s) => s.id == sponsor.id ? s.copyWith(isActive: !value) : s)
            .toList();
      });
      showToast(context, "변경 실패");
    }
  }

  Future<void> _confirmDelete(Sponsor sponsor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("광고 삭제"),
        content: Text("'${sponsor.title}' 광고를 삭제하시겠습니까?"),
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
    if (confirmed == true) {
      try {
        await SponsorService.delete(sponsor.id);
        if (mounted) showToast(context, "삭제되었습니다");
        await _loadSponsors();
      } catch (e) {
        if (mounted) showToast(context, "삭제 실패");
      }
    }
  }

  Future<void> _openForm({Sponsor? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _SponsorFormPage(existing: existing)),
    );
    if (saved == true) {
      await _loadSponsors();
      if (mounted) showToast(context, "저장되었습니다");
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
            title: const Text("제휴·광고 관리"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (_granted)
                IconButton(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  tooltip: "광고 추가",
                ),
            ],
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
    return _buildList(color, isDark);
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

  Widget _buildList(Color color, bool isDark) {
    if (_loadingList && _sponsors.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sponsors.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadSponsors,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text("등록된 광고가 없습니다")),
            SizedBox(height: 8),
            Center(
              child: Text(
                "오른쪽 위 + 버튼으로 추가하세요",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final dateFmt = DateFormat('yyyy.MM.dd', 'ko_KR');
    return RefreshIndicator(
      onRefresh: _loadSponsors,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _sponsors.length,
        itemBuilder: (context, index) {
          final sponsor = _sponsors[index];
          final live = sponsor.isCurrentlyValid(now);
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
                        sponsor.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Switch(
                      value: sponsor.isActive,
                      activeThumbColor: color,
                      onChanged: (v) => _toggleActive(sponsor, v),
                    ),
                  ],
                ),
                Text(
                  sponsor.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _tag(sponsor.category.label, color, isDark),
                    _tag(sponsor.placement.label, color, isDark),
                    _tag("우선순위 ${sponsor.priority}", color, isDark),
                    _tag(
                      live ? "지금 노출 중" : "비노출",
                      live ? Colors.green : Colors.grey,
                      isDark,
                    ),
                  ],
                ),
                if (sponsor.startDate != null || sponsor.endDate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    "${sponsor.startDate != null ? dateFmt.format(sponsor.startDate!) : '제한 없음'}"
                    " ~ "
                    "${sponsor.endDate != null ? dateFmt.format(sponsor.endDate!) : '제한 없음'}",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openForm(existing: sponsor),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text("수정"),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmDelete(sponsor),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      label: const Text(
                        "삭제",
                        style: TextStyle(color: Colors.red),
                      ),
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

  Widget _tag(String text, Color color, bool isDark) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: isDark ? 0.22 : 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

/// 광고 추가/수정 폼. 관리 목록과 함께 변경되므로 같은 파일에 둔다.
class _SponsorFormPage extends StatefulWidget {
  final Sponsor? existing;
  const _SponsorFormPage({this.existing});

  @override
  State<_SponsorFormPage> createState() => _SponsorFormPageState();
}

class _SponsorFormPageState extends State<_SponsorFormPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _ctaController;
  late final TextEditingController _urlController;

  SponsorCategory _category = SponsorCategory.etc;
  SponsorPlacement _placement = SponsorPlacement.all;
  int _priority = 0;
  bool _isActive = true;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _imageUrl;
  File? _localImage;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _titleController = TextEditingController(text: s?.title ?? '');
    _subtitleController = TextEditingController(text: s?.subtitle ?? '');
    _ctaController = TextEditingController(text: s?.callToAction ?? '자세히 보기');
    _urlController = TextEditingController(text: s?.targetUrl ?? '');
    _category = s?.category ?? SponsorCategory.etc;
    _placement = s?.placement ?? SponsorPlacement.all;
    _priority = s?.priority ?? 0;
    _isActive = s?.isActive ?? true;
    _startDate = s?.startDate;
    _endDate = s?.endDate;
    _imageUrl = s?.imageUrl;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _ctaController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      // 원본 그대로면 5MB 제한(storage.rules)에 걸려 조용히 실패한다.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _localImage = File(picked.path));
      }
    } catch (e) {
      if (mounted) showToast(context, "이미지를 불러올 수 없습니다");
    }
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() => _startDate = date);
  }

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() => _endDate = date);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final subtitle = _subtitleController.text.trim();
    if (title.isEmpty || subtitle.isEmpty) {
      showToast(context, "제목과 설명을 입력하세요");
      return;
    }
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      showToast(context, "종료일이 시작일보다 앞설 수 없습니다");
      return;
    }
    setState(() => _saving = true);
    try {
      var imageUrl = _imageUrl;
      if (_localImage != null) {
        final uploaded = await SponsorService.uploadImage(_localImage!.path);
        if (uploaded != null) {
          imageUrl = uploaded;
        } else if (mounted) {
          showToast(context, "이미지 업로드 실패 (다른 정보는 저장됩니다)");
        }
      }
      final cta = _ctaController.text.trim();
      final url = _urlController.text.trim();
      final sponsor = Sponsor(
        id: widget.existing?.id ?? '',
        title: title,
        subtitle: subtitle,
        callToAction: cta.isEmpty ? '자세히 보기' : cta,
        category: _category,
        imageUrl: imageUrl,
        targetUrl: url.isEmpty ? null : url,
        placement: _placement,
        priority: _priority,
        isActive: _isActive,
        startDate: _startDate,
        endDate: _endDate,
      );
      await SponsorService.upsert(sponsor);
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
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: Text(_isEdit ? "광고 수정" : "광고 추가"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildImagePicker(color, isDark),
                const SizedBox(height: 6),
                Text(
                  "비워두면 아래 카테고리에 맞는 기본 아이콘이 나옵니다",
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: "제목",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subtitleController,
                  decoration: const InputDecoration(
                    labelText: "설명 (한 줄)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctaController,
                  decoration: const InputDecoration(
                    labelText: "버튼 문구",
                    hintText: "자세히 보기",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: "연결 링크 (선택)",
                    hintText: "https://...",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                _buildLabel("카테고리 (아이콘)", isDark),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in SponsorCategory.values)
                      ChoiceChip(
                        avatar: Icon(c.icon, size: 16),
                        label: Text(c.label),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                        selectedColor: color.withValues(
                          alpha: isDark ? 0.32 : 0.18,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: _category == c
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildLabel("노출 탭", isDark),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in SponsorPlacement.values)
                      ChoiceChip(
                        label: Text(p.label),
                        selected: _placement == p,
                        onSelected: (_) => setState(() => _placement = p),
                        selectedColor: color.withValues(
                          alpha: isDark ? 0.32 : 0.18,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: _placement == p
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _buildLabel("우선순위", isDark),
                    const Spacer(),
                    IconButton(
                      onPressed: () => setState(
                        () => _priority = (_priority - 1).clamp(0, 99),
                      ),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$_priority',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(
                        () => _priority = (_priority + 1).clamp(0, 99),
                      ),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Text(
                  "숫자가 클수록 먼저 노출됩니다. 여러 광고가 겹치면 가장 큰 것 하나만 보여요.",
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("활성화"),
                  subtitle: const Text("꺼두면 기간과 상관없이 노출되지 않습니다"),
                  value: _isActive,
                  activeThumbColor: color,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 6),
                _buildDateRow(
                  label: "시작일 (선택)",
                  value: _startDate == null
                      ? "제한 없음"
                      : _formatDate(_startDate!),
                  onTap: _pickStartDate,
                  isDark: isDark,
                  onClear: _startDate == null
                      ? null
                      : () => setState(() => _startDate = null),
                ),
                const SizedBox(height: 12),
                _buildDateRow(
                  label: "종료일 (선택)",
                  value: _endDate == null ? "제한 없음" : _formatDate(_endDate!),
                  onTap: _pickEndDate,
                  isDark: isDark,
                  onClear: _endDate == null
                      ? null
                      : () => setState(() => _endDate = null),
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

  Widget _buildLabel(String text, bool isDark) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white70 : Colors.black54,
    ),
  );

  Widget _buildImagePicker(Color color, bool isDark) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: _buildImagePreview(color),
      ),
    );
  }

  Widget _buildImagePreview(Color color) {
    if (_localImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(_localImage!, fit: BoxFit.cover),
          ),
          _clearImageButton(() => setState(() => _localImage = null)),
        ],
      );
    }
    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              _imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _imagePickerPlaceholder(color),
            ),
          ),
          _clearImageButton(() => setState(() => _imageUrl = null)),
        ],
      );
    }
    return _imagePickerPlaceholder(color);
  }

  Widget _clearImageButton(VoidCallback onTap) => Positioned(
    top: 8,
    right: 8,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 16, color: Colors.white),
      ),
    ),
  );

  Widget _imagePickerPlaceholder(Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, color: color, size: 32),
        const SizedBox(height: 8),
        Text("이미지 선택 (선택)", style: TextStyle(color: color)),
      ],
    );
  }

  Widget _buildDateRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    required bool isDark,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: onClear != null
              ? IconButton(icon: const Icon(Icons.clear), onPressed: onClear)
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      DateFormat('yyyy.MM.dd (E)', 'ko_KR').format(dt);
}
