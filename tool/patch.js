// 줄바꿈 스타일(CRLF/LF)을 그대로 유지하며 정확히 한 번만 치환한다.
// 백슬래시는 '~B~'로 적는다 — 셸 힙독이 백슬래시를 먹기 때문.
const fs = require('fs');
const BS = String.fromCharCode(92);
const un = t => t.split('~B~').join(BS).split('~D~').join(String.fromCharCode(36));
function patch(path, pairs) {
  const raw = fs.readFileSync(path, 'utf8');
  const crlf = raw.includes('\r\n');
  let s = crlf ? raw.split('\r\n').join('\n') : raw;
  for (const [a, b] of pairs) {
    const A = un(a), B = un(b);
    const n = s.split(A).length - 1;
    if (n !== 1) {
      console.error(`MISS(${n}) in ${path}:\n` + A.slice(0, 180));
      process.exit(1);
    }
    s = s.split(A).join(B);
  }
  fs.writeFileSync(path, crlf ? s.split('\n').join('\r\n') : s);
}
module.exports = { patch };
