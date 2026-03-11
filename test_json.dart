import 'dart:convert';
import 'dart:io';

void main() {
  final file = File(
    'c:\\Users\\PC\\Desktop\\knue.mate\\assets\\buildings\\knue_buildings.json',
  );
  final content = file.readAsStringSync();
  try {
    jsonDecode(content);
    print('OK');
  } catch (e) {
    print(e);
  }
}
