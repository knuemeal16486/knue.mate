// VWorld에서 교원대 일대의 지적(부지)·건물·도로를 받아 앱 에셋으로 굽는다.
//
// 런타임에 API를 부르지 않고 미리 받아 두는 이유:
//  - 지도를 열 때마다 네트워크를 기다리지 않는다
//  - API 키가 앱에 들어가지 않는다 (키는 이 스크립트에서만 쓴다)
//  - 쿼터·장애에 영향받지 않는다
//
// 사용법: VWORLD_KEY=... node tool/fetch_vworld.js
const fs = require('fs');

const KEY = process.env.VWORLD_KEY;
if (!KEY) { console.error('VWORLD_KEY 환경변수가 필요합니다.'); process.exit(1); }

// 원룸촌 + 교원대 캠퍼스 전체.
const BBOX = { minX: 127.3470, minY: 36.6030, maxX: 127.3670, maxY: 36.6160 };

// 평면 좌표 원점 — 원룸촌 한복판(월탄1길·월탄3길 부근). 여기가 (0,0)이 된다.
const ORIGIN = { lon: 127.3544, lat: 36.6092 };

// 위경도 → 미터. 이 정도 좁은 범위에서는 등거리 근사로 충분하다.
const M_PER_DEG_LAT = 111320;
const M_PER_DEG_LON = 111320 * Math.cos(ORIGIN.lat * Math.PI / 180);
const toLocal = ([lon, lat]) => [
  +((lon - ORIGIN.lon) * M_PER_DEG_LON).toFixed(1),
  // 화면 좌표계와 맞추려고 남쪽을 +y로 둔다.
  +((ORIGIN.lat - lat) * M_PER_DEG_LAT).toFixed(1),
];

async function fetchAll(layer) {
  const out = [];
  for (let page = 1; ; page++) {
    const url = new URL('https://api.vworld.kr/req/data');
    url.search = new URLSearchParams({
      service: 'data', request: 'GetFeature', version: '2.0',
      data: layer, format: 'json',
      // ⚠️ VWorld의 size 상한은 1000이다. 넘기면 INVALID_RANGE로 거절당한다.
      size: '1000', page: String(page),
      geomFilter: `BOX(${BBOX.minX},${BBOX.minY},${BBOX.maxX},${BBOX.maxY})`,
      crs: 'EPSG:4326', key: KEY,
    });
    const res = await fetch(url);
    const json = await res.json();
    const r = json.response;
    if (r.status !== 'OK') throw new Error(`${layer}: ${JSON.stringify(r.error)}`);
    out.push(...r.result.featureCollection.features);
    const total = Number(r.page.total);
    process.stderr.write(`  ${layer} ${page}/${total} (${out.length}건)\n`);
    if (page >= total) break;
  }
  return out;
}

const outerRings = g =>
  g.type === 'Polygon' ? [g.coordinates[0]]
  : g.type === 'MultiPolygon' ? g.coordinates.map(p => p[0])
  : [];
const lineStrings = g =>
  g.type === 'LineString' ? [g.coordinates]
  : g.type === 'MultiLineString' ? g.coordinates
  : [];

// 지적도 jibun 끝에 붙는 지목(land category) 한 글자를 용도 묶음으로 바꾼다.
// 네이버지도가 깔끔해 보이는 건 결국 이 용도별 면 구분 덕분이다.
const JIMOK_GROUP = {
  '학': 'campus',                                  // 학교용지 — 교원대 부지
  '도': 'road', '철': 'road',
  '천': 'water', '구': 'water', '유': 'water', '양': 'water', '수': 'water',
  '전': 'farm', '답': 'farm', '과': 'farm', '목': 'farm',
  '임': 'forest',
  '공': 'park', '체': 'park', '원': 'park', '묘': 'park',
  '대': 'built', '장': 'built', '차': 'built', '주': 'built',
  '창': 'built', '종': 'built', '사': 'built',
};
function jimokOf(jibun) {
  if (!jibun) return null;
  // "57-3학", "6 학" 처럼 공백이 있기도 없기도 하다. 끝의 한글만 뽑는다.
  const m = String(jibun).trim().match(/[가-힣]+$/);
  return m ? m[0][0] : null;
}

(async () => {
  console.error('지적(부지) 받는 중…');
  const parcels = await fetchAll('LP_PA_CBND_BUBUN');
  console.error('건물 받는 중…');
  const bFeatures = await fetchAll('LT_C_SPBD');
  console.error('도로 받는 중…');
  const rFeatures = await fetchAll('LT_L_MOCTLINK');

  // ── 지적 → 용도별 면 ──
  const landuse = [];
  const jimokCount = {};
  for (const f of parcels) {
    const p = f.properties || {};
    const jimok = jimokOf(p.jibun);
    const group = JIMOK_GROUP[jimok];
    jimokCount[jimok || '?'] = (jimokCount[jimok || '?'] || 0) + 1;
    if (!group) continue;
    // 대지는 건물이 그 위에 그려지므로 면까지 칠하면 지저분해진다.
    if (group === 'built') continue;
    for (const ring of outerRings(f.geometry)) {
      const pts = ring.map(toLocal);
      if (pts.length < 3) continue;
      landuse.push({ g: group, ring: pts });
    }
  }

  // ── 건물 ──
  const buildings = [];
  for (const f of bFeatures) {
    const p = f.properties || {};
    for (const ring of outerRings(f.geometry)) {
      const pts = ring.map(toLocal);
      if (pts.length < 3) continue;
      buildings.push({
        id: p.bd_mgt_sn || f.id,
        name: (p.buld_nm || '').trim() || null,
        floors: Math.max(1, parseInt(p.gro_flo_co || '1', 10) || 1),
        road: (p.rd_nm || '').trim() || null,
        no: (p.buld_no || '').trim() || null,
        ring: pts,
      });
    }
  }

  // ── 도로 ──
  const roads = [];
  for (const f of rFeatures) {
    for (const line of lineStrings(f.geometry)) {
      const pts = line.map(toLocal);
      if (pts.length < 2) continue;
      roads.push({ pts });
    }
  }

  const out = {
    note: 'VWorld(국토교통부) 지적·건물·도로를 원룸촌 기준 평면 좌표(m)로 변환. tool/fetch_vworld.js로 생성.',
    origin: ORIGIN,
    landuse, buildings, roads,
  };
  fs.mkdirSync('assets/housing', { recursive: true });
  fs.writeFileSync('assets/housing/campus_base.json', JSON.stringify(out));

  const byGroup = {};
  landuse.forEach(l => byGroup[l.g] = (byGroup[l.g] || 0) + 1);
  console.error(`완료: 부지 ${landuse.length}면 ${JSON.stringify(byGroup)}, 건물 ${buildings.length}, 도로 ${roads.length}`);
  console.error('지목 분포:', JSON.stringify(jimokCount));
})();
