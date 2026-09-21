// OpenStreetMap에서 캠퍼스 일대 도로 중심선을 받아 에셋으로 굽는다.
//
//   node tool/fetch_osm_roads.js
//   → assets/housing/campus_roads.json
//
// ## 왜 캡처 추적 대신 OSM인가
//
// 포장면을 캡처에서 **면으로** 떠내던 방식은 천장이 있었다. 충실도를 올리면
// 가장자리가 굽고, 곧게 펴면 길이 제자리를 벗어난다(IoU 91%→80%). 래스터
// 분류의 경계를 아무리 다듬어도 "지도다운 도로"가 안 나온다.
//
// 실제 지도는 도로를 면으로 그리지 않는다. **중심선을 굵기로 긋는다.**
// 그래야 양 가장자리가 정확히 평행하고 교차점이 깔끔하다. OSM은 그 중심선을
// 사람이 측량해 그려 둔 것이라 애초에 곧다.
//
// 정합 확인: OSM 도로 점이 우리 교내 건물 안에 떨어지는 비율 0.6%
// (2m 보정 시 0.1%). 좌표계가 서로 맞는다.
//
// ## 라이선스
//
// OSM 데이터는 ODbL이다. 앱에 "© OpenStreetMap 기여자" 표기가 **반드시**
// 있어야 한다(자취방 지도 화면에 표시한다).

const fs = require('fs');
const path = require('path');

// 우리 평면 좌표계 원점 — tool/fetch_vworld.js와 같아야 한다.
const ORIGIN = { lon: 127.3544, lat: 36.6092 };
const M_PER_DEG_LAT = 111320;
const M_PER_DEG_LON = 111320 * Math.cos((ORIGIN.lat * Math.PI) / 180);

// 캠퍼스 + 원룸촌을 덮는 범위.
const BBOX = [36.604, 127.351, 36.616, 127.364]; // south, west, north, east

/// 도로 종류 → 그릴 폭(m)과 계층.
///
/// 폭은 캡처에서 실제 도로 폭을 재어 맞췄다. 계층(rank)은 겹칠 때
/// 어느 것을 위에 그릴지 정한다 — 큰 길이 위로 온다.
const CLASS = {
  secondary: { w: 11.0, rank: 5, kind: 'major' },
  primary: { w: 12.0, rank: 5, kind: 'major' },
  tertiary: { w: 9.0, rank: 4, kind: 'major' },
  residential: { w: 7.0, rank: 3, kind: 'road' },
  unclassified: { w: 7.0, rank: 3, kind: 'road' },
  living_street: { w: 6.0, rank: 3, kind: 'road' },
  service: { w: 4.5, rank: 2, kind: 'road' },
  track: { w: 3.5, rank: 1, kind: 'path' },
  pedestrian: { w: 5.0, rank: 2, kind: 'walk' },
  footway: { w: 2.6, rank: 1, kind: 'walk' },
  path: { w: 2.2, rank: 1, kind: 'walk' },
  steps: { w: 2.2, rank: 1, kind: 'steps' },
};

const QUERY = `[out:json][timeout:90];
way["highway"](${BBOX.join(',')});
out geom;`;

async function main() {
  const res = await fetch('https://overpass-api.de/api/interpreter', {
    method: 'POST',
    headers: {
      // User-Agent가 없으면 406으로 거절당한다.
      'User-Agent': 'knue-mate/1.0 (campus map build tool)',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'data=' + encodeURIComponent(QUERY),
  });
  if (!res.ok) throw new Error(`Overpass ${res.status}`);
  const data = await res.json();

  const roads = [];
  let skipped = 0;
  for (const el of data.elements) {
    if (el.type !== 'way' || !el.geometry) continue;
    const tag = el.tags || {};
    const cls = CLASS[tag.highway];
    if (!cls) {
      skipped++;
      continue;
    }
    // 공사중인 길은 그리지 않는다.
    if (tag.highway === 'construction') continue;

    const pts = el.geometry.map((g) => [
      +(((g.lon - ORIGIN.lon) * M_PER_DEG_LON).toFixed(1)),
      +(((ORIGIN.lat - g.lat) * M_PER_DEG_LAT).toFixed(1)),
    ]);
    // 같은 점이 이어지는 구간을 접는다.
    const dedup = [pts[0]];
    for (const p of pts.slice(1)) {
      const q = dedup[dedup.length - 1];
      if (Math.abs(p[0] - q[0]) > 0.05 || Math.abs(p[1] - q[1]) > 0.05) {
        dedup.push(p);
      }
    }
    if (dedup.length < 2) continue;

    roads.push({
      k: cls.kind,
      w: cls.w,
      r: cls.rank,
      ...(tag.name ? { n: tag.name } : {}),
      ...(tag.tunnel === 'yes' ? { tunnel: 1 } : {}),
      pts: dedup,
    });
  }

  roads.sort((a, b) => a.r - b.r); // 낮은 계층부터 → 큰 길이 위에 그려진다

  const out = {
    note:
      'OpenStreetMap 도로 중심선(ODbL). tool/fetch_osm_roads.js로 생성. '
      + '앱에 "© OpenStreetMap 기여자" 표기가 반드시 필요하다.',
    attribution: '© OpenStreetMap 기여자',
    license: 'ODbL 1.0',
    origin: ORIGIN,
    roads,
  };
  const file = path.join('assets', 'housing', 'campus_roads.json');
  fs.writeFileSync(file, JSON.stringify(out));
  const pts = roads.reduce((a, r) => a + r.pts.length, 0);
  const byKind = {};
  for (const r of roads) byKind[r.k] = (byKind[r.k] || 0) + 1;
  console.log(
    `→ ${file}  ${roads.length}개 / ${pts}점 / ` +
      `${(fs.statSync(file).size / 1024).toFixed(0)} KB`
  );
  console.log('  종류별:', JSON.stringify(byKind));
  console.log('  태그가 없어 건너뛴 way:', skipped);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
