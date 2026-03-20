import urllib.request
import json
import re

url = "https://www.knue.ac.kr/www/selectSearchEmplList.do?key=444&searchKrwd=043"
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req, timeout=30) as resp:
    content = resp.read().decode("utf-8", errors="replace")

def clean_html(s):
    s = re.sub(r'<[^>]+>', '', s)
    s = s.replace('&amp;', '&').replace('&nbsp;', ' ').replace('&#39;', "'")
    s = re.sub(r'\s+', ' ', s).strip()
    return s

rows = re.findall(r'<tr>(.*?)</tr>', content, re.DOTALL)
results = []

for row in rows:
    if '<td' not in row:
        continue
    tds = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL)
    if len(tds) < 4:
        continue
    cat   = clean_html(tds[0])
    dept  = clean_html(tds[1])
    phone_td = clean_html(tds[2])
    duty  = clean_html(tds[3]) if len(tds) > 3 else ""
    phone_match = re.search(r'043-[\d-]+', row)
    phone = phone_match.group(0) if phone_match else phone_td
    results.append({"category": cat, "dept": dept, "duties": duty, "phone": phone})

print(f"파싱 결과: {len(results)}건")
for r in results[:5]:
    print(r)

with open("knue_staff.json", "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

print("knue_staff.json 저장 완료")
