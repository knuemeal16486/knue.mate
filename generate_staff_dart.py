import json

# 행정 관련 부서만 필터링 (학과/교수 제외)
ADMIN_DEPTS = {
    # 대학 본부 직속
    '한국교원대학교', '교수부', '사도교육원',
    # 행정처
    '총무과', '시설관리과', '재무과',
    # 처/원 단위
    '기획처', '기획평가과', '교수지원과', '연구전략과',
    '입학인재관리과', '학생복지과', '장학복지과',
    '대외협력부', '학술정보과', '정보화팀',
    '교육혁신센터', '종합교육연수원', '사무국',
    '산학협력단',
    # 연구기관
    '교육연구원', 'AI에듀테크센터', '에듀테크연구센터',
    '뇌기반교육', '뇌AI기반교육', '교육박물관',
    '황새생태연구원', 'KNUE심리상담센터', '인권센터',
    '신문방송사', '영유아교육연수원', '글로벌교육리더십',
    '과학영재교육', '문화콘텐츠교육', '융합교육',
    '인공지능융합교육', '교원연수사업단', '늘봄지원사업단',
    '뇌AI기반교육', '영재교육원',
    # 대학/대학원
    '일반대학원', '교육대학원', '교육정책전문대학원',
    '제1대학', '제2대학', '제3대학', '제4대학',
    '수학교설립추진단',
}

data = json.load(open('knue_staff.json', encoding='utf-8'))

# 학과 관련 필터 (학과 교수/조교 등은 이미 과사무실 탭에 있음)
SKIP_DEPTS = {
    '교육학과', '국어교육과', '영어교육과', '독어교육과', '불어교육과',
    '음악교육과', '미술교육과', '체육교육과', '윤리교육과', '일반사회교육과',
    '역사교육과', '지리교육과', '수학교육과', '물리교육과', '화학교육과',
    '생물교육과', '환경교육과', '기술교육과', '가정교육과', '컴퓨터교육과',
    '유아교육과', '초등교육과', '특수교육과', '교육정책학과',
}

# 모든 부서 포함 (학과 제외)
filtered = [d for d in data if d['dept'] not in SKIP_DEPTS]

# duties가 "내용없음"인 경우 빈 문자열로
for d in filtered:
    if d['duties'] in ['내용없음', '-', '']:
        d['duties'] = ''

# 부서별 그룹화
from collections import OrderedDict
dept_groups = OrderedDict()
for staff in filtered:
    dept = staff['dept']
    if dept not in dept_groups:
        dept_groups[dept] = []
    dept_groups[dept].append(staff)

# Dart 코드 생성
lines = []
lines.append("// ─── 행정직원 데이터 (자동 생성) ───")
lines.append("")
lines.append("class AdminStaff {")
lines.append("  final String category;")
lines.append("  final String dept;")
lines.append("  final String duties;")
lines.append("  final String phone;")
lines.append("  const AdminStaff({required this.category, required this.dept, required this.duties, required this.phone});")
lines.append("}")
lines.append("")
lines.append("const List<AdminStaff> kAdminStaff = [")

for staff in filtered:
    cat = staff['category'].replace("'", "\\'")
    dept = staff['dept'].replace("'", "\\'")
    duties = staff['duties'].replace("'", "\\'")
    phone = staff['phone']
    lines.append(f"  AdminStaff(category: '{cat}', dept: '{dept}', duties: '{duties}', phone: '{phone}'),")

lines.append("];")

dart_code = '\n'.join(lines)
with open('admin_staff_data.dart.txt', 'w', encoding='utf-8') as f:
    f.write(dart_code)

print(f"총 {len(filtered)}명의 직원 데이터 생성 (부서 수: {len(dept_groups)}개)")
print("저장 완료: admin_staff_data.dart.txt")
# 상위 부서별 인원 표시
for dept, staffs in list(dept_groups.items())[:10]:
    print(f"  {dept}: {len(staffs)}명")
