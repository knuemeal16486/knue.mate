#!/usr/bin/env node
/**
 * 이번 주 학생회관(MealSource.b) 식단을 www.knue.ac.kr 에서 직접 긁어
 * Firestore daily_meals 컬렉션에 cacheVersion:2 로 저장합니다.
 *
 * 사용법:
 *   1. Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성
 *   2. 다운로드한 JSON 파일을 scripts/serviceAccount.json 으로 저장
 *   3. npm install firebase-admin node-fetch cheerio
 *   4. node update_meal_cache.js
 */

const admin = require('firebase-admin');
const https = require('https');
const serviceAccount = require('./serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'knue-mate',
});

const db = admin.firestore();

function fetch(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

function parseHtml(html) {
  // data-day → (month, day) 매핑
  const dayMap = {};
  const thRe = /<th[^>]+data-day="(\d+)"[^>]*>[\s\S]*?<span>([\s\S]*?)<\/span>/g;
  let m;
  while ((m = thRe.exec(html)) !== null) {
    const idx = m[1];
    const dateMatch = m[2].match(/(\d+)\/(\d+)/);
    if (dateMatch) dayMap[idx] = { month: parseInt(dateMatch[1]), day: parseInt(dateMatch[2]) };
  }

  const mealKeys = ['breakfast', 'lunch', 'dinner'];
  const result = {};

  for (const [dayIdx, { month, day }] of Object.entries(dayMap)) {
    // 이번 주 해당 날짜의 연도 계산
    const now = new Date();
    const year = now.getFullYear();
    const pad = (n) => String(n).padStart(2, '0');
    const dateKey = `${year}-${pad(month)}-${pad(day)}`;
    const meals = { breakfast: [], lunch: [], dinner: [] };

    // tbody에서 data-day=N 인 td 추출 (최대 3개 행 = 조/중/석식)
    const tdRe = new RegExp(`<td data-day="${dayIdx}">[\\s\\S]*?</td>`, 'g');
    let rowIdx = 0;
    let tdMatch;
    while ((tdMatch = tdRe.exec(html)) !== null && rowIdx < 3) {
      const tdHtml = tdMatch[0];
      const liRe = /<li[^>]*>([\s\S]*?)<\/li>/g;
      let li;
      while ((li = liRe.exec(tdHtml)) !== null) {
        // 태그 제거, 줄 단위로 분리
        const text = li[1].replace(/<[^>]+>/g, '');
        const items = text.split(/[\r\n]/)
          .map((s) => s.trim().replace(/&amp;/g, '&'))
          .filter((s) => s.length > 0);
        meals[mealKeys[rowIdx]].push(...items);
      }
      rowIdx++;
    }

    result[dateKey] = meals;
  }

  return result;
}

async function run() {
  const now = new Date();
  const dayOfWeek = now.getDay() === 0 ? 7 : now.getDay();
  const monday = new Date(now);
  monday.setDate(now.getDate() - (dayOfWeek - 1));
  const pad = (n) => String(n).padStart(2, '0');
  const dateStr = `${monday.getFullYear()}${pad(monday.getMonth() + 1)}${pad(monday.getDate())}`;

  const url = `https://www.knue.ac.kr/www/selectDietInfoWebList.do?key=1960&siteSe=cafe&searchStdde=${dateStr}`;
  console.log(`스크래핑 URL: ${url}\n`);

  const html = await fetch(url);
  const meals = parseHtml(html);

  console.log('파싱 결과:');
  for (const [date, m] of Object.entries(meals).sort()) {
    const hasMeal = Object.values(m).some((v) => v.length > 0);
    if (hasMeal) {
      console.log(`\n  ${date}:`);
      for (const [type, items] of Object.entries(m)) {
        if (items.length) console.log(`    ${type}: ${items.join(' / ')}`);
      }
    }
  }

  console.log('\nFirestore 업로드 중...');
  const batch = db.batch();
  for (const [dateKey, mealData] of Object.entries(meals)) {
    const docId = `${dateKey}_b`;
    const ref = db.collection('daily_meals').doc(docId);
    batch.set(ref, {
      date: dateKey,
      source: 'b',
      meals: mealData,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      cacheVersion: 2,
    });
    console.log(`  저장: ${docId}`);
  }

  await batch.commit();
  console.log('\n✅ 완료! 앱에서 즉시 반영됩니다.');
}

run().catch((e) => { console.error(e); process.exit(1); });
