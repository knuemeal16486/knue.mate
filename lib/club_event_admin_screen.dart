import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'club_event_model.dart';
import 'club_event_service.dart';
import 'constants.dart';

/// 동아리 행사 관리자 화면. 비밀번호로 보호되며, 통과 후 행사 목록을
/// 조회·추가·수정·삭제하고 녹출(isFeatured) 여부를 토글할 수 있다.
class ClubEventAdminScreen extends StatefulWidget {
  const ClubEventAdminScreen({super.key});
  @override
  State<ClubEventAdminScreen> createState() => _ClubEventAdminScreenState();
}

class _ClubEventAdminScreenState extends State<ClubEventAdminScreen> {
  bool _passwordFetched = false;
  String? _remotePassword;
  bool _granted = false;
  bool _leaveHandled = false;

  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  List<ClubEvent> _events = [];
  bool _loadingList = true;

  @override
  void initState() {
    super.initState();
    _loadAdminPassword();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminPassword() async {
    final pw = await ClubEventService.fetchAdminPassword();
    if (!mounted) return;
    setState(() {
      _remotePassword = pw;
      _passwordFetched = true;
    });
    if (pw == null) {
      _leaveScreen("관리자 설정이 없습니다");
    }
  }

  /// 실패/설정 없음 상황에서 화면을 벗어난다. 테스트 환경처럼 push 없이
  /// 단독 라우트인 경우(canPop == false)에는 안내만 남기고 화면은 유지한다.
  void _leaveScreen(String message) {
    if (_leaveHandled) return;
    _leaveHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showToast(context, message);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  void _submitPassword() {
    if (_passwordController.text == _remotePassword) {
      setState(() => _granted = true);
      _loadEvents();
    } else {
      // 재시도 제한 없음: 화면을 벗어나지 않고 입력만 초기화해 다시 시도할
      // 수 있게 한다. 원격 비밀번호 설정 자체가 없는 경우(_remotePassword
      // == null)는 _loadAdminPassword()에서 별도로 _leaveScreen 처리한다.
      _passwordController.clear();
      showToast(context, "비밀번호가 일치하지 않습니다");
    }
  }

  Future<void> _loadEvents({bool showSavedToast = false}) async {
    if (mounted) setState(() => _loadingList = true);
    try {
      final list = await ClubEventService.fetchAll(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _events = list..sort((a, b) => a.startDate.compareTo(b.startDate));
        _loadingList = false;
      });
      if (showSavedToast && mounted) showToast(context, "저장되었습니다");
    } catch (e) {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _toggleFeatured(ClubEvent event, bool value) async {
    setState(() {
      _events = _events
          .map((e) => e.id == event.id ? _withFeatured(e, value) : e)
          .toList();
    });
    try {
      await ClubEventService.setFeatured(event.id, value);
      // 낙관적으로 갱신된 _events를 캐시에도 반영해 홈 카드/목록(캐시 우선)이
      // 백그라운드 폴링을 기다리지 않고 즉시 변경 사항을 반영하도록 한다.
      await ClubEventCache.save(_events);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _events = _events
            .map((e) => e.id == event.id ? _withFeatured(e, !value) : e)
            .toList();
      });
      showToast(context, "변경 실패");
    }
  }

  ClubEvent _withFeatured(ClubEvent e, bool featured) => ClubEvent(
        id: e.id,
        title: e.title,
        clubName: e.clubName,
        startDate: e.startDate,
        endDate: e.endDate,
        location: e.location,
        description: e.description,
        posterUrl: e.posterUrl,
        externalLink: e.externalLink,
        isFeatured: featured,
        createdAt: e.createdAt,
      );

  Future<void> _confirmDelete(ClubEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("행사 삭제"),
        content: Text("'${event.title}' 행사를 삭제하시겠습니까?"),
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
        await ClubEventService.delete(event.id);
        if (mounted) showToast(context, "삭제되었습니다");
        await _loadEvents();
      } catch (e) {
        if (mounted) showToast(context, "삭제 실패");
      }
    }
  }

  Future<void> _openForm({ClubEvent? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EventFormPage(existing: existing)),
    );
    if (saved == true) {
      await _loadEvents(showSavedToast: true);
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
            title: const Text("동아리 행사 관리"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (_granted)
                IconButton(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  tooltip: "행사 추가",
                ),
            ],
          ),
          body: _buildBody(color, isDark),
        );
      },
    );
  }

  Widget _buildBody(Color color, bool isDark) {
    if (!_passwordFetched) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_remotePassword == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 40, color: isDark ? Colors.white38 : Colors.black38),
              const SizedBox(height: 12),
              const Text("관리자 설정이 없습니다"),
            ],
          ),
        ),
      );
    }
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
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text("확인"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(Color color, bool isDark) {
    if (_loadingList && _events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadEvents(),
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text("등록된 행사가 없습니다")),
          ],
        ),
      );
    }
    final dateFmt = DateFormat('M월 d일 HH:mm', 'ko_KR');
    return RefreshIndicator(
      onRefresh: () => _loadEvents(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
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
                        event.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Switch(
                      value: event.isFeatured,
                      activeThumbColor: color,
                      onChanged: (v) => _toggleFeatured(event, v),
                    ),
                  ],
                ),
                Text(
                  event.clubName,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateFmt.format(event.startDate),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openForm(existing: event),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text("수정"),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmDelete(event),
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      label: const Text("삭제",
                          style: TextStyle(color: Colors.red)),
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

/// 행사 추가/수정 폼. 관리 목록과 함께 변경되므로 같은 파일에 둔다.
class _EventFormPage extends StatefulWidget {
  final ClubEvent? existing;
  const _EventFormPage({this.existing});

  @override
  State<_EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<_EventFormPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _clubNameController;
  late final TextEditingController _locationController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _linkController;

  late DateTime _startDate;
  DateTime? _endDate;
  String? _posterUrl;
  File? _localPoster;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? '');
    _clubNameController = TextEditingController(text: e?.clubName ?? '');
    _locationController = TextEditingController(text: e?.location ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _linkController = TextEditingController(text: e?.externalLink ?? '');
    _startDate = e?.startDate ?? DateTime.now();
    _endDate = e?.endDate;
    _posterUrl = e?.posterUrl;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _clubNameController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _pickPoster() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() => _localPoster = File(picked.path));
      }
    } catch (e) {
      if (mounted) showToast(context, "이미지를 불러올 수 없습니다");
    }
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startDate),
    );
    setState(() {
      _startDate = DateTime(date.year, date.month, date.day,
          time?.hour ?? _startDate.hour, time?.minute ?? _startDate.minute);
    });
  }

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endDate ?? _startDate),
    );
    setState(() {
      _endDate = DateTime(date.year, date.month, date.day, time?.hour ?? 0,
          time?.minute ?? 0);
    });
  }

  Future<void> _save(Color color) async {
    final title = _titleController.text.trim();
    final clubName = _clubNameController.text.trim();
    if (title.isEmpty || clubName.isEmpty) {
      showToast(context, "제목과 동아리명을 입력하세요");
      return;
    }
    setState(() => _saving = true);
    try {
      var posterUrl = _posterUrl;
      if (_localPoster != null) {
        final uploaded = await ClubEventService.uploadPoster(_localPoster!.path);
        if (uploaded != null) {
          posterUrl = uploaded;
        } else if (mounted) {
          showToast(context, "포스터 업로드 실패 (다른 정보는 저장됩니다)");
        }
      }
      final event = ClubEvent(
        id: widget.existing?.id ?? '',
        title: title,
        clubName: clubName,
        startDate: _startDate,
        endDate: _endDate,
        location: _locationController.text.trim(),
        description: _descriptionController.text.trim(),
        posterUrl: posterUrl,
        externalLink: _linkController.text.trim().isEmpty
            ? null
            : _linkController.text.trim(),
        isFeatured: widget.existing?.isFeatured ?? false,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );
      await ClubEventService.upsert(event);
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
            title: Text(_isEdit ? "행사 수정" : "행사 추가"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPosterPicker(color, isDark),
                const SizedBox(height: 20),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                      labelText: "제목", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clubNameController,
                  decoration: const InputDecoration(
                      labelText: "동아리명", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                _buildDateRow(
                  label: "시작일시",
                  value: _formatDateTime(_startDate),
                  onTap: _pickStartDate,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildDateRow(
                  label: "종료일시 (선택)",
                  value: _endDate == null ? "설정 안 함" : _formatDateTime(_endDate!),
                  onTap: _pickEndDate,
                  isDark: isDark,
                  onClear: _endDate == null
                      ? null
                      : () => setState(() => _endDate = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                      labelText: "장소", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: "설명", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _linkController,
                  decoration: const InputDecoration(
                      labelText: "외부 링크 (선택)", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _save(color),
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
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
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

  Widget _buildPosterPicker(Color color, bool isDark) {
    return GestureDetector(
      onTap: _pickPoster,
      child: Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: _buildPosterPreview(color),
      ),
    );
  }

  Widget _buildPosterPreview(Color color) {
    if (_localPoster != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(_localPoster!, fit: BoxFit.cover),
      );
    }
    if (_posterUrl != null && _posterUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          _posterUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _posterPickerPlaceholder(color),
        ),
      );
    }
    return _posterPickerPlaceholder(color);
  }

  Widget _posterPickerPlaceholder(Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, color: color, size: 32),
        const SizedBox(height: 8),
        Text("포스터 선택", style: TextStyle(color: color)),
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

  String _formatDateTime(DateTime dt) =>
      DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(dt);
}
