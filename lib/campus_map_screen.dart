import 'dart:async';
import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'building_data.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screenshot/screenshot.dart';
import 'constants.dart';
import 'admin_staff_data.dart';
import 'club_event_service.dart' show ClubEventService;
import 'map_facility_service.dart';
import 'staff_contacts_screen.dart';
import 'ui_utils.dart';

// ─────────────────────────────────────────────────── 데이터 모델 ──

enum FacilityType {
  restaurant,
  cafe,
  convenience,
  bus_stop,
  pc,
  pub,
  atm,
  printer,
  laundry,
  bookstore,
  bank,
  post,
  gym,
  ev,
  parking,
  stage,
  toilet,
  department,
  observatory,
}

extension FacilityTypeExt on FacilityType {
  IconData get icon => switch (this) {
    FacilityType.printer => Icons.print_rounded,
    FacilityType.cafe => Icons.coffee_rounded,
    FacilityType.ev => Icons.ev_station_rounded,
    FacilityType.stage => Icons.theater_comedy_rounded,
    FacilityType.toilet => Icons.wc_rounded,
    FacilityType.convenience => Icons.store_rounded,
    FacilityType.parking => Icons.local_parking_rounded,
    FacilityType.atm => Icons.atm_rounded,
    FacilityType.restaurant => Icons.restaurant_rounded,
    FacilityType.department => Icons.business_center_rounded,
    FacilityType.gym => Icons.fitness_center_rounded,
    FacilityType.bank => Icons.account_balance_rounded,
    FacilityType.post => Icons.mail_rounded,
    FacilityType.bookstore => Icons.menu_book_rounded,
    FacilityType.bus_stop => Icons.directions_bus_rounded,
    FacilityType.pub => Icons.local_bar_rounded,
    FacilityType.pc => Icons.sports_esports_rounded,
    FacilityType.laundry => Icons.local_laundry_service_rounded,
    FacilityType.observatory => Icons.satellite_alt_rounded,
  };

  Color get color => switch (this) {
    FacilityType.printer => const Color(0xFF3949AB),
    FacilityType.cafe => const Color(0xFF6D4C41),
    FacilityType.ev => const Color(0xFF2E7D32),
    FacilityType.stage => const Color(0xFFE64A19),
    FacilityType.toilet => const Color(0xFF00838F),
    FacilityType.convenience => const Color(0xFFC62828),
    FacilityType.parking => const Color(0xFF455A64),
    FacilityType.atm => const Color(0xFF1565C0),
    FacilityType.restaurant => const Color(0xFFF57F17),
    FacilityType.department => const Color(0xFF6A1B9A),
    FacilityType.gym => const Color(0xFFBF360C),
    FacilityType.bank => const Color(0xFF1B5E20),
    FacilityType.post => const Color(0xFFE65100),
    FacilityType.bookstore => const Color(0xFF4A148C),
    FacilityType.bus_stop => const Color(0xFF00ACC1),
    FacilityType.pub => const Color(0xFF8E24AA),
    FacilityType.pc => const Color(0xFF1E88E5),
    FacilityType.laundry => const Color(0xFF00897B),
    FacilityType.observatory => const Color(0xFF5E35B1),
  };

  String get label => switch (this) {
    FacilityType.restaurant => '식당',
    FacilityType.cafe => '카페',
    FacilityType.convenience => '편의점',
    FacilityType.bus_stop => '정류장',
    FacilityType.pc => 'PC방',
    FacilityType.pub => '주점',
    FacilityType.atm => 'ATM',
    FacilityType.printer => '프린터',
    FacilityType.laundry => '빨래방',
    FacilityType.bookstore => '서점',
    FacilityType.bank => '은행',
    FacilityType.post => '우체국',
    FacilityType.gym => '체육관',
    FacilityType.ev => '전기차충전',
    FacilityType.parking => '주차장',
    FacilityType.stage => '공연장',
    FacilityType.toilet => '화장실',
    FacilityType.department => '과사무실',
    FacilityType.observatory => '관측소',
  };

  double get minZoom => switch (this) {
    FacilityType.restaurant ||
    FacilityType.bus_stop ||
    FacilityType.observatory ||
    FacilityType.parking => 15.5,
    FacilityType.cafe ||
    FacilityType.convenience ||
    FacilityType.atm ||
    FacilityType.stage ||
    FacilityType.bank ||
    FacilityType.post ||
    FacilityType.pub ||
    FacilityType.pc ||
    FacilityType.laundry ||
    FacilityType.bookstore => 16.0,
    FacilityType.printer || FacilityType.ev => 16.5,
    FacilityType.toilet ||
    FacilityType.gym ||
    FacilityType.department => 17.0, // Added missing ones gracefully.
  };

  String get category => switch (this) {
    FacilityType.cafe ||
    FacilityType.convenience ||
    FacilityType.restaurant ||
    FacilityType.atm ||
    FacilityType.bank ||
    FacilityType.post ||
    FacilityType.pub ||
    FacilityType.pc ||
    FacilityType.laundry ||
    FacilityType.bookstore => '편의',
    FacilityType.bus_stop || FacilityType.ev || FacilityType.parking => '이동',
    FacilityType.printer ||
    FacilityType.gym ||
    FacilityType.department ||
    FacilityType.observatory => '교육',
    FacilityType.stage || FacilityType.toilet => '시설',
  };
}

class MapFacility {
  final String name;
  final FacilityType type;
  final LatLng position;
  final String? detail;

  /// null이 아니면 개발자 모드로 추가된 위치([AdminMapFacility]의 Firestore
  /// 문서 id) — 코드에 박힌 [kFacilities]와 구분해 삭제 버튼을 보여줄 때 쓴다.
  final String? adminId;
  const MapFacility({
    required this.name,
    required this.type,
    required this.position,
    this.detail,
    this.adminId,
  });
}

// BuildingData and FloorData removed. Imported from building_data.dart.

// ─────────────────────────────────────────────────── 정적 데이터 ──

const LatLng _knueCenter = LatLng(36.6093, 127.3585);
const String _trailsKey = 'campus_trails_v2';

// ─────────────────────── 과 사무실 모델 ──



// 행정직원 데이터는 admin_staff_data.dart에서 불러온 kAdminStaff 리스트를 사용합니다.

// Building data is now loaded dynamically from assets.

final List<MapFacility> kFacilities = [
  // 사용자 제공 실제 좌표
  const MapFacility(
    name: '연수원 공감 ',
    type: FacilityType.cafe,
    position: LatLng(36.613702, 127.356901),
    detail: '09:00~18:00',
  ),
  const MapFacility(
    name: '도서관 공감',
    type: FacilityType.cafe,
    position: LatLng(36.609039, 127.358218),
    detail: '08:00~20:00',
  ),
  const MapFacility(
    name: '브리드 커피',
    type: FacilityType.cafe,
    position: LatLng(36.6083883, 127.3600495),
    detail: '09:00~18:00',
  ),
  const MapFacility(
    name: 'CU 학생회관',
    type: FacilityType.convenience,
    position: LatLng(36.6084443, 127.3595452),
    detail: '24시간 무인',
  ),
  const MapFacility(
    name: 'CU 다정관',
    type: FacilityType.convenience,
    position: LatLng(36.613345, 127.359776),
    detail: '24시간 무인',
  ),
  const MapFacility(
    name: '교원대 우체국',
    type: FacilityType.post,
    position: LatLng(36.6084174, 127.3594701),
    detail: '09:00~18:00 (주말 휴무)',
  ),
  const MapFacility(
    name: '학생회관 식당',
    type: FacilityType.restaurant,
    position: LatLng(36.6082839, 127.3597920),
    detail: '11:00~14:00 / 17:00~19:00',
  ),
  const MapFacility(
    name: '교내 서점',
    type: FacilityType.bookstore,
    position: LatLng(36.6083582, 127.3595345),
    detail: '09:00~18:00 (주말 휴무)',
  ),
  const MapFacility(
    name: '기숙사 식당',
    type: FacilityType.restaurant,
    position: LatLng(36.612830, 127.360559),
    detail: '07:00~19:00',
  ),
  const MapFacility(
    name: '농협은행 교원대출장소',
    type: FacilityType.bank,
    position: LatLng(36.6084551, 127.3569837),
    detail: '09:00~16:00 (주말 휴무)',
  ),
  const MapFacility(
    name: 'CU 뉴교원대원룸점',
    type: FacilityType.convenience,
    position: LatLng(36.609641, 127.355747),
    detail: '24시간',
  ),
  const MapFacility(
    name: 'CU 한국교원대점',
    type: FacilityType.convenience,
    position: LatLng(36.6071352, 127.3536792),
    detail: '24시간',
  ),
  const MapFacility(
    name: '셀프빨래방',
    type: FacilityType.laundry,
    position: LatLng(36.6093335, 127.3556359),
    detail: '24시간 무인',
  ),
  const MapFacility(
    name: '카페 시즌',
    type: FacilityType.cafe,
    position: LatLng(36.608337, 127.355796),
  ),
  const MapFacility(
    name: '카페 MAY 49-10',
    type: FacilityType.cafe,
    position: LatLng(36.608294, 127.355404),
  ),
  const MapFacility(
    name: '카페 에브리앙',
    type: FacilityType.cafe,
    position: LatLng(36.605542, 127.353762),
  ),
  const MapFacility(
    name: '카페 아도르',
    type: FacilityType.cafe,
    position: LatLng(36.611532, 127.349267),
  ),
  const MapFacility(
    name: '카페 36.5 공감',
    type: FacilityType.cafe,
    position: LatLng(36.617870, 127.356246),
  ),
  const MapFacility(
    name: '디저트 39 한국교원대점',
    type: FacilityType.cafe,
    position: LatLng(36.617172, 127.356144),
  ),
  const MapFacility(
    name: '카페 도란',
    type: FacilityType.cafe,
    position: LatLng(36.616630, 127.356241),
  ),
  const MapFacility(
    name: '카페 에셀',
    type: FacilityType.cafe,
    position: LatLng(36.616565, 127.360463),
  ),
  const MapFacility(
    name: '카페 우즈',
    type: FacilityType.cafe,
    position: LatLng(36.612996, 127.361487),
  ),
  const MapFacility(
    name: '카페 마레',
    type: FacilityType.cafe,
    position: LatLng(36.613771, 127.360892),
  ),
  const MapFacility(
    name: '카페 더 다락',
    type: FacilityType.cafe,
    position: LatLng(36.60099, 127.36287),
  ),
  const MapFacility(
    name: '한국교원대 버스정류장',
    type: FacilityType.bus_stop,
    position: LatLng(36.6084066, 127.3584965),
  ),
  const MapFacility(
    name: '한국교원대 정문 버스정류장',
    type: FacilityType.bus_stop,
    position: LatLng(36.607025, 127.353601),
  ),
  const MapFacility(
    name: '한국교원대 후문 버스정류장',
    type: FacilityType.bus_stop,
    position: LatLng(36.617752, 127.355930),
  ),
  const MapFacility(
    name: '탑연삼거리 버스정류장 (조치원 방면)',
    type: FacilityType.bus_stop,
    position: LatLng(36.623738, 127.359626),
  ),
  const MapFacility(
    name: '탑연삼거리 버스정류장 (청주 방면)',
    type: FacilityType.bus_stop,
    position: LatLng(36.623777, 127.358091),
  ),
  const MapFacility(
    name: '지진파 관측소',
    type: FacilityType.observatory,
    position: LatLng(36.613258, 127.358067),
  ),
  const MapFacility(
    name: '청람 천문대',
    type: FacilityType.observatory,
    position: LatLng(36.606748, 127.360119),
  ),
  const MapFacility(
    name: 'B&W',
    type: FacilityType.pub,
    position: LatLng(36.614150, 127.360720),
  ),
  const MapFacility(
    name: 'BLUR',
    type: FacilityType.pub,
    position: LatLng(36.6071406, 127.3541862),
  ),
  const MapFacility(
    name: '완행열차',
    type: FacilityType.pub,
    position: LatLng(36.607760, 127.353119),
  ),
  const MapFacility(
    name: 'POW PC방',
    type: FacilityType.pc,
    position: LatLng(36.6053847, 127.3539890),
  ),
  const MapFacility(
    name: 'PLAN D',
    type: FacilityType.pub,
    position: LatLng(36.6073462, 127.3536216),
  ),
  const MapFacility(
    name: '땡금이네 실내포차',
    type: FacilityType.pub,
    position: LatLng(36.6097232, 127.3559940),
  ),
];
// ─────────────────────────────────────────────────── 메인 위젯 ──

class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key});
  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final TabController _tabController;

  final Set<FacilityType> _activeFilters = {
    FacilityType.cafe,
    FacilityType.restaurant,
    FacilityType.convenience,
    FacilityType.atm,
    FacilityType.bank,
    FacilityType.post,
    FacilityType.bookstore,
    FacilityType.bus_stop,
    FacilityType.pub,
    FacilityType.pc,
    FacilityType.laundry,
    FacilityType.observatory,
  };

  bool _trailMode = false;
  bool _showBuildings = true;
  bool _searchOpen = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final List<LatLng> _trailPoints = [];
  List<List<LatLng>> _savedTrails = [];
  int? _selectedTrailIdx;
  List<String> _trailNames = [];

  // 건물/시설/카테고리 순서 상태 (null이면 기본 순서)
  List<int> _buildingOrder = [];
  List<int> _facilityOrder = [];
  List<String> _categoryOrder = ['교육', '편의', '이동', '시설'];

  // 숨김 목록
  final Set<int> _hiddenBuildingIdx = {};
  final Set<int> _hiddenFacilityIdx = {};

  // ── 개발자 모드: 지도에 위치 찍기/삭제 (Firestore, 전체 사용자 공유) ──
  bool _devMode = false;
  List<AdminMapFacility> _adminFacilities = [];

  // 날씨
  String? _weatherTemp;
  String? _weatherIcon;
  double _currentZoom = 16.0;

  // Custom Names & Favorites
  Map<int, String> _customBuildingNames = {};
  Map<int, String> _customFacilityNames = {};

  // 위치 관련
  Position? _userPosition;
  StreamSubscription<Position>? _locSub;
  AnimationController? _zoomAnim;
  bool _locationPermGranted = false; // ignore: unused_field

  // 탭 7개(지도·건물·부속시설·산책로·과사무실·행정·강의실)를 3그룹으로 접었다.
  // 기능은 그대로 두고 "들어가는 문"만 줄인 것 — 각 그룹 안에서 세그먼트로 나눈다.
  //   0 지도 / 1 장소(건물·부속시설·강의실) / 2 연락처(과 사무실·행정)
  int _placeSegment = 0; // 0 건물, 1 부속시설, 2 강의실

  /// 첫 진입 1회 기능 안내 시트를 이미 봤는지. (발견성 문제 보완)
  static const String _kGuideSeenKey = 'campus_map_guide_seen_v1';

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _tabController = TabController(length: 2, vsync: this);

    // 학생들이 많이 이용하는 건물 우선 배치 (학부생 위주 정렬) - 실제 존재하는 인덱스만 필터링
    final pop = [
      18,
      21,
      22,
      7,
      9,
      8,
      12,
      13,
      14,
      16,
      17,
      15,
      5,
      6,
      10,
      11,
      0,
      4,
      19,
      20,
    ].where((idx) => idx < kBuildings.length).toList();

    final rest = List.generate(
      kBuildings.length,
      (i) => i,
    ).where((i) => !pop.contains(i)).toList();
    _buildingOrder = pop + rest;

    _facilityOrder = List.generate(kFacilities.length, (i) => i);
    _loadCustomNames();
    _loadTrails();
    _loadFavoritesAndCategories();
    _startLocationTracking();
    _fetchWeather();
    _loadAdminFacilities();
    // 첫 프레임 뒤에 안내 — 기능이 7개 탭에 흩어져 있어 아무도 모른다는 문제 보완.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeShowFirstRunGuide(
        themeColor.value,
        Theme.of(context).brightness == Brightness.dark,
      );
    });
    // 백그라운드 Firebase 건물 동기화가 화면이 열려있는 동안 끝나도 반영되도록 구독.
    kBuildingsRevision.addListener(_onBuildingsUpdated);
  }

  void _onBuildingsUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAdminFacilities() async {
    final list = await MapFacilityService.fetchAll();
    if (mounted) setState(() => _adminFacilities = list);
  }

  FacilityType _facilityTypeFromKey(String key) {
    for (final t in FacilityType.values) {
      if (t.name == key) return t;
    }
    return FacilityType.department;
  }

  /// 개발자 모드 켜기. club_events·자취방 관리 화면과 같은 공유 비밀번호로
  /// 잠근다 — 화면을 옮기지 않고 이 화면 안에서 바로 지도를 길게 눌러
  /// 찍을 수 있어야 하므로, 별도 관리 화면 대신 비밀번호만 여기서 확인한다.
  Future<void> _toggleDevMode(bool isDark) async {
    if (_devMode) {
      setState(() => _devMode = false);
      return;
    }
    final password = await ClubEventService.fetchAdminPassword();
    if (!mounted) return;
    if (password == null) {
      showToast(context, "관리자 설정이 없습니다");
      return;
    }
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("개발자 모드"),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: "비밀번호"),
          onSubmitted: (_) => Navigator.pop(dialogContext, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("확인"),
          ),
        ],
      ),
    );
    final matched = ok == true && controller.text == password;
    controller.dispose();
    if (!mounted) return;
    if (matched) {
      setState(() => _devMode = true);
      showToast(context, "개발자 모드 켜짐 — 지도를 길게 눌러 위치를 추가하세요");
    } else if (ok == true) {
      showToast(context, "비밀번호가 일치하지 않습니다");
    }
  }

  /// 지도를 길게 눌렀을 때 새 위치를 등록하는 폼.
  Future<void> _showAddFacilityDialog(LatLng point, bool isDark) async {
    final nameCtrl = TextEditingController();
    final detailCtrl = TextEditingController();
    FacilityType selected = FacilityType.restaurant;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("새 위치 추가"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: "이름"),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<FacilityType>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: "종류"),
                  isExpanded: true,
                  items: FacilityType.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text('${t.label} (${t.category})'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selected = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detailCtrl,
                  decoration: const InputDecoration(labelText: "설명 (선택, 예: 09:00~18:00)"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("취소"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("추가"),
            ),
          ],
        ),
      ),
    );

    final name = nameCtrl.text.trim();
    final detail = detailCtrl.text.trim();
    nameCtrl.dispose();
    detailCtrl.dispose();
    if (saved != true || name.isEmpty) return;

    try {
      await MapFacilityService.add(
        name: name,
        typeKey: selected.name,
        lat: point.latitude,
        lng: point.longitude,
        detail: detail.isEmpty ? null : detail,
      );
      await _loadAdminFacilities();
      if (mounted) showToast(context, "위치를 추가했습니다");
    } catch (e) {
      if (mounted) showToast(context, "추가 실패");
    }
  }

  Future<void> _confirmDeleteAdminFacility(AdminMapFacility f) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("위치 삭제"),
        content: Text("'${f.name}'을(를) 삭제하시겠습니까? 모든 사용자에게서 사라집니다."),
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
    if (confirmed != true) return;
    try {
      await MapFacilityService.delete(f.id);
      await _loadAdminFacilities();
      if (mounted) showToast(context, "삭제되었습니다");
    } catch (e) {
      if (mounted) showToast(context, "삭제 실패");
    }
  }

  /// 개발자 모드로 추가한 위치의 상세 시트. 기존 kFacilities용
  /// _showFacilityDetail과는 별도로 둔다 — 그쪽은 이미 이름 바꾸기 등
  /// 복잡한 로직이 얽혀 있어, 삭제 버튼 하나 추가하려고 건드리면
  /// 회귀 위험이 크다.
  void _showAdminFacilityDetail(AdminMapFacility f, bool isDark) {
    final type = _facilityTypeFromKey(f.typeKey);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: type.color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(type.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (f.detail != null && f.detail!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                f.detail!,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "개발자 모드로 추가된 위치",
                style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600),
              ),
            ),
            if (_devMode) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmDeleteAdminFacility(f);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text("이 위치 삭제", style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadFavoritesAndCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final c = prefs.getStringList('knue_category_order');
    if (c != null && c.length == 4) _categoryOrder = c;
    if (mounted) setState(() {});
  }

  Future<void> _saveFavoritesAndCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('knue_category_order', _categoryOrder);
  }

  Future<void> _loadCustomNames() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final bNames = prefs.getString('custom_building_names_v1');
      if (bNames != null) {
        final bMap = json.decode(bNames) as Map<String, dynamic>;
        _customBuildingNames = bMap.map(
          (k, v) => MapEntry(int.parse(k), v.toString()),
        );
      }
      final fNames = prefs.getString('custom_facility_names_v1');
      if (fNames != null) {
        final fMap = json.decode(fNames) as Map<String, dynamic>;
        _customFacilityNames = fMap.map(
          (k, v) => MapEntry(int.parse(k), v.toString()),
        );
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveCustomNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_building_names_v1',
      json.encode(
        _customBuildingNames.map((k, v) => MapEntry(k.toString(), v)),
      ),
    );
    await prefs.setString(
      'custom_facility_names_v1',
      json.encode(
        _customFacilityNames.map((k, v) => MapEntry(k.toString(), v)),
      ),
    );
  }

  Future<void> _fetchWeather() async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=36.6093&longitude=127.3585&current_weather=true&timezone=Asia%2FSeoul',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final j = json.decode(res.body) as Map;
        final cw = j['current_weather'] as Map;
        final temp = (cw['temperature'] as num).round();
        final wcode = cw['weathercode'] as int;
        if (!mounted) return;
        setState(() {
          _weatherTemp = '$temp°';
          _weatherIcon = _weatherCodeToEmoji(wcode);
        });
      }
    } catch (_) {}
  }

  String _weatherCodeToEmoji(int code) {
    if (code == 0) return '☀️';
    if (code <= 3) return '🌤️';
    if (code <= 49) return '🌫️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '❄️';
    if (code <= 82) return '🌦️';
    if (code <= 99) return '⛈️';
    return '🌡️';
  }

  /// 위치 추적을 시작한다. 권한이 거부되어 시작하지 못하면 false를 반환해
  /// 호출부(현재 위치 버튼)가 사용자에게 안내를 보여줄 수 있게 한다.
  Future<bool> _startLocationTracking() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return false;
    }
    try {
      var status = await Geolocator.checkPermission();
      if (status == LocationPermission.denied) {
        status = await Geolocator.requestPermission();
      }
      if (status == LocationPermission.denied ||
          status == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationPermGranted = false);
        return false;
      }
      if (!mounted) return false;
      setState(() => _locationPermGranted = true);
      _locSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((pos) {
            if (mounted) setState(() => _userPosition = pos);
          });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    kBuildingsRevision.removeListener(_onBuildingsUpdated);
    _locSub?.cancel();
    _zoomAnim?.dispose();
    _mapController.dispose();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // 정된 줌 애니메이션
  void _animatedZoom(double target) {
    final begin = _currentZoom;
    final end = target.clamp(14.0, 19.0);
    _zoomAnim?.dispose();
    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    final anim = CurvedAnimation(
      parent: _zoomAnim!,
      curve: Curves.easeOutCubic,
    );
    anim.addListener(() {
      final z = begin + (end - begin) * anim.value;
      _mapController.move(_mapController.camera.center, z);
    });
    _zoomAnim!.forward();
  }

  void _animatedMove(LatLng target, double zoom) {
    try {
      final latB = _mapController.camera.center.latitude;
      final lngB = _mapController.camera.center.longitude;
      final zoomB = _currentZoom;
      _zoomAnim?.dispose();
      _zoomAnim = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 450),
      );
      final anim = CurvedAnimation(
        parent: _zoomAnim!,
        curve: Curves.easeOutCubic,
      );
      anim.addListener(() {
        final t = anim.value;
        try {
          _mapController.move(
            LatLng(
              latB + (target.latitude - latB) * t,
              lngB + (target.longitude - lngB) * t,
            ),
            zoomB + (zoom - zoomB) * t,
          );
        } catch (_) {}
      });
      _zoomAnim!.forward();
    } catch (_) {
      // Map not ready yet or camera accessed before map exists. Check fallback.
      setState(() => _currentZoom = zoom);
    }
  }

  // ─── 산책로 영구 저장/불러오기 ───

  Future<void> _loadTrails() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_trailsKey) ?? [];
    final names = prefs.getStringList('${_trailsKey}_names') ?? [];
    if (!mounted) return;
    setState(() {
      _savedTrails = data.map((item) {
        final pts = json.decode(item) as List;
        return pts
            .map<LatLng>((p) => LatLng(p[0] as double, p[1] as double))
            .toList();
      }).toList();
      _trailNames = List.generate(
        _savedTrails.length,
        (i) => i < names.length ? names[i] : '산책로 ${i + 1}',
      );
    });
  }

  Future<void> _persistTrails() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _savedTrails
        .map(
          (trail) =>
              json.encode(trail.map((p) => [p.latitude, p.longitude]).toList()),
        )
        .toList();
    await prefs.setStringList(_trailsKey, data);
    await prefs.setStringList('${_trailsKey}_names', _trailNames);
  }

  Future<void> _deleteTrail(int idx) async {
    setState(() => _savedTrails.removeAt(idx));
    await _persistTrails();
  }

  void _saveTrail() {
    if (_trailPoints.length < 2) return;
    setState(() {
      _savedTrails.add(List.from(_trailPoints));
      _trailPoints.clear();
      _trailMode = false;
    });
    _persistTrails();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '🥾 산책로가 저장되었습니다!',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── 빌드 ───

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, primary, _) => Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: isDark
            ? const Color(0xFF0D0D0D)
            : const Color(0xFFF4F6FB),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: _buildTopBar(primary, isDark),
        ),
        body: Stack(
          children: [
            TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              controller: _tabController,
              children: [
                _buildMapTab(primary, isDark),
                _buildPlacesTab(primary, isDark),
              ],
            ),
            if (_searchOpen) _buildSearchOverlay(primary, isDark),
          ],
        ),
      ),
    );
  }

  // ─── iOS 스타일 탑바 ───

  Widget _buildTopBar(Color primary, bool isDark) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.65),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Text(
                        '캠퍼스맵',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      // 검색만 상단에 남긴다 — 건물표시/산책로 토글은 지도 위
                      // 세로 스택으로 내려, 조작 대상 옆에서 조작하게 했다.
                      _TopBarBtn(
                        icon: _searchOpen
                            ? Icons.search_off_rounded
                            : Icons.search_rounded,
                        active: _searchOpen,
                        isDark: isDark,
                        activeColor: primary,
                        onTap: () => setState(() {
                          _searchOpen = !_searchOpen;
                          if (!_searchOpen) {
                            _searchQuery = '';
                            _searchCtrl.clear();
                          }
                        }),
                      ),
                      _TopBarBtn(
                        icon: Icons.help_outline_rounded,
                        active: false,
                        isDark: isDark,
                        activeColor: primary,
                        onTap: () => _showFeatureGuide(primary, isDark),
                      ),
                      // 숨은 개발자 모드 진입로 — 일반 사용자 눈에 띄지 않게
                      // 다른 관리 화면들처럼 숨겨두는 대신, 지도 조작과
                      // 묶여 있어야 해서 여기 아이콘으로 남긴다.
                      _TopBarBtn(
                        icon: _devMode
                            ? Icons.build_circle_rounded
                            : Icons.build_circle_outlined,
                        active: _devMode,
                        isDark: isDark,
                        activeColor: Colors.redAccent,
                        onTap: () => _toggleDevMode(isDark),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: isDark
                        ? primary.withValues(alpha: 0.2)
                        : primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  indicatorPadding: const EdgeInsets.symmetric(
                    horizontal: -10,
                    vertical: 4,
                  ),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  labelColor: primary,
                  unselectedLabelColor: isDark
                      ? Colors.white54
                      : Colors.black54,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  // 3개뿐이라 스크롤 없이 균등 분할 — 한눈에 전체 구조가 보인다.
                  isScrollable: false,
                  padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                  tabs: const [
                    _MapGroupTab(icon: Icons.map_rounded, label: '지도'),
                    _MapGroupTab(icon: Icons.place_rounded, label: '장소'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 검색 오버레이 ───

  Widget _buildSearchOverlay(Color primary, bool isDark) {
    final query = _searchQuery.trim();
    final allItems = [
      ...kBuildings.asMap().entries.map(
        (e) => _SearchItem(
          name: _customBuildingNames[e.key] ?? e.value.name,
          sub: e.value.description,
          icon: Icons.business,
          color: e.value.color,
          onTap: () {
            _searchCtrl.clear();
            setState(() {
              _searchOpen = false;
              _searchQuery = '';
            });
            _tabController.animateTo(0);
            Future.delayed(
              const Duration(milliseconds: 200),
              () => _animatedMove(e.value.position, 18.0),
            );
            _showBuildingDetail(e.value);
          },
        ),
      ),
      ...kFacilities.asMap().entries.map(
        (e) => _SearchItem(
          name: _customFacilityNames[e.key] ?? e.value.name,
          sub: e.value.detail ?? e.value.type.label,
          icon: e.value.type.icon,
          color: e.value.type.color,
          onTap: () {
            _searchCtrl.clear();
            setState(() {
              _searchOpen = false;
              _searchQuery = '';
            });
            _tabController.animateTo(0);
            Future.delayed(
              const Duration(milliseconds: 200),
              () => _animatedMove(e.value.position, 18.5),
            );
            _showFacilityDetail(e.value);
          },
        ),
      ),
      // 강의실 — 예전엔 전용 탭에 들어가 건물을 고른 뒤에야 찾을 수 있었다.
      // 이제 강의실 이름만 알면 통합 검색에서 바로 나온다.
      for (final b in kBuildings)
        for (final f in b.floors)
          for (final room in f.rooms)
            _SearchItem(
              name: room,
              sub: '${b.name} ${f.floor}',
              icon: Icons.meeting_room_rounded,
              color: b.color,
              onTap: () {
                _searchCtrl.clear();
                setState(() {
                  _searchOpen = false;
                  _searchQuery = '';
                  _selectedClassroomBuilding = b;
                  _placeSegment = 2; // 장소 > 강의실
                });
                _tabController.animateTo(1);
              },
            ),
      // 연락처는 캠퍼스맵에서 다루지 않지만, 검색에서는 계속 찾히게 둔다.
      // 여기서 "과 사무실"을 검색하는 사람이 많고, 결과가 없으면 앱 어디에도
      // 없다고 오해하기 쉬워서다. 탭하면 교직원 연락처 화면으로 넘긴다.
      ...kDeptOffices.map(
        (d) => _SearchItem(
          name: d.dept,
          sub: '${d.building} ${d.room} · ${d.phone}',
          icon: Icons.school_rounded,
          color: primary,
          onTap: () => _openContacts(deptOnly: true),
        ),
      ),
      ...kAdminStaff.map(
        (a) => _SearchItem(
          name: '${a.dept} ${a.category}',
          sub: a.duties.isNotEmpty ? '${a.duties} · ${a.phone}' : a.phone,
          icon: Icons.badge_rounded,
          color: primary,
          onTap: () => _openContacts(deptOnly: false),
        ),
      ),
    ];
    // 강의실·연락처까지 합치면 후보가 2천 건이 넘는다. 한 글자만 쳐도 수백 건이
    // 매칭될 수 있어 상한을 두고, 대소문자 구분 없이 찾는다.
    final q = query.toLowerCase();
    final results = query.isEmpty
        ? <_SearchItem>[]
        : allItems
              .where((i) =>
                  i.name.toLowerCase().contains(q) ||
                  i.sub.toLowerCase().contains(q))
              .take(60)
              .toList();

    return Positioned.fill(
      top: MediaQuery.of(context).padding.top + 104,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.85),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade900
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white12
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: '건물·시설·강의실·연락처 검색...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: isDark ? Colors.white54 : Colors.black54,
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                // 결과 목록
                if (results.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: results.length > 8 ? 8 : results.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                        ),
                        itemBuilder: (_, i) {
                          final item = results[i];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: item.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                item.icon,
                                color: item.color,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              item.sub,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            onTap: item.onTap,
                          );
                        },
                      ),
                    ),
                  )
                else if (query.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        '검색 결과가 없습니다',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _searchOpen = false;
                        _searchQuery = '';
                        _searchCtrl.clear();
                      });
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 지도 탭 ───

  Widget _buildMapTab(Color primary, bool isDark) {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return _buildDesktopFallback(primary, isDark);
    }
    final orderedFacilities = _facilityOrder
        .where((i) => !_hiddenFacilityIdx.contains(i))
        .map((i) => kFacilities[i])
        .toList();
    // 개발자 모드로 찍은 위치도 같은 필터(카테고리 켜짐·줌 레벨)를 그대로 따른다.
    final adminAsFacilities = _adminFacilities.map(
      (a) => MapFacility(
        name: a.name,
        type: _facilityTypeFromKey(a.typeKey),
        position: LatLng(a.lat, a.lng),
        detail: a.detail,
        adminId: a.id,
      ),
    );
    final filtered = [...orderedFacilities, ...adminAsFacilities]
        .where(
          (f) =>
              _activeFilters.contains(f.type) && _currentZoom >= f.type.minZoom,
        )
        .toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _knueCenter,
            initialZoom: _currentZoom,
            minZoom: 14.0,
            maxZoom: 19.0,
            onTap: _trailMode
                ? (tap, pt) => setState(() => _trailPoints.add(pt))
                : null,
            onLongPress: _devMode
                ? (tap, pt) => _showAddFacilityDialog(pt, isDark)
                : null,
            onMapEvent: (e) {
              if (e is MapEventMove) {
                setState(() => _currentZoom = e.camera.zoom);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.knue.knuemate',
            ),
            // 저장된 산책로
            ..._savedTrails.asMap().entries.map(
              (e) => PolylineLayer(
                polylines: [
                  Polyline(
                    points: e.value,
                    strokeWidth: 4,
                    color: Colors.primaries[e.key % Colors.primaries.length]
                        .withValues(alpha: 0.85),
                  ),
                ],
              ),
            ),
            // 현재 그리는 산책로
            if (_trailPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _trailPoints,
                    strokeWidth: 4,
                    color: Colors.yellowAccent.withValues(alpha: 0.9),
                  ),
                ],
              ),
            // 웨이포인트
            if (_trailMode && _trailPoints.isNotEmpty)
              MarkerLayer(
                markers: _trailPoints
                    .asMap()
                    .entries
                    .map(
                      (e) => Marker(
                        point: e.value,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: e.key == 0 ? Colors.green : Colors.yellow,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            if (_showBuildings && _currentZoom >= 15.5)
              MarkerLayer(
                markers: kBuildings
                    .asMap()
                    .entries
                    .where((e) => !_hiddenBuildingIdx.contains(e.key))
                    .map((e) {
                      final b = e.value;
                      final large = _currentZoom >= 17;
                      return Marker(
                        point: b.position,
                        width: large ? 100.0 : 74.0,
                        height: large ? 42.0 : 30.0,
                        alignment: Alignment.bottomCenter,
                        child: GestureDetector(
                          onTap: () => _showBuildingDetail(b),
                          child: _MapLabel(
                            text: _customBuildingNames[e.key] ?? b.name,
                            color: b.color,
                            large: large,
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),
            // 시설 마커
            if (filtered.isNotEmpty)
              MarkerLayer(
                markers: filtered
                    .map(
                      (f) => Marker(
                        point: f.position,
                        width: 34,
                        height: 34,
                        child: GestureDetector(
                          onTap: () => f.adminId != null
                              ? _showAdminFacilityDetail(
                                  _adminFacilities
                                      .firstWhere((a) => a.id == f.adminId),
                                  isDark,
                                )
                              : _showFacilityDetail(f),
                          child: _FacilityPin(type: f.type),
                        ),
                      ),
                    )
                    .toList(),
              ),

            // 내 위치 마커
            if (_userPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      _userPosition!.latitude,
                      _userPosition!.longitude,
                    ),
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    child: _UserLocationMarker(primary: primary),
                  ),
                ],
              ),
          ],
        ),

        // 날씨 위젯 (좌하단)
        if (_weatherTemp != null)
          Positioned(
            left: 12,
            bottom: _trailMode ? 130 : 28, // Navigation pill 여백 고려
            child: GestureDetector(
              onTap: _fetchWeather,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C1E).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: isDark
                            ? Colors.white12
                            : Colors.black.withValues(alpha: 0.05),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _weatherIcon!,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _weatherTemp!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // 필터 바
        Positioned(
          top: MediaQuery.of(context).padding.top + 104 + 8,
          left: 10,
          right: 10,
          child: _buildFilterBar(isDark),
        ),

        // 지도 조작 토글 — 예전엔 상단바에 있었으나, 조작 대상(지도) 옆에
        // 두어야 무슨 버튼인지 즉시 이해된다.
        Positioned(
          right: 12,
          top: MediaQuery.of(context).padding.top + 104 + 60,
          child: _buildMapToggleStack(primary, isDark),
        ),

        // 줌 컨트롤
        Positioned(
          right: 12,
          bottom: _trailMode ? 130 : 28,
          child: _buildZoomControls(primary),
        ),

        // 산책로 패널
        if (_trailMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildTrailPanel(primary, isDark),
          ),
      ],
    );
  }

  // ─── 필터 바 (카테고리) ───

  /// 지도 위 세로 토글 스택 — 건물 라벨 표시 / 산책로 그리기 / 저장 목록.
  Widget _buildMapToggleStack(Color primary, bool isDark) {
    final warm = KnueTokens.warm(isDark);
    Widget btn({
      required IconData icon,
      required bool active,
      required Color activeColor,
      required VoidCallback onTap,
      required String tooltip,
      bool last = false,
    }) {
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: last
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12,
                        width: 0.5,
                      ),
                    ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: active
                  ? activeColor
                  : (isDark ? Colors.white54 : Colors.black45),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.75)
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(
                icon: _showBuildings
                    ? Icons.location_city_rounded
                    : Icons.location_city_outlined,
                active: _showBuildings,
                activeColor: primary,
                tooltip: '건물 이름 표시',
                onTap: () => setState(() => _showBuildings = !_showBuildings),
              ),
              btn(
                icon: _trailMode
                    ? Icons.edit_off_rounded
                    : Icons.route_rounded,
                active: _trailMode,
                activeColor: warm,
                tooltip: _trailMode ? '산책로 그리기 종료' : '산책로 그리기',
                onTap: () => setState(() {
                  _trailMode = !_trailMode;
                  if (!_trailMode) _trailPoints.clear();
                }),
              ),
              btn(
                icon: Icons.format_list_bulleted_rounded,
                active: false,
                activeColor: primary,
                tooltip: '저장된 산책로',
                last: true,
                onTap: () => _showTrailListSheet(primary, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    List<FacilityType> orderedTypes = _facilityOrder
        .map((i) => kFacilities[i].type)
        .toSet()
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          height: 52,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.05),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              _FilterChip(
                label: '전체',
                icon: Icons.layers_rounded,
                active: _activeFilters.length == orderedTypes.length,
                color: Colors.blueAccent,
                isDark: isDark,
                onTap: () {
                  setState(() {
                    if (_activeFilters.length == orderedTypes.length) {
                      _activeFilters.clear();
                    } else {
                      _activeFilters.clear();
                      _activeFilters.addAll(orderedTypes);
                    }
                  });
                },
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 16,
                color: isDark ? Colors.white24 : Colors.black12,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) =>
                      Material(color: Colors.transparent, child: child),
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) newIndex -= 1;

                      // _facilityOrder를 다시 정렬
                      final oldType = orderedTypes[oldIndex];

                      // 현재 선택된 타입에 해당하는 인덱스들을 추출
                      final typeIndices = _facilityOrder
                          .where((i) => kFacilities[i].type == oldType)
                          .toList();
                      _facilityOrder.removeWhere(
                        (i) => kFacilities[i].type == oldType,
                      );

                      // 새로운 위치를 찾아 삽입.
                      // 단순화를 위해 orderedTypes 기준 새로운 인덱스의 앞 타입 뒤에 삽입
                      if (newIndex == 0) {
                        _facilityOrder.insertAll(0, typeIndices);
                      } else {
                        final insertAfterType =
                            orderedTypes[newIndex > oldIndex
                                ? newIndex
                                : newIndex - 1];
                        final lastIdxOfInsertAfter = _facilityOrder
                            .lastIndexWhere(
                              (i) => kFacilities[i].type == insertAfterType,
                            );
                        if (lastIdxOfInsertAfter != -1) {
                          _facilityOrder.insertAll(
                            lastIdxOfInsertAfter + 1,
                            typeIndices,
                          );
                        } else {
                          _facilityOrder.addAll(typeIndices);
                        }
                      }
                    });
                  },
                  children: [
                    for (int i = 0; i < orderedTypes.length; i++)
                      _CustomReorderableDragStartListener(
                        key: ValueKey(orderedTypes[i]),
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _FilterChip(
                            label: orderedTypes[i].label,
                            icon: orderedTypes[i].icon,
                            active: _activeFilters.contains(orderedTypes[i]),
                            color: orderedTypes[i].color,
                            isDark: isDark,
                            small: true,
                            onTap: () {
                              setState(() {
                                if (_activeFilters.contains(orderedTypes[i])) {
                                  _activeFilters.remove(orderedTypes[i]);
                                } else {
                                  _activeFilters.add(orderedTypes[i]);
                                }
                              });
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 줌 컨트롤 ───

  Widget _buildZoomControls(Color primary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.65);
    final shadow = BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
      blurRadius: 16,
      offset: const Offset(0, 4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          width: 48,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [shadow],
            border: Border.all(
              color: isDark
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.05),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              _PillZoomBtn(
                icon: Icons.add_rounded,
                onTap: () => _animatedZoom(_currentZoom + 1),
                isDark: isDark,
              ),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.05),
              ),
              _PillZoomBtn(
                icon: Icons.remove_rounded,
                onTap: () => _animatedZoom(_currentZoom - 1),
                isDark: isDark,
              ),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.05),
              ),
              _PillZoomBtn(
                icon: Icons.my_location_rounded,
                color: _userPosition != null ? Colors.blue : null,
                onTap: () async {
                  if (_userPosition != null) {
                    _animatedMove(
                      LatLng(_userPosition!.latitude, _userPosition!.longitude),
                      17.5,
                    );
                    return;
                  }
                  final granted = await _startLocationTracking();
                  if (!granted) {
                    if (!mounted) return;
                    showToast(context, "위치 권한이 필요합니다. 설정에서 허용해주세요.");
                    await Geolocator.openAppSettings();
                    return;
                  }
                  _animatedMove(_knueCenter, 16.5);
                },
                isDark: isDark,
              ),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.05),
              ),
              _PillZoomBtn(
                icon: Icons.school_rounded,
                onTap: () => _animatedMove(_knueCenter, 16.0),
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 산책로 패널 ───

  Widget _buildTrailPanel(Color primary, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1C1C1E).withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.05),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.edit_location_alt_rounded,
                      color: Colors.amber.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '산책로 그리기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade600.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_trailPoints.length} 포인트',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '지도 위를 터치하여 새로운 산책로를 이어나가 보세요.\n저장된 경로는 산책로 탭에서 볼 수 있습니다.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (_trailPoints.isNotEmpty) {
                            setState(() => _trailPoints.removeLast());
                          }
                        },
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('실행 취소'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.white
                              : Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _trailPoints.length >= 2 ? _saveTrail : null,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text(
                          '저장하기',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 건물 안내 탭 ───

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
        // 상단 여백은 그룹 탭(_buildPlacesTab)이 이미 잡아준다.
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
                            child: Icon(
                              f.type.icon,
                              color: f.type.color,
                              size: 20,
                            ),
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

  Widget _buildBuildingTab(Color primary, bool isDark) {
    final orderedBuildings = _buildingOrder
        .map((i) => (i, kBuildings[i]))
        .toList();
    final visibleBuildings = orderedBuildings
        .where((e) => !_hiddenBuildingIdx.contains(e.$1))
        .toList();
    return Column(
      children: [
        // 상단 여백은 그룹 탭(_buildPlacesTab)이 이미 잡아준다.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                '건물 목록',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              if (_hiddenBuildingIdx.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _hiddenBuildingIdx.clear()),
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
                        '숨김 ${_hiddenBuildingIdx.length}개 해제',
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
                onTap: () => _showReorderSheet(isDark, primary),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.swap_vert_rounded, size: 14, color: primary),
                      const SizedBox(width: 4),
                      Text(
                        '순서 편집',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primary,
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
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            itemCount: visibleBuildings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final (idx, b) = visibleBuildings[i];
              return Dismissible(
                key: ValueKey(idx),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility_off_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '숨기기',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                confirmDismiss: (_) async {
                  setState(() => _hiddenBuildingIdx.add(idx));
                  return false;
                },
                child: _BuildingCard(
                  building: b,
                  isDark: isDark,
                  customName: _customBuildingNames[idx],
                  onTap: () {
                    _tabController.animateTo(0);
                    Future.delayed(
                      const Duration(milliseconds: 300),
                      () => _animatedMove(b.position, 18.0),
                    );
                    _showBuildingDetail(b);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── 산책로 탭 ───

  double _calcTrailDistance(List<LatLng> pts) {
    double total = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      total += _haversine(pts[i], pts[i + 1]);
    }
    return total;
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final x =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(x));
  }

  String _formatDist(double m) {
    if (m < 1000) return '${m.round()}m';
    return '${(m / 1000).toStringAsFixed(2)}km';
  }

  void _showTrailEditDialog(
    int idx,
    String currentName,
    List<LatLng> trail,
    Color primary,
    bool isDark,
  ) {
    final textCtrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '산책로 이름 변경',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '산책로 이름을 지어주세요',
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(c),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black12,
                        ),
                      ),
                      child: Text(
                        '취소',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(c);
                        final newName = textCtrl.text.trim();
                        if (newName.isNotEmpty) {
                          setState(() {
                            while (_trailNames.length <= idx) {
                              _trailNames.add('산책로 ${_trailNames.length + 1}');
                            }
                            _trailNames[idx] = newName;
                          });
                          _persistTrails();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '저장',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: isDark ? Colors.white12 : Colors.black12),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(c);
                  showDialog(
                    context: context,
                    builder: (confirmC) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: const Text(
                        '지도에서 경로 이어그리기',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      content: const Text(
                        '이 산책로를 지도에 띄워 다시 편집하시겠습니까?\n(편집 모드로 진입하며, 기존 저장된 경로는 초기화됩니다.)',
                        style: TextStyle(fontSize: 14, height: 1.4),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmC),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(confirmC);
                            setState(() {
                              _trailPoints.clear();
                              _trailPoints.addAll(trail);
                              _trailMode = true;
                              _trailNames.removeAt(idx);
                              _savedTrails.removeAt(idx);
                            });
                            _persistTrails();
                            _tabController.animateTo(0);
                            _animatedMove(trail.last, 17.0);
                          },
                          child: const Text(
                            '편집 시작',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                icon: Icon(Icons.edit_location_alt_rounded, color: primary),
                label: Text(
                  '지도에서 이 산책로 편집하기',
                  style: TextStyle(fontWeight: FontWeight.w700, color: primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 그룹 탭: 장소 / 연락처 ───

  /// 세그먼트 바. 그룹 안에서 하위 화면을 고르는 공통 UI.
  Widget _buildSegmentBar({
    required List<String> labels,
    required int selected,
    required ValueChanged<int> onSelect,
    required Color primary,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
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
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? primary
                          : (isDark ? Colors.white54 : Colors.black54),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 장소 그룹 — 건물 / 부속시설 / 강의실.
  /// 세 화면 모두 "캠퍼스 어딘가를 찾는" 같은 목적이라 한 문 뒤로 모았다.
  Widget _buildPlacesTab(Color primary, bool isDark) {
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 104),
        _buildSegmentBar(
          labels: const ['건물', '부속시설', '강의실'],
          selected: _placeSegment,
          onSelect: (i) => setState(() => _placeSegment = i),
          primary: primary,
          isDark: isDark,
        ),
        Expanded(
          child: IndexedStack(
            index: _placeSegment,
            children: [
              _buildBuildingTab(primary, isDark),
              _buildFacilityTab(primary, isDark),
              _buildClassroomSearchTab(primary, isDark),
            ],
          ),
        ),
      ],
    );
  }


  /// 검색 오버레이를 닫고 교직원 연락처 화면을 연다.
  /// 연락처는 캠퍼스맵에서 빠졌지만 검색으로는 여전히 닿을 수 있게 한다.
  void _openContacts({required bool deptOnly}) {
    _searchCtrl.clear();
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffContactsScreen(initialDeptOnly: deptOnly),
      ),
    );
  }

  // ─── 기능 안내 (발견성 보완) ───

  /// 첫 진입 때 1회 자동으로, 이후에는 상단 ? 버튼으로 열리는 안내.
  /// 7개 탭에 흩어져 아무도 모르던 기능들을 한 장으로 보여준다.
  Future<void> _maybeShowFirstRunGuide(Color primary, bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kGuideSeenKey) == true) return;
    if (!mounted) return;
    await prefs.setBool(_kGuideSeenKey, true);
    if (!mounted) return;
    _showFeatureGuide(primary, isDark);
  }

  void _showFeatureGuide(Color primary, bool isDark) {
    const items = [
      (
        Icons.route_rounded,
        '산책로 그리기',
        '지도 오른쪽 산책로 버튼을 켜고 지도를 탭하면 나만의 경로가 그려집니다.'
      ),
      (
        Icons.meeting_room_rounded,
        '강의실 찾기',
        '장소 → 강의실에서 건물을 고르면 층별 강의실·연구실을 볼 수 있어요.'
      ),
      (
        Icons.call_rounded,
        '연락처는 검색으로',
        '학과·부서 이름을 검색하면 교직원 연락처 화면으로 바로 넘어갑니다.'
      ),
      (
        Icons.tune_rounded,
        '내 맞춤 정렬',
        '장소 목록 우측 상단에서 순서 변경·숨김·이름 바꾸기를 할 수 있어요.'
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161618) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  '캠퍼스맵에는 이런 기능이 있어요',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                ...items.map(
                  (it) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: primary.withValues(
                                alpha: isDark ? 0.18 : 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(it.$1, size: 18, color: primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                it.$2,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                it.$3,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).maybePop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '알겠어요',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 저장된 산책로 목록. 예전에는 별도 탭이었지만, 산책로는 지도에서 그리고
  /// 지도에서 보는 것이라 지도 탭의 바텀시트로 옮겼다. 내용은 그대로다.
  void _showTrailListSheet(Color primary, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161618) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(child: _buildTrailList(primary, isDark, scrollCtrl)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrailList(
      Color primary, bool isDark, ScrollController scrollCtrl) {
    if (_savedTrails.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.route_rounded,
                size: 56,
                color: isDark ? Colors.white24 : Colors.black12,
              ),
              const SizedBox(height: 12),
              Text(
                '저장된 산책로가 없습니다',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '지도의 산책로 버튼을 켜고 지도를 탭해 경로를 그려보세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Row(
            children: [
              Text(
                '내 산책로 · ${_savedTrails.length}개',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            itemCount: _savedTrails.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, idx) {
              final trail = _savedTrails[idx];
              final name = idx < _trailNames.length
                  ? _trailNames[idx]
                  : '산책로 ${idx + 1}';
              final dist = _calcTrailDistance(trail);
              final trailColor =
                  Colors.primaries[idx % Colors.primaries.length];
              final isSelected = _selectedTrailIdx == idx;
              final walkMinutes = (dist / 80).ceil();
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTrailIdx = isSelected ? null : idx);
                  // 시트를 닫으면 바로 뒤가 지도라 탭 이동이 필요 없다.
                  Navigator.of(ctx).maybePop();
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (trail.isNotEmpty) _animatedMove(trail.first, 16.5);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? trailColor
                          : trailColor.withValues(alpha: 0.25),
                      width: isSelected ? 2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: trailColor.withValues(
                          alpha: isSelected ? 0.18 : 0.06,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: trailColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.hiking_rounded,
                                color: trailColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.straighten_rounded,
                                            size: 13,
                                            color: trailColor,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            _formatDist(dist),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: trailColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.timer_outlined,
                                            size: 13,
                                            color: Colors.grey.shade500,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '약 $walkMinutes분',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.location_on_rounded,
                                            size: 13,
                                            color: Colors.grey.shade500,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${trail.length}개 지점',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.edit_rounded,
                                    size: 18,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                  tooltip: '이름/경로 편집',
                                  onPressed: () => _showTrailEditDialog(
                                    idx,
                                    name,
                                    trail,
                                    primary,
                                    isDark,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.ios_share_rounded,
                                    size: 18,
                                    color: Colors.blueAccent,
                                  ),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => _ScreenshotShareDialog(
                                        name: name,
                                        trail: trail,
                                        dist: dist,
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                  tooltip: '삭제',
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      title: const Text(
                                        '산책로 삭제',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      content: Text('"$name"을(를) 삭제할까요?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c),
                                          child: Text(
                                            '취소',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(c);
                                            _deleteTrail(idx);
                                          },
                                          child: const Text(
                                            '삭제',
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: trailColor.withValues(alpha: 0.08),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(14),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '지도에서 표시 중 ✓',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: trailColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── 과 사무실 탭 ───

  String _classroomSearchQuery = '';
  BuildingData? _selectedClassroomBuilding;

  Widget _buildClassroomSearchTab(Color primary, bool isDark) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final selectedBuilding = _selectedClassroomBuilding;

        // ── 1단계: 건물 선택 ──
        if (selectedBuilding == null) {
          final buildingsWithFloors =
              kBuildings.where((b) => b.floors.isNotEmpty).toList()
                ..sort((a, b) => a.name.compareTo(b.name));

          return Column(
            children: [
              // 상단 여백은 그룹 탭(_buildPlacesTab)이 이미 잡아준다.
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.apartment_rounded, size: 18, color: primary),
                    const SizedBox(width: 8),
                    Text(
                      '건물을 선택하세요',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 40),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.15,
                  ),
                  itemCount: buildingsWithFloors.length,
                  itemBuilder: (ctx, i) {
                    final b = buildingsWithFloors[i];
                    return GestureDetector(
                      onTap: () => setLocalState(() {
                        _selectedClassroomBuilding = b;
                        _classroomSearchQuery = '';
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E2E)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: b.color.withValues(alpha: 0.25),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: b.color.withValues(
                                alpha: isDark ? 0.2 : 0.05,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: b.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  b.shortName.length > 2
                                      ? b.shortName.substring(0, 2)
                                      : b.shortName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: b.color,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      letterSpacing: -0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${b.aboveGroundFloorCount}\uce35',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        // ── 2단계: 강의실 검색 ──
        final query = _classroomSearchQuery.trim().toLowerCase();
        final List<Map<String, dynamic>> results = [];
        if (query.isEmpty) {
          for (final f in selectedBuilding.floors) {
            for (final room in f.rooms) {
              results.add({'floor': f.floor, 'room': room});
            }
          }
        } else {
          for (final f in selectedBuilding.floors) {
            for (final room in f.rooms) {
              if (room.toLowerCase().contains(query) ||
                  f.floor.toString().contains(query)) {
                results.add({'floor': f.floor, 'room': room});
              }
            }
          }
        }

        return Column(
          children: [
            // 상단 여백은 그룹 탭(_buildPlacesTab)이 이미 잡아준다.
            const SizedBox(height: 4),
            // 헤더: 뒤로가기 + 건물 이름
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 16, 2),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setLocalState(() {
                      _selectedClassroomBuilding = null;
                      _classroomSearchQuery = '';
                    }),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selectedBuilding.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Text(
                        selectedBuilding.shortName.length > 2
                            ? selectedBuilding.shortName.substring(0, 2)
                            : selectedBuilding.shortName,
                        style: TextStyle(
                          color: selectedBuilding.color,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedBuilding.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _tabController.animateTo(0);
                      Future.delayed(
                        const Duration(milliseconds: 200),
                        () => _animatedMove(selectedBuilding.position, 18.0),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: selectedBuilding.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.near_me_rounded,
                            size: 11,
                            color: selectedBuilding.color,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '지도',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selectedBuilding.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 검색창
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white12
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (v) =>
                            setLocalState(() => _classroomSearchQuery = v),
                        decoration: InputDecoration(
                          hintText: '강의실 호수, 이름 검색...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 11,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (results.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    '검색 결과가 없습니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  itemCount: results.length,
                  itemBuilder: (ctx, i) {
                    final r = results[i];
                    final floor = r['floor'];
                    final String room = r['room'];
                    final floorLabel = floor is int
                        ? (floor < 0 ? 'B${floor.abs()}' : '${floor}F')
                        : floor.toString();
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedBuilding.color.withValues(alpha: 0.15),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: selectedBuilding.color.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              floorLabel,
                              style: TextStyle(
                                color: selectedBuilding.color,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          room,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          '${selectedBuilding.name} $floorLabel',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        onTap: () {
                          _tabController.animateTo(0);
                          Future.delayed(
                            const Duration(milliseconds: 200),
                            () =>
                                _animatedMove(selectedBuilding.position, 18.0),
                          );
                          Future.delayed(
                            const Duration(milliseconds: 400),
                            () => _showBuildingDetail(selectedBuilding),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _showReorderSheet(bool isDark, Color primary) {
    final tempOrder = List<int>.from(_buildingOrder);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '건물 순서 편집',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setLocalState(
                          () => tempOrder.setAll(
                            0,
                            List.generate(kBuildings.length, (i) => i),
                          ),
                        );
                      },
                      child: Text(
                        '초기화',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _buildingOrder = List.from(tempOrder));
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        '완료',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: tempOrder.length,
                  onReorder: (oldIdx, newIdx) {
                    setLocalState(() {
                      if (newIdx > oldIdx) newIdx--;
                      final item = tempOrder.removeAt(oldIdx);
                      tempOrder.insert(newIdx, item);
                    });
                  },
                  itemBuilder: (_, i) {
                    final b = kBuildings[tempOrder[i]];
                    return ListTile(
                      key: ValueKey(tempOrder[i]),
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: b.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            b.shortName.length > 2
                                ? b.shortName.substring(0, 2)
                                : b.shortName,
                            style: TextStyle(
                              color: b.color,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        b.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        b.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _hiddenBuildingIdx.contains(tempOrder[i])
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: _hiddenBuildingIdx.contains(tempOrder[i])
                                  ? Colors.redAccent
                                  : (isDark ? Colors.white54 : Colors.black54),
                              size: 20,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setLocalState(() {
                                setState(() {
                                  if (_hiddenBuildingIdx.contains(
                                    tempOrder[i],
                                  )) {
                                    _hiddenBuildingIdx.remove(tempOrder[i]);
                                  } else {
                                    _hiddenBuildingIdx.add(tempOrder[i]);
                                  }
                                });
                              });
                            },
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.drag_handle_rounded,
                            color: isDark ? Colors.white38 : Colors.black26,
                          ),
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

  // ─── 바텀시트: 건물 ───

  void _showBuildingDetail(BuildingData b) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final idx = kBuildings.indexOf(b);
    final displayedName = _customBuildingNames[idx] ?? b.name;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 핸들
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 헤더
              Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: b.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          b.shortName.length > 3
                              ? b.shortName.substring(0, 3)
                              : b.shortName,
                          style: TextStyle(
                            color: b.color,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                displayedName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: isDark ? Colors.white : Colors.black87,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  final textCtrl = TextEditingController(
                                    text: displayedName,
                                  );
                                  showDialog(
                                    context: context,
                                    builder: (c) => Dialog(
                                      backgroundColor: Colors.transparent,
                                      child: Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF1E1E2E)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white12
                                                : Colors.black12,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              '건물 이름 변경',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            TextField(
                                              controller: textCtrl,
                                              autofocus: true,
                                              decoration: InputDecoration(
                                                hintText: '새 이름 입력',
                                                filled: true,
                                                fillColor: isDark
                                                    ? Colors.white10
                                                    : Colors.grey.shade100,
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide.none,
                                                ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 14,
                                                    ),
                                              ),
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 24),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c),
                                                    style: OutlinedButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 14,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      side: BorderSide(
                                                        color: isDark
                                                            ? Colors.white24
                                                            : Colors.black12,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '취소',
                                                      style: TextStyle(
                                                        color: isDark
                                                            ? Colors.white70
                                                            : Colors.black87,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: () {
                                                      Navigator.pop(c);
                                                      final newName = textCtrl
                                                          .text
                                                          .trim();
                                                      setState(() {
                                                        if (newName
                                                            .isNotEmpty) {
                                                          _customBuildingNames[idx] =
                                                              newName;
                                                        } else {
                                                          _customBuildingNames
                                                              .remove(idx);
                                                        }
                                                      });
                                                      _saveCustomNames();
                                                      Navigator.pop(ctx);
                                                      _showBuildingDetail(b);
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: b.color,
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 14,
                                                          ),
                                                      elevation: 0,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      '저장',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: Icon(
                                  Icons.edit_rounded,
                                  size: 16,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            b.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 층별 안내 (어코디언 + 정렬 토글)
              _BuildingFloorSection(
                building: b,
                isDark: isDark,
                ctrl: ctrl,
                onHide: () {
                  Navigator.pop(ctx);
                  setState(() {
                    final idx = kBuildings.indexOf(b);
                    if (idx >= 0) _hiddenBuildingIdx.add(idx);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 바텀시트: 시설 ───

  void _showFacilityDetail(MapFacility f) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idx = kFacilities.indexOf(f);
    final displayedName = _customFacilityNames[idx] ?? f.name;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 16),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 아이콘 + 이름
              Row(
                children: [
                  const SizedBox(width: 20),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: f.type.color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(f.type.icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            displayedName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: isDark ? Colors.white : Colors.black87,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final textCtrl = TextEditingController(
                                text: displayedName,
                              );
                              showDialog(
                                context: context,
                                builder: (c) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1E1E2E)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.black12,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          '시설 이름 변경',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        TextField(
                                          controller: textCtrl,
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            hintText: '새 이름 입력',
                                            filled: true,
                                            fillColor: isDark
                                                ? Colors.white10
                                                : Colors.grey.shade100,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide.none,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 14,
                                                ),
                                          ),
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: () =>
                                                    Navigator.pop(c),
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 14,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  side: BorderSide(
                                                    color: isDark
                                                        ? Colors.white24
                                                        : Colors.black12,
                                                  ),
                                                ),
                                                child: Text(
                                                  '취소',
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  Navigator.pop(c);
                                                  final newName = textCtrl.text
                                                      .trim();
                                                  setState(() {
                                                    if (newName.isNotEmpty) {
                                                      _customFacilityNames[idx] =
                                                          newName;
                                                    } else {
                                                      _customFacilityNames
                                                          .remove(idx);
                                                    }
                                                  });
                                                  _saveCustomNames();
                                                  Navigator.pop(ctx);
                                                  _showFacilityDetail(f);
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: f.type.color,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 14,
                                                      ),
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  '저장',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: f.type.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          f.type.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: f.type.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 운영 시간 카드
              if (f.detail != null) ...[
                const SizedBox(height: 14),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        f.detail!,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        color: f.type.color,
                        borderRadius: BorderRadius.circular(14),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _animatedMove(f.position, 18.5);
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.near_me_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '지도에서 보기',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            final idx = kFacilities.indexOf(f);
                            if (idx >= 0) _hiddenFacilityIdx.add(idx);
                          });
                        },
                        icon: const Icon(
                          Icons.visibility_off_rounded,
                          size: 14,
                          color: Colors.grey,
                        ),
                        label: const Text(
                          '이 마커 지도에서 숨기기',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 외부 지도 ───

  // ─── Windows 폴백 ───

  Widget _buildDesktopFallback(Color primary, bool isDark) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.map_rounded, size: 72, color: primary),
        ),
        const SizedBox(height: 24),
        Text(
          '캠퍼스 지도',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '지도는 모바일 앱에서 이용 가능합니다',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '아래 [건물 안내] 탭에서 층별 시설 정보를 확인하세요',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () => _tabController.animateTo(1),
          icon: const Icon(Icons.business),
          label: const Text(
            '건물 안내 보기',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    ),
  );
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
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '부속시설 편집',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setLocalState(
                        () => tempOrder.setAll(
                          0,
                          List.generate(kFacilities.length, (i) => i),
                        ),
                      ),
                      child: Text(
                        '초기화',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _facilityOrder = List.from(tempOrder));
                        _saveFavoritesAndCategories();
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        '완료',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: tempOrder.length,
                  onReorder: (o, n) {
                    setLocalState(() {
                      if (n > o) n--;
                      final t = tempOrder.removeAt(o);
                      tempOrder.insert(n, t);
                    });
                  },
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
                      title: Text(
                        displayedName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        f.type.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _hiddenFacilityIdx.contains(idx)
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: _hiddenFacilityIdx.contains(idx)
                                  ? Colors.redAccent
                                  : (isDark ? Colors.white54 : Colors.black54),
                              size: 20,
                            ),
                            onPressed: () {
                              setLocalState(() {
                                setState(() {
                                  if (_hiddenFacilityIdx.contains(idx)) {
                                    _hiddenFacilityIdx.remove(idx);
                                  } else {
                                    _hiddenFacilityIdx.add(idx);
                                  }
                                });
                              });
                            },
                          ),
                          Icon(
                            Icons.drag_handle_rounded,
                            color: isDark ? Colors.white38 : Colors.black26,
                          ),
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
}

// ───────────────────────────────────────── 지도 레이블 마커 ──
// 건물 이름처럼 생긴 말풍선 라벨 (하단에 작은 삼각형 pointer)

/// 캠퍼스맵 상단 그룹 탭 — 아이콘과 라벨을 가로로 붙여 높이를 낮게 유지한다.
class _MapGroupTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MapGroupTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 34,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  final String text;
  final Color color;
  final bool large;
  const _MapLabel({
    required this.text,
    required this.color,
    required this.large,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: large ? 10 : 7,
            vertical: large ? 5 : 3,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(large ? 10 : 7),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: large ? 11 : 9,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        CustomPaint(
          painter: _TrianglePainter(color: color),
          size: const Size(8, 5),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────── 시설 핀 마커 ──

class _FacilityPin extends StatelessWidget {
  final FacilityType type;
  const _FacilityPin({required this.type});

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: type.color,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
      boxShadow: [
        BoxShadow(
          color: type.color.withValues(alpha: 0.4),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: Icon(type.icon, color: Colors.white, size: 17),
  );
}

// ─────────────────────────── 필터 칩 ──

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active, isDark;
  final Color color;
  final VoidCallback onTap;
  final bool small;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.isDark,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: small ? 9 : 11,
        vertical: small ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: active
            ? color
            : (isDark
                  ? Colors.grey.shade900.withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.95)),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.0)
              : (isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.08)),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: small ? 12 : 13,
            color: active ? Colors.white : (isDark ? Colors.white70 : color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: active
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────── 건물 리스트 카드 ──

class _BuildingCard extends StatelessWidget {
  final BuildingData building;
  final bool isDark;
  final VoidCallback onTap;
  final String? customName;
  const _BuildingCard({
    required this.building,
    required this.isDark,
    required this.onTap,
    this.customName,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: building.color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  building.shortName.length > 2
                      ? building.shortName.substring(0, 2)
                      : building.shortName,
                  style: TextStyle(
                    color: building.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customName ?? building.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    building.description,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white38 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.layers_rounded,
                        size: 12,
                        color: building.color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '지상 ${building.aboveGroundFloorCount}층',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: building.color,
                        ),
                      ),
                    ],
                  ),
                  if (building.floors.any(
                    (f) => f.floor is int && (f.floor as int) < 0,
                  ))
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_downward_rounded,
                          size: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'B${building.floors.where((f) => f.floor is int && (f.floor as int) < 0).length} 지하층 있음',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────── 줌/탑바 버튼 ──

class _PillZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;
  const _PillZoomBtn({
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (isDark ? Colors.white70 : Colors.black54);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(icon, color: fg, size: 20),
      ),
    );
  }
}

class _TopBarBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color? activeColor;
  final bool isDark;
  const _TopBarBtn({
    required this.icon,
    required this.active,
    required this.onTap,
    this.activeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: active
            ? (activeColor ?? (isDark ? Colors.white : Colors.black))
                  .withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(100), // Circle pill
      ),
      child: Icon(
        icon,
        size: 20,
        color: active
            ? (activeColor ?? (isDark ? Colors.white : Colors.black87))
            : (isDark ? Colors.white60 : Colors.black54),
      ),
    ),
  );
}

// ──────────────────────────────────────────────── 검색 모델 ──

class _SearchItem {
  final String name;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SearchItem({
    required this.name,
    required this.sub,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _ScreenshotShareDialog extends StatefulWidget {
  final String name;
  final List<LatLng> trail;
  final double dist;

  const _ScreenshotShareDialog({
    required this.name,
    required this.trail,
    required this.dist,
  });

  @override
  State<_ScreenshotShareDialog> createState() => _ScreenshotShareDialogState();
}

class _ScreenshotShareDialogState extends State<_ScreenshotShareDialog> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    if (widget.trail.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bounds = LatLngBounds.fromPoints(widget.trail);

    return AlertDialog(
      title: Text(
        '산책로 공유',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          if (_isGenerating)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 300,
                height: 300,
                child: Screenshot(
                  controller: _screenshotController,
                  child: Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCameraFit: CameraFit.bounds(
                            bounds: bounds,
                            padding: const EdgeInsets.all(40),
                          ),
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.knue.knuemate',
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: widget.trail,
                                strokeWidth: 5,
                                color: Colors.blueAccent.withValues(alpha: 0.8),
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                width: 24,
                                height: 24,
                                point: widget.trail.first,
                                child: const Icon(
                                  Icons.circle,
                                  color: Colors.green,
                                  size: 16,
                                ),
                              ),
                              Marker(
                                width: 24,
                                height: 24,
                                point: widget.trail.last,
                                child: const Icon(
                                  Icons.flag_circle_rounded,
                                  color: Colors.redAccent,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '한국교원대학교 · ${widget.name}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isGenerating ? null : () => Navigator.pop(context),
          child: Text(
            '취소',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
          ),
        ),
        TextButton(
          onPressed: _isGenerating
              ? null
              : () async {
                  setState(() => _isGenerating = true);
                  await Future.delayed(const Duration(milliseconds: 300));
                  try {
                    final image = await _screenshotController.capture();
                    if (image != null) {
                      await SharePlus.instance.share(
                        ShareParams(
                          files: [
                            XFile.fromData(
                              image,
                              mimeType: 'image/png',
                              name: '${widget.name}_trail.png',
                            ),
                          ],
                          text:
                              '📍 산책로: ${widget.name}\n경유지 ${widget.trail.length}개\n── 한국교원대학교 캠퍼스맵 앱에서 공유 ──',
                        ),
                      );
                      if (context.mounted) Navigator.pop(context);
                    }
                  } catch (e) {
                    if (context.mounted) setState(() => _isGenerating = false);
                  }
                },
          child: const Text(
            '공유하기',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserLocationMarker extends StatefulWidget {
  final Color primary;
  const _UserLocationMarker({required this.primary});

  @override
  State<_UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends State<_UserLocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double pulse = _controller.value;
        const markerColor = Colors.pinkAccent; // 고채도 핑크레드로 가시성 극대화
        return Stack(
          alignment: Alignment.center,
          children: [
            // 외각 파동 효과
            Container(
              width: 24 + (40 * pulse),
              height: 24 + (40 * pulse),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: markerColor.withValues(alpha: 0.4 * (1 - pulse)),
              ),
            ),
            // 메인 고양이 캐릭터
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: markerColor.withValues(alpha: 0.5),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                ],
                border: Border.all(color: markerColor, width: 2.5),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.pets_rounded, color: markerColor, size: 20),
            ),
          ],
        );
      },
    );
  }
}

class _CustomReorderableDragStartListener extends ReorderableDragStartListener {
  final Duration delay;
  // ignore: unused_element_parameter
  const _CustomReorderableDragStartListener({
    super.key,
    required super.child,
    required super.index,
    super.enabled, // ignore: unused_element_parameter
    this.delay = const Duration(milliseconds: 700), // ignore: unused_element_parameter
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(delay: delay, debugOwner: this);
  }
}

// ─── 건물 층별 안내 (어코디언 + 정렬 토글) ───

class _BuildingFloorSection extends StatefulWidget {
  final BuildingData building;
  final bool isDark;
  final ScrollController ctrl;
  final VoidCallback onHide;

  const _BuildingFloorSection({
    required this.building,
    required this.isDark,
    required this.ctrl,
    required this.onHide,
  });

  @override
  State<_BuildingFloorSection> createState() => _BuildingFloorSectionState();
}

class _BuildingFloorSectionState extends State<_BuildingFloorSection> {
  bool _sortAscending = false; // 기본: 내림차순 (높은 층 우선)
  final Set<int> _expandedIndices = {}; // 펼쳐진 층의 floors 인덱스

  @override
  Widget build(BuildContext context) {
    final b = widget.building;
    final isDark = widget.isDark;

    // 정렬된 층 인덱스 목록 생성
    final indexedFloors = List.generate(b.floors.length, (i) => i);
    final sortedIndices = _sortAscending
        ? indexedFloors
        : indexedFloors.reversed.toList();

    return Expanded(
      child: Column(
        children: [
          // 헤더 행: 층별 안내 타이틀 + 정렬 토글
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: b.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '층별 안내',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                // 정렬 토글 버튼
                GestureDetector(
                  onTap: () => setState(() {
                    _sortAscending = !_sortAscending;
                    _expandedIndices.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: b.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: b.color.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _sortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 11,
                          color: b.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _sortAscending ? '오름차순' : '내림차순',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: b.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 층 목록 (어코디언 스타일)
          Expanded(
            child: ListView.separated(
              controller: widget.ctrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: sortedIndices.length + 1, // +1: 숨기기 버튼
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, listIdx) {
                // 마지막 아이템: 숨기기 버튼
                if (listIdx == sortedIndices.length) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: widget.onHide,
                      icon: const Icon(
                        Icons.visibility_off_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                      label: const Text(
                        '이 마커 지도에서 숨기기',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  );
                }

                final floorIdx = sortedIndices[listIdx];
                final f = b.floors[floorIdx];
                final isExpanded = _expandedIndices.contains(floorIdx);
                final hasRooms = f.rooms.isNotEmpty;

                final floorLabel = f.floor is int
                    ? (f.floor < 0
                          ? 'B${(f.floor as int).abs()}'
                          : '${f.floor}F')
                    : f.floor.toString();

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: isExpanded
                        ? Border.all(
                            color: b.color.withValues(alpha: 0.35),
                            width: 1.2,
                          )
                        : Border.all(color: Colors.transparent),
                  ),
                  child: Column(
                    children: [
                      // 층 행 (탭 가능)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: hasRooms
                            ? () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedIndices.remove(floorIdx);
                                  } else {
                                    _expandedIndices.add(floorIdx);
                                  }
                                });
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              // 층 배지
                              Container(
                                width: 50,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isExpanded
                                      ? b.color.withValues(alpha: 0.2)
                                      : b.color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  floorLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: b.color,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 호실 수 / 비어있음 텍스트
                              Expanded(
                                child: Text(
                                  hasRooms ? '${f.rooms.length}개 호실' : '정보 없음',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: hasRooms
                                        ? (isDark
                                              ? Colors.white70
                                              : Colors.black54)
                                        : (isDark
                                              ? Colors.white30
                                              : Colors.black26),
                                  ),
                                ),
                              ),
                              // 펼치기 화살표
                              if (hasRooms)
                                AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 20,
                                    color: isExpanded
                                        ? b.color
                                        : (isDark
                                              ? Colors.white38
                                              : Colors.black26),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // 호실 칩 (펼쳐졌을 때만 표시)
                      if (isExpanded && hasRooms)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: f.rooms
                                .map(
                                  (r) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: b.color.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: b.color.withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Text(
                                      r,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.9,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.8,
                                              ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
