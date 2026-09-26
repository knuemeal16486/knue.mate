import 'building_data.dart';
import 'housing_iso.dart' show BaseBuilding;
import 'housing_model.dart' show lonLatToHousingWorld;

// 캠퍼스맵에 들어 있던 교내 건물 정보(설명·층별 호실)를 3D 지도의 교내
// 건물에 이어 붙인다. 두 데이터는 따로 만들어져서 이름과 대략의 위치만 공통이다.

/// 이름 비교용: 띄어쓰기·괄호 설명을 뺀다.
String _norm(String s) =>
    s.replaceAll(RegExp(r'\(.*?\)'), '').replaceAll(RegExp(r'\s+'), '');

/// 층 이름: 1 → "1층", "B1" → "지하 1층", "1F" → "1층". 순수 함수 — 테스트 대상.
String floorLabel(dynamic floor) {
  if (floor is int) return floor < 0 ? '지하 ${-floor}층' : '$floor층';
  final s = floor.toString().trim().toUpperCase();
  if (s.startsWith('B') && int.tryParse(s.substring(1)) != null) return '지하 ${s.substring(1)}층';
  if (s.endsWith('F') && int.tryParse(s.substring(0, s.length - 1)) != null) {
    return '${s.substring(0, s.length - 1)}층';
  }
  return floor.toString();
}

/// 캠퍼스맵 건물(위도·경도 한 점)을 3D 지도의 교내 건물에 잇는다.
/// 결과: 3D 건물 id → 캠퍼스맵 건물 정보. 순수 함수 — 테스트 대상.
///
/// 캠퍼스맵 좌표는 건물 윤곽이 아니라 마커를 꽂은 **한 점**이라, 3D 지도의
/// 건물 안에 떨어지는 건 33개 중 7개뿐이고 대개 10~65m 떨어져 있다(2026-09
/// 확인). 좌표만으로 이으면 옆 건물에 붙는다(제2학생회관 → 제2대학 등).
/// 그래서 이름으로 먼저 맞추고(같은 이름 조각이 여럿이면 모두), 이름으로 못
/// 찾으면 좌표가 [maxMeters] 안에서 가장 가까운 교내 건물로 잇는다.
Map<String, BuildingData> matchCampusInfo(
  List<BaseBuilding> buildings,
  List<BuildingData> infos, {
  String? Function(BaseBuilding b)? nameOf,
  double maxMeters = 60,
}) {
  final campus = [for (final b in buildings) if (b.isCampus) b];
  String? name(BaseBuilding b) => nameOf?.call(b) ?? b.officialName;
  final out = <String, BuildingData>{};
  for (final info in infos) {
    final at = lonLatToHousingWorld(info.position.longitude, info.position.latitude);
    double dist(BaseBuilding b) => (b.center - at).distance;
    final key = _norm(info.name);
    final short = _norm(info.shortName);
    final exact = [
      for (final b in campus)
        if (name(b) case final n?)
          if (_norm(n) == key || _norm(n) == short) b,
    ];
    // "다감관 A동"·"다감관 B동"처럼 한 건물이 여러 동으로 나뉜 건 모든 동에 붙인다.
    final wings = [
      for (final b in campus)
        if (name(b) case final n?)
          if (key.length >= 2 && _norm(n).startsWith(key) && _norm(n) != key) b,
    ];
    final picks = <BaseBuilding>[];
    if (exact.isNotEmpty) {
      // 같은 이름이 여럿이면 한 건물을 모양대로 쪼갠 조각들이다(미래도서관을
      // 둘로 나눈 것처럼) — 어느 조각을 눌러도 같은 안내가 나오게 모두 붙인다.
      picks.addAll(exact);
    } else if (wings.isNotEmpty) {
      picks.addAll(wings);
    } else if (campus.isNotEmpty) {
      final near = campus.reduce((a, b) => dist(a) <= dist(b) ? a : b);
      if (dist(near) <= maxMeters) picks.add(near);
    }
    for (final p in picks) {
      out.putIfAbsent(p.id, () => info);
    }
  }
  return out;
}
