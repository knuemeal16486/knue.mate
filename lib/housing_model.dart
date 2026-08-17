import 'package:latlong2/latlong.dart';

/// 자취방 매물 한 건. 학교 주변은 부동산보다 건물에 붙은 번호로 집주인과
/// 직거래하는 경우가 많아 [landlordPhone]을 핵심 필드로 둔다.
class HousingListing {
  final String id;
  final String name;
  final LatLng position;
  final int monthlyRent;
  final String landlordPhone;
  final String? memo;

  const HousingListing({
    required this.id,
    required this.name,
    required this.position,
    required this.monthlyRent,
    required this.landlordPhone,
    this.memo,
  });
}
