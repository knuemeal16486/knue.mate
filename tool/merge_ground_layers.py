# traced_raw.json의 바닥 층 몇 개만 campus_traced.json에 옮긴다.
#
#   dart run tool/trace_map.dart          # → tool/mapsrc/traced_raw.json
#   python tool/merge_ground_layers.py    # → assets/housing/campus_traced.json
#
# 원래는 build_index.dart가 traced_raw를 통째로 에셋으로 만든다. 지금은 그걸
# 돌리면 교내 21동의 이름·용도가 사라져서(CLAUDE.md "지도 데이터 다시 만들기")
# 돌릴 수 없다. 이 도구는 build_index가 **손대지 않고 그대로 넘기는 키**만
# 글자 그대로 옮기므로, 건물을 비롯한 다른 키는 한 글자도 바뀌지 않는다.
# (JSON으로 읽었다 다시 쓰면 5.0이 5로 바뀌는 식으로 파일 전체가 달라진다.)
import io
import json

KEYS = ['pavementFull', 'courts', 'stallStrips', 'paths', 'crosswalks']
RAW = 'tool/mapsrc/traced_raw.json'
ASSET = 'assets/housing/campus_traced.json'


def span(text, key):
    """text 안에서 "key": 뒤에 오는 값(객체나 배열)의 시작·끝."""
    k = '"%s":' % key
    i = text.index(k) + len(k)
    while text[i].isspace():  # 에셋은 "key": 뒤에 한 칸을 띄운 곳이 있다
        i += 1
    opener = text[i]
    closer = {'{': '}', '[': ']'}[opener]
    depth = 0
    j = i
    while True:
        c = text[j]
        if c == opener:
            depth += 1
        elif c == closer:
            depth -= 1
            if depth == 0:
                return i, j + 1
        j += 1


raw = io.open(RAW, encoding='utf-8', newline='').read()
asset = io.open(ASSET, encoding='utf-8', newline='').read()
before = json.loads(asset)

for key in KEYS:
    i, j = span(raw, key)
    value = raw[i:j]
    if '"%s":' % key in asset:
        x, y = span(asset, key)
        asset = asset[:x] + value + asset[y:]
    else:
        body = asset.rstrip()
        asset = body[:-1] + ',"%s":' % key + value + '}' + asset[len(body):]

after = json.loads(asset)
for key in before:
    if key not in KEYS:
        assert before[key] == after[key], '%s가 바뀌었다' % key
io.open(ASSET, 'w', encoding='utf-8', newline='').write(asset)
print('옮긴 키:', ', '.join('%s %d' % (k, len(after[k])) for k in KEYS),
      '· %d KB' % (len(asset) // 1024))
