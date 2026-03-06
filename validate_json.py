import json
try:
    with open('assets/buildings/knue_buildings.json', 'r', encoding='utf-8') as f:
        data = json.load(f)
    print("VALID")
except json.JSONDecodeError as e:
    print(f"INVALID: {e.msg} at line {e.lineno}, col {e.colno} (pos {e.pos})")
except Exception as e:
    print(f"ERROR: {e}")
