import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'constants.dart';

class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key});

  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  late TabController _tabController;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // WebView는 Android/iOS에서만 지원
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      _initWebView();
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() {
            _isLoading = false;
            _hasError = false;
          }),
          onWebResourceError: (error) => setState(() {
            _isLoading = false;
            _hasError = true;
          }),
          onNavigationRequest: (request) {
            // 외부 링크는 url_launcher로 열기
            if (!request.url.contains('map.kakao.com') &&
                !request.url.contains('dapi.kakao.com') &&
                !request.url.startsWith('about:')) {
              launchUrl(Uri.parse(request.url),
                  mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(
        'https://map.kakao.com/?urlX=14168527&urlY=4393800&urlLevel=4',
      ));
  }

  Future<void> _openInExternalApp() async {
    final uri = Uri.parse(
      'https://map.kakao.com/link/map/한국교원대학교,36.609283,127.359147',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openGoogleMaps() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=한국교원대학교',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, primaryColor, child) {
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F4FF),
          appBar: AppBar(
            backgroundColor: primaryColor,
            elevation: 0,
            title: const Text(
              '🗺️ 캠퍼스맵',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.open_in_new, color: Colors.white),
                tooltip: '지도 앱에서 열기',
                onPressed: _openInExternalApp,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: '🗺️ 지도'),
                Tab(text: '🏛️ 건물 안내'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildMapTab(primaryColor, isDark),
              _buildBuildingGuideTab(primaryColor, isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapTab(Color primaryColor, bool isDark) {
    // Windows/Linux/macOS: WebView 미지원 → 안내 UI
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.map_rounded, size: 72, color: primaryColor),
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
            const SizedBox(height: 8),
            Text(
              '데스크톱에서는 외부 지도 앱으로 확인하세요',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _openInExternalApp,
              icon: const Icon(Icons.map),
              label: const Text('카카오맵으로 보기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFE000),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openGoogleMaps,
              icon: const Icon(Icons.travel_explore),
              label: const Text('구글맵으로 보기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4285F4),
                side: const BorderSide(color: Color(0xFF4285F4)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Android/iOS: WebView 표시
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          Container(
            color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F4FF),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  const SizedBox(height: 16),
                  Text(
                    '캠퍼스 지도를 불러오는 중...',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_hasError)
          Container(
            color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F4FF),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    '지도를 불러올 수 없습니다\n인터넷 연결을 확인해주세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _hasError = false;
                      });
                      _controller.reload();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openInExternalApp,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('외부 앱으로 보기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(color: primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 외부 앱 열기 플로팅 버튼
        Positioned(
          bottom: 24,
          right: 16,
          child: Column(
            children: [
              _buildFab(
                icon: Icons.map,
                label: '카카오맵',
                color: const Color(0xFFFFE000),
                textColor: Colors.black,
                onTap: _openInExternalApp,
              ),
              const SizedBox(height: 10),
              _buildFab(
                icon: Icons.travel_explore,
                label: '구글맵',
                color: const Color(0xFF4285F4),
                textColor: Colors.white,
                onTap: _openGoogleMaps,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFab({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingGuideTab(Color primaryColor, bool isDark) {
    final buildings = [
      _BuildingInfo('다정관', '행정학부, 교육정책전문대학원', Icons.business, Colors.blue, '36.613286,127.359914'),
      _BuildingInfo('다감관', '초등교육과, 유아교육과', Icons.school, Colors.purple, '36.614016,127.359718'),
      _BuildingInfo('종합교육관', '강의실, 대형 강의실', Icons.menu_book, Colors.teal, '36.610537,127.361035'),
      _BuildingInfo('인문과학관', '인문 계열 학과', Icons.history_edu, Colors.orange, '36.610517,127.360008'),
      _BuildingInfo('자연과학관', '자연 계열 학과', Icons.science, Colors.green, '36.608424,127.361631'),
      _BuildingInfo('융합과학관', '융합 교육', Icons.biotech, Colors.cyan, '36.609173,127.361614'),
      _BuildingInfo('응용과학관', '응용 계열 학부', Icons.calculate, Colors.indigo, '36.607976,127.362114'),
      _BuildingInfo('호연관', '강의실', Icons.class_, Colors.brown, '36.609509,127.358781'),
      _BuildingInfo('미래도서관', '도서관, 열람실', Icons.local_library, Colors.deepPurple, '36.609283,127.359147'),
      _BuildingInfo('학생회관', '학생식당, 편의시설', Icons.store, Colors.red, '36.608378,127.359853'),
      _BuildingInfo('기숙사 식당', '기숙사생 전용 식당', Icons.restaurant, Colors.amber, '36.612763,127.360502'),
      _BuildingInfo('대학본부', '행정처, 총장실', Icons.account_balance, Colors.blueGrey, '36.608583,127.357278'),
      _BuildingInfo('복지관', '학생 복지 시설', Icons.people, Colors.pink, '36.612863,127.359115'),
      _BuildingInfo('교원문화관', '공연장, 문화공간', Icons.theater_comedy, Colors.deepOrange, '36.607609,127.358611'),
      _BuildingInfo('미술관', '미술교육과', Icons.palette, Colors.orange, '36.607686,127.360534'),
      _BuildingInfo('음악관', '음악교육과', Icons.music_note, Colors.purple, '36.607311,127.361410'),
      _BuildingInfo('버스정류장', '정문 버스환승지', Icons.directions_bus, Colors.blue, '36.608214,127.358542'),
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: buildings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final b = buildings[index];
        return _BuildingCard(
          info: b,
          primaryColor: primaryColor,
          isDark: isDark,
          onTap: () async {
            final uri = Uri.parse(
              'https://map.kakao.com/link/map/${Uri.encodeComponent(b.name)},${b.coordinates}',
            );
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        );
      },
    );
  }
}

class _BuildingInfo {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String coordinates;

  const _BuildingInfo(
    this.name,
    this.description,
    this.icon,
    this.color,
    this.coordinates,
  );
}

class _BuildingCard extends StatelessWidget {
  final _BuildingInfo info;
  final Color primaryColor;
  final bool isDark;
  final VoidCallback onTap;

  const _BuildingCard({
    required this.info,
    required this.primaryColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: info.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(info.icon, color: info.color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      info.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
