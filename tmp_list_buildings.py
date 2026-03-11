import json

path = r'c:\Users\PC\Desktop\knue.mate\assets\buildings\knue_buildings.json'
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for b in data['buildings']:
    print(f"'{b['name']}' - floors: {len(b.get('floors', []))}")
