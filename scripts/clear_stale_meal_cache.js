#!/usr/bin/env node
/**
 * 학생회관(MealSource.b) 만료 캐시 삭제 스크립트
 *
 * 사용법:
 *   1. Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성
 *   2. 다운로드한 JSON 파일을 이 스크립트와 같은 폴더에 serviceAccount.json 으로 저장
 *   3. npm install firebase-admin
 *   4. node clear_stale_meal_cache.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'knue-mate',
});

const db = admin.firestore();

async function clearStaleMealBCache() {
  // 이번 주 월요일 00:00:00 계산
  const now = new Date();
  const dayOfWeek = now.getDay() === 0 ? 7 : now.getDay(); // 일요일=7로 통일
  const thisMonday = new Date(now);
  thisMonday.setDate(now.getDate() - (dayOfWeek - 1));
  thisMonday.setHours(0, 0, 0, 0);

  console.log(`이번 주 월요일 기준: ${thisMonday.toISOString()}`);
  console.log('daily_meals 컬렉션에서 _b 문서 조회 중...\n');

  const snapshot = await db
    .collection('daily_meals')
    .where('source', '==', 'b')
    .get();

  if (snapshot.empty) {
    console.log('학생회관(b) 문서가 없습니다.');
    return;
  }

  const stale = [];
  snapshot.forEach((doc) => {
    const data = doc.data();
    const lastUpdated = data.lastUpdated?.toDate();
    if (!lastUpdated || lastUpdated < thisMonday) {
      stale.push({ id: doc.id, lastUpdated });
    }
  });

  if (stale.length === 0) {
    console.log('만료된 학생회관 캐시가 없습니다. 이미 최신 상태입니다.');
    return;
  }

  console.log(`만료된 문서 ${stale.length}개 발견:`);
  stale.forEach((d) => {
    console.log(`  - ${d.id}  (저장: ${d.lastUpdated?.toISOString() ?? 'null'})`);
  });

  const batch = db.batch();
  stale.forEach((d) => batch.delete(db.collection('daily_meals').doc(d.id)));
  await batch.commit();

  console.log(`\n✅ ${stale.length}개 문서 삭제 완료. 다음 앱 실행 시 최신 식단이 재스크래핑됩니다.`);
}

clearStaleMealBCache().catch((err) => {
  console.error('오류:', err);
  process.exit(1);
});
