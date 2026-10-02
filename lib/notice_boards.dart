// 공지 게시판 목록. Flutter 없이도 읽을 수 있게 따로 둔다 — 앱(KnueScraper)과
// 중앙 수집기(tool/collect_notices.dart)가 같은 목록을 쓴다.

/// 크롤링 대상 게시판. 그룹 → 게시판 이름 → 목록 주소.
/// "LINK:"로 시작하면 받지 않고 그 주소로 넘기기만 한다.
const Map<String, Map<String, String>> kNoticeBoardGroups = {
  'MAIN': {
    '대학소식': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=25&key=806',
    '학사공지': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=26&key=807',
    '청람소양':
        'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=256&key=1609',
    '학점교류':
        'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=254&key=1562',
    '등록금': 'https://www.knue.ac.kr/www/selectBbsNttList.do?key=550&bbsNo=11',
    '장학금':
        'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=207&key=1443',
    '교환학생': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=13&key=597',
    '행사세미나':
        'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=28&key=809',
    '채용공고': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=27&key=808',
    '입찰공고': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=29&key=810',
  },
  'ANNEX': {
    '도서관일반':
        'https://lib.knue.ac.kr/pyxis-api/1/bulletin-boards/1/bulletins?max=20&offset=0',
    '도서관학술':
        'https://lib.knue.ac.kr/pyxis-api/1/bulletin-boards/2/bulletins?max=20&offset=0',
    // 종합교육연수원 (공통 게시판 패턴)
    '종합연수원':
        'https://tot.knue.ac.kr/common/bbs/management/selectCmmnBBSMgmtList.do?menuId=3000001755&bbsId=BBSMSTR_003000000094',
    // 영유아교육연수원
    '영유아연수원':
        'https://tot.knue.ac.kr/common/bbs/management/selectCmmnBBSMgmtList.do?menuId=3000001756&bbsId=BBSMSTR_003000000576',
    // 신문방송사 (기사 목록 URL)
    '신문방송사':
        'https://m.news.knue.ac.kr/news/articleList.html?sc_section_code=S1N3',
    // 사도교육원
    '일반공지': 'http://rec.knue.ac.kr/bbs/lstBoard.jsp?bodcode=edunotice',
    '학부/대학원': 'http://rec.knue.ac.kr/bbs/lstBoard.jsp?bodcode=notice',
    '교육대학원': 'http://rec.knue.ac.kr/bbs/lstBoard.jsp?bodcode=boardt',
  },
  'LIFE': {
    '학생지원':
        'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=258&key=1625',
    '임용안내':
        'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=259&key=1630',
    '취업정보': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=12&key=574',
  },
  'DEPT': {
    // 제1대학
    '교육학과':
        'https://www.knue.ac.kr/education/selectBbsNttList.do?bbsNo=86&key=985',
    '유아교육과':
        'https://www.knue.ac.kr/ece/selectBbsNttList.do?bbsNo=93&key=1005',
    '초등교육과': 'LINK:https://m.cafe.daum.net/knue-primary/_rec',
    '특수교육과':
        'https://www.knue.ac.kr/sped/selectBbsNttList.do?bbsNo=100&key=1025',

    // 제2대학
    '국어교육과':
        'https://www.knue.ac.kr/korean/selectBbsNttList.do?bbsNo=106&key=1044',
    '영어교육과':
        'https://www.knue.ac.kr/english/selectBbsNttList.do?bbsNo=113&key=1114',
    '독어교육과':
        'https://www.knue.ac.kr/german/selectBbsNttList.do?bbsNo=223&key=1065',
    '불어교육과':
        'https://www.knue.ac.kr/french/selectBbsNttList.do?bbsNo=119&key=1079',
    '중국어교육과':
        'https://www.knue.ac.kr/chinese/selectBbsNttList.do?bbsNo=226&key=1143',
    '윤리교육과':
        'https://www.knue.ac.kr/ethics/selectBbsNttList.do?bbsNo=189&key=1343',
    '일반사회교육과':
        'https://www.knue.ac.kr/social/selectBbsNttList.do?bbsNo=133&key=1132',
    '지리교육과':
        'https://www.knue.ac.kr/geography/selectBbsNttList.do?bbsNo=229&key=1158',
    '역사교육과':
        'https://www.knue.ac.kr/history/selectBbsNttList.do?bbsNo=141&key=1092',

    // 제3대학
    '수학교육과':
        'https://www.knue.ac.kr/math/selectBbsNttList.do?bbsNo=151&key=1231',
    '물리교육과':
        'https://www.knue.ac.kr/phys/selectBbsNttList.do?bbsNo=194&key=1202',
    '화학교육과':
        'https://www.knue.ac.kr/chemedu/selectBbsNttList.do?bbsNo=235&key=1273',
    '생물교육과':
        'https://www.knue.ac.kr/bioedu/selectBbsNttList.do?bbsNo=161&key=1216',
    '지구과학교육과':
        'https://www.knue.ac.kr/earth/selectBbsNttList.do?bbsNo=166&key=1247',
    '가정교육과':
        'https://www.knue.ac.kr/homeedu/selectBbsNttList.do?bbsNo=199&key=1176',
    '환경교육과':
        'https://www.knue.ac.kr/envi/selectBbsNttList.do?bbsNo=178&key=1285',
    '기술교육과':
        'https://www.knue.ac.kr/techedu/selectBbsNttList.do?bbsNo=169&key=1189',
    '컴퓨터교육과':
        'https://www.knue.ac.kr/comedu/selectBbsNttList.do?bbsNo=242&key=1258',

    // 제4대학
    '음악교육과':
        'https://www.knue.ac.kr/music/selectBbsNttList.do?bbsNo=204&key=1314',
    '체육교육과':
        'https://www.knue.ac.kr/phy/selectBbsNttList.do?bbsNo=211&key=1327',
    '미술교육과':
        'https://www.knue.ac.kr/artedu/selectBbsNttList.do?bbsNo=181&key=1300',
  },
  'GRAD': {
    '대학원': 'https://www.knue.ac.kr/grad/selectBbsNttList.do?bbsNo=67&key=645',
    '교육대학원':
        'https://www.knue.ac.kr/grad/selectBbsNttList.do?bbsNo=68&key=646',
    '교육정책대학원':
        'https://www.knue.ac.kr/edupol/selectBbsNttList.do?bbsNo=73&key=659',
  },
};

/// 청람공지 화면의 표시 구조 — 큰 탭(공지사항 / 대학·대학원) → 하위 탭 →
/// 게시판. boardGroups(크롤링 대상)와는 별개의 "보여주는 방식"만 담당한다
/// — 여기 값을 바꿔도 크롤링이나 즐겨찾기·키워드 알림 저장 키(게시판
/// 이름 그 자체)는 그대로다.
///
/// '교육대학원'이 캠퍼스 생활(사도교육원 소속, 기숙사 공지)과 대학원
/// (GRAD 소속, 학사 공지) 양쪽에 나오는데, 이건 boardGroups에 실제로
/// 이름이 같은 게시판 두 개가 따로 있어서다(원래부터 있던 것 — 두 게시판이
/// 같은 category 문자열을 공유해 즐겨찾기/알림이 서로 엮일 수 있는 상태).
const Map<String, Map<String, List<String>>> kNoticeTabStructure = {
  '공지사항': {
    '학사안내': [
      '대학소식',
      '학사공지',
      '등록금',
      '장학금',
      '청람소양',
      '행사세미나',
      '채용공고',
      '입찰공고',
    ],
    '교류 프로그램': ['학점교류', '교환학생'],
    '캠퍼스 생활': [
      '학생지원',
      '임용안내',
      '취업정보',
      '일반공지',
      '학부/대학원',
      '교육대학원',
      '도서관일반',
      '도서관학술',
      '종합연수원',
      '영유아연수원',
      '신문방송사',
    ],
  },
  '대학/대학원': {
    '제1대학': ['교육학과', '유아교육과', '초등교육과', '특수교육과'],
    '제2대학': [
      '국어교육과',
      '영어교육과',
      '독어교육과',
      '불어교육과',
      '중국어교육과',
      '윤리교육과',
      '일반사회교육과',
      '지리교육과',
      '역사교육과',
    ],
    '제3대학': [
      '수학교육과',
      '물리교육과',
      '화학교육과',
      '생물교육과',
      '지구과학교육과',
      '가정교육과',
      '환경교육과',
      '기술교육과',
      '컴퓨터교육과',
    ],
    '제4대학': ['음악교육과', '체육교육과', '미술교육과'],
    '대학원': ['대학원', '교육대학원', '교육정책대학원'],
  },
};
