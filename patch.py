import json
import re

with open('assets/buildings/knue_buildings.json', 'r', encoding='utf-8') as f:
    json_data = json.load(f)

with open('lib/campus_map_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

for b in json_data['buildings']:
    name = b['name']
    
    floors_dart = "[\n"
    for fl in b['floors']:
        floor_val = fl['floor']
        if isinstance(floor_val, str):
            floor_dart_val = f"'{floor_val}'"
        else:
            floor_dart_val = str(floor_val)
            
        rooms_dart = "["
        for r in fl['facilities']:
            r_name = r['name'].replace("'", "\\'") if r['name'] else ''
            if r.get('room'):
                r_room = str(r['room']).replace("'", "\\'")
                rooms_dart += f"'{r_room} {r_name}', "
            else:
                rooms_dart += f"'{r_name}', "
        rooms_dart += "]"
        
        floors_dart += f"      FloorData(floor: {floor_dart_val}, rooms: {rooms_dart}),\n"
    floors_dart += "    ]"

    b_idx = code.find(f"name: '{name}'")
    if b_idx != -1:
        floors_idx = code.find('floors:', b_idx)
        if floors_idx != -1:
            end_bracket_idx = -1
            bracket_count = 0
            for i in range(floors_idx + 7, len(code)):
                if code[i] == '[':
                    bracket_count += 1
                elif code[i] == ']':
                    bracket_count -= 1
                    if bracket_count == 0:
                        end_bracket_idx = i
                        break
            if end_bracket_idx != -1:
                start_part = code[:floors_idx + 7]
                while start_part[-1] in (' ', '\n', '\r'):
                    start_part = start_part[:-1]
                start_part += " "
                
                end_part = code[end_bracket_idx + 1:]
                code = start_part + floors_dart + end_part
                print(f"Updated {name}")

code = re.sub(r'TabController\(length: \d+,', r'TabController(length: 6,', code)

if "'강의실 검색'" not in code:
    code = code.replace("Tab(text: '과 사무실'),", "Tab(text: '과 사무실'),\n                  Tab(text: '강의실 검색'),")

if "_buildClassroomSearchTab" not in code:
    code = code.replace("_buildDeptOfficeTab(isDark),", "_buildDeptOfficeTab(isDark),\n                  _buildClassroomSearchTab(primary, isDark),")

    insert_str = """
  String _classroomSearchQuery = '';

  Widget _buildClassroomSearchTab(Color primary, bool isDark) {
    final query = _classroomSearchQuery.trim().toLowerCase();
    
    // 검색 수행
    List<Map<String, dynamic>> results = [];
    if (query.isNotEmpty) {
      for (final b in kBuildings) {
        for (final f in b.floors) {
          for (final room in f.rooms) {
            final lowerRoom = room.toLowerCase();
            if (lowerRoom.contains(query) || b.name.toLowerCase().contains(query) || b.shortName.toLowerCase().contains(query)) {
              results.add({
                'building': b,
                'floor': f.floor,
                'room': room,
              });
            }
          }
        }
      }
    }

    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 104),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white12
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _classroomSearchQuery = v),
                    decoration: InputDecoration(
                      hintText: '강의실 이름, 호수, 건물명 검색...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (query.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.class_rounded,
                    size: 48,
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '강의실 이름이나 호수를 검색해보세요',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (results.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                '검색 결과가 없습니다.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: results.length,
              itemBuilder: (ctx, i) {
                final r = results[i];
                final BuildingData b = r['building'];
                final floor = r['floor'];
                final String room = r['room'];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: b.color.withValues(alpha: 0.15),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: b.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.meeting_room_rounded,
                          color: b.color,
                          size: 20,
                        ),
                      ),
                    ),
                    title: Text(
                      room,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${b.name}  ·  ${floor}${floor is int && floor > 0 ? "F" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    onTap: () {
                      _tabController.animateTo(0);
                      Future.delayed(
                        const Duration(milliseconds: 200),
                        () => _animatedMove(b.position, 18.0),
                      );
                      Future.delayed(
                        const Duration(milliseconds: 400),
                        () => _showBuildingDetail(b),
                      );
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
"""
    
    dept_idx = code.find('Widget _buildDeptOfficeTab')
    if dept_idx != -1:
        code = code[:dept_idx] + insert_str + "\n\n  " + code[dept_idx:]

with open('lib/campus_map_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Saved successfully")
