import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

/// 학생회 원룸 지도의 "준공연도" 표(출처: 충북 부동산정보조회 시스템,
/// 건축물 사용승인일 기준)를 그대로 옮긴 것. 사전이 이 표와 어긋나면 실패한다.
const Map<int, List<String>> _table = {
  1997: ['수정아파트 101-가동', '수정아파트 101-나동', '수정아파트 102동', '교원빌라 107동'],
  1998: ['교원빌라 106동', '교원빌라 109동', '교원빌라 101동', '교원빌라 102동', '교원빌라 103동', '교원빌라 105동', '교원빌라 110동'],
  1999: ['교원빌라 108동', '교원빌라 112동', '교원빌라 111동'],
  2001: ['서호아파트 101동', '서호아파트 102동', '드림빌라 B동', '드림빌라 A동', '원앙빌라'],
  2002: ['드림빌라 C동', '대현빌라 A동', '대현빌라 B동'],
  2004: ['드림빌라 D동', '드림빌라 E동'],
  2005: ['교원빌라 A동'],
  2008: ['삼성프리하우스'],
  2010: ['둥지빌', '청람드림빌 A동', '청람드림빌 B동', '청람드림빌 C동', '청람드림빌 D동', '교원학사', '성균관빌'],
  2011: ['새터빌', '대성빌', '어울림빌', '한마음빌', '그린빌라 A동', '에듀빌', '승방빌'],
  2012: ['파인빌', '교원빌라 113동', '화이트빌'],
  2013: ['다솜빌', '메이플빌', '보광빌', '원더빌', '부광빌', '초록빌', '자연빌', '가온빌'],
  2014: ['연송빌', '국보빌'],
  2015: ['에코빌', '더베이스', '하늘채', '등용문', '그린캐슬', '엘리트빌'],
  2016: ['행운빌', '연흥빌'],
  2017: ['프라임빌', '채움빌', '꿈터빌', '해오름빌', '글마루빌', '미소가', '위너스빌', '아우름빌'],
  2018: ['소망빌', '대원빌', '미래로빌'],
  2020: ['바우하우스 A동', '바우하우스 B동'],
};

void main() {
  test('원룸 지도 표의 모든 건물이 같은 준공연도로 찾아진다', () {
    for (final e in _table.entries) {
      for (final name in e.value) {
        expect(builtYearByName(name), e.key, reason: name);
      }
    }
  });

  test('개발자 모드에서 조금 다르게 적은 이름도 찾는다', () {
    expect(builtYearByName('어울림'), 2011); // 사전은 "어울림빌"
    expect(builtYearByName('청람드림빌 D'), 2010); // "…D동"
    expect(builtYearByName('가온빌 (늘품)'), 2013);
    expect(builtYearByName('원더빌(MAY)'), 2013);
    expect(builtYearByName('교원빌라101동'), 1998);
    expect(builtYearByName('수정아파트 101-가'), 1997);
  });

  test('지도 데이터에 다르게 적힌 이름도 같은 건물로 본다', () {
    expect(builtYearByName('대현빌 A'), 2002);
    expect(builtYearByName('대현빌 B'), 2002);
    expect(builtYearByName('둥지빌라'), 2010);
    expect(builtYearByName('프리하우스'), 2008);
    expect(builtYearByName('연흥빌'), 2016);
    expect(builtYearByName('서호e타운 101동'), 2001);
    expect(builtYearByName('서호e타운 102동'), 2001);
    for (final dong in ['101', '102', '103']) {
      expect(builtYearByName('태암수정아파트 $dong동'), 1997);
    }
    // 연도만 아는 건물은 사전 항목으로 잘못 이어 붙이지 않는다.
    expect(oneRoomByName('태암수정아파트 103동'), isNull);
  });

  test('모르는 이름·빈 이름은 null', () {
    expect(builtYearByName('HS 빌'), isNull);
    expect(builtYearByName('공사중'), isNull);
    expect(builtYearByName(''), isNull);
    expect(builtYearByName(null), isNull);
  });

  test('다듬은 이름끼리 겹치지 않는다(엉뚱한 건물의 연도가 붙지 않게)', () {
    final keys = kOneRoomNames.map((n) => normalizeOneRoomName(n.name)).toList();
    expect(keys.toSet().length, keys.length);
  });

  test('이름만 고친 수정 문서도 사전의 연도를 보여준다', () {
    const o = HousingBuildingOverride(buildingId: 'x', name: '가온빌', zone: HousingZone.hqPath);
    expect(o.toOneRoomName().builtYear, 2013);
    const typed = HousingBuildingOverride(buildingId: 'x', name: '가온빌', zone: HousingZone.hqPath, builtYear: 2014);
    expect(typed.toOneRoomName().builtYear, 2014, reason: '직접 적은 연도가 먼저');
  });
}
