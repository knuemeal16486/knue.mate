import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'constants.dart';
import 'housing_model.dart';

const LatLng _knueCenter = LatLng(36.6093, 127.3585);

/// 자취방 구하기 화면 — 지도·목록·월세 레이아웃만 갖춘 셸.
/// 실제 매물 데이터(Firestore 등)는 아직 연결하지 않아 [_listings]는 항상 비어 있다.
/// 나중에 데이터가 들어오면 지도 마커·목록·평균 월세가 자연스럽게 채워지는 구조.
class HousingScreen extends StatefulWidget {
  const HousingScreen({super.key});

  @override
  State<HousingScreen> createState() => _HousingScreenState();
}

class _HousingScreenState extends State<HousingScreen> {
  final List<HousingListing> _listings = const [];

  int? get _averageRent {
    if (_listings.isEmpty) return null;
    final total = _listings.fold<int>(0, (sum, l) => sum + l.monthlyRent);
    return total ~/ _listings.length;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColor,
      builder: (context, color, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: const Text("자취방 구하기"),
            backgroundColor: color,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Column(
            children: [
              _buildMap(),
              _buildRentSummary(color, isDark),
              Expanded(child: _buildListingList(isDark)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMap() {
    return SizedBox(
      height: 220,
      child: FlutterMap(
        options: const MapOptions(
          initialCenter: _knueCenter,
          initialZoom: 15.5,
          minZoom: 13.0,
          maxZoom: 18.0,
          interactionOptions: InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.knue.knuemate',
          ),
          MarkerLayer(
            markers: _listings
                .map(
                  (l) => Marker(
                    point: l.position,
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.home_rounded, color: Colors.redAccent),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRentSummary(Color color, bool isDark) {
    final avg = _averageRent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, color: color, size: 22),
          const SizedBox(width: 10),
          Text(
            "평균 월세",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const Spacer(),
          Text(
            avg != null ? "$avg만원" : "정보 없음",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: avg != null ? color : (isDark ? Colors.white38 : Colors.black38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListingList(bool isDark) {
    if (_listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.apartment_outlined,
              size: 40,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              "등록된 자취방이 아직 없어요",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "곧 추가될 예정이에요",
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }
    // 실제 데이터가 붙으면 여기서 ListView.builder로 매물 카드를 그린다.
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _listings.length,
      itemBuilder: (context, index) {
        final listing = _listings[index];
        return ListTile(
          title: Text(listing.name),
          subtitle: Text("${listing.monthlyRent}만원 · ${listing.landlordPhone}"),
        );
      },
    );
  }
}
