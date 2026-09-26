import 'dart:async';
import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'building_data.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screenshot/screenshot.dart';
import 'constants.dart';
import 'admin_staff_data.dart';
import 'admin_auth_service.dart';
import 'map_facility_service.dart';
import 'staff_contacts_screen.dart';
import 'housing_screen.dart';

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
  late final TabController _tabController;

  bool _searchOpen = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  // 건물/시설/카테고리 순서 상태 (null이면 기본 순서)
  List<int> _buildingOrder = [];
  List<int> _facilityOrder = [];
  List<String> _categoryOrder = ['교육', '편의', '이동', '시설'];

  // 숨김 목록
  final Set<int> _hiddenBuildingIdx = {};
  final Set<int> _hiddenFacilityIdx = {};

  // Custom Names & Favorites
  Map<int, String> _customBuildingNames = {};
  Map<int, String> _customFacilityNames = {};


  // 탭 7개(지도·건물·부속시설·산책로·과사무실·행정·강의실)를 3그룹으로 접었다.
  // 기능은 그대로 두고 "들어가는 문"만 줄인 것 — 각 그룹 안에서 세그먼트로 나눈다.
  //   0 지도 / 1 장소(건물·부속시설·강의실) / 2 연락처(과 사무실·행정)
  int _placeSegment = 0; // 0 건물, 1 부속시설, 2 강의실

  @override
  void initState() {
    super.initState();
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
    _loadFavoritesAndCategories();
    // 백그라운드 Firebase 건물 동기화가 화면이 열려있는 동안 끝나도 반영되도록 구독.
    kBuildingsRevision.addListener(_onBuildingsUpdated);
  }

  void _onBuildingsUpdated() {
    if (mounted) setState(() {});
  }

  /// 3D 지도의 개발자 모드(편집 도구) 켜기. 캠퍼스맵에 끼운 3D 지도에는
  /// 자체 상단바가 없어서 비밀번호를 넣는 입구가 여기다. 끄기는 지도 위
  /// 배너의 [종료]로 한다.
  Future<void> _toggleDevMode(bool isDark) async {
    if (AdminAuthService.isAdmin.value) {
      showToast(context, "이미 개발자 모드예요 — 끄려면 지도 위 [종료]를 누르세요");
      return;
    }
    // 이 기기에 이미 권한이 있으면 비밀번호를 묻지 않는다.
    if (await AdminAuthService.refreshAdminStatus()) {
      if (!mounted) return;
      showToast(context, "개발자 모드 켜짐 — 지도의 편집 도구를 쓰세요");
      return;
    }
    if (!mounted) return;
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
    final typed = controller.text;
    controller.dispose();
    if (ok != true) return;
    // 맞는지는 서버가 판단한다 — 앱은 정답을 갖고 있지 않다.
    final result = await AdminAuthService.unlock(typed);
    if (!mounted) return;
    if (result == AdminUnlockResult.ok) {
      showToast(context, "개발자 모드 켜짐 — 지도의 편집 도구를 쓰세요");
    } else {
      showToast(context, result.message);
    }
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

  @override
  void dispose() {
    kBuildingsRevision.removeListener(_onBuildingsUpdated);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 장소 탭·검색에서 "지도에서 보기": 3D 지도 탭으로 넘어가 캠퍼스맵의
  /// 위도·경도 그대로 옮겨 간다(그 자리 건물을 고른다).
  void _animatedMove(LatLng target, double zoom) {
    _tabController.animateTo(0);
    _housingFocus.value = HousingFocusRequest.at(target.latitude, target.longitude, ++_focusSeq);
  }

  /// 3D 지도(HousingScreen)에 보내는 이동 요청.
  final ValueNotifier<HousingFocusRequest?> _housingFocus = ValueNotifier(null);
  int _focusSeq = 0;

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
                // 캠퍼스맵과 자취방 지도를 3D 지도 하나로 합쳤다. 캠퍼스 모드로
                // 인문과학관에서 시작하고, 위쪽 [캠퍼스]/[자취방]으로 오간다.
                HousingScreen(
                  isEmbedded: true,
                  campusMode: true,
                  focusRequests: _housingFocus,
                ),
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
                      // 숨은 개발자 모드 진입로 — 3D 지도의 편집 도구를 켠다.
                      ValueListenableBuilder<bool>(
                        valueListenable: AdminAuthService.isAdmin,
                        builder: (context, isAdmin, _) => _TopBarBtn(
                          icon: isAdmin
                              ? Icons.build_circle_rounded
                              : Icons.build_circle_outlined,
                          active: isAdmin,
                          isDark: isDark,
                          activeColor: Colors.redAccent,
                          onTap: () => _toggleDevMode(isDark),
                        ),
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

  // ─── 필터 바 (카테고리) ───

  // ─── 줌 컨트롤 ───

  // ─── 산책로 패널 ───

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

// ─────────────────────────── 시설 핀 마커 ──

// ─────────────────────────── 필터 칩 ──

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
                          // ODbL 출처 표기는 지도가 보이는 모든 곳에 있어야 한다.
                          const SimpleAttributionWidget(
                            source: Text('© OpenStreetMap 기여자'),
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
