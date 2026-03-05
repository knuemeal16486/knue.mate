import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;

void main() async {
  final url =
      'https://www.knue.ac.kr/www/selectDietInfoWebList.do?key=1960&siteSe=cafe';
  final response = await http.get(
    Uri.parse(url),
    headers: {'User-Agent': 'Mozilla/5.0'},
  );
  final html = utf8.decode(response.bodyBytes, allowMalformed: true);
  final doc = htmlParser.parse(html);
  final table = doc.querySelector('table.p-calendar-list');

  if (table == null) {
    print('No table found');
    return;
  }

  for (final th in table.querySelectorAll('thead th[data-day]')) {
    print('TH: ${th.text.trim()}');
  }

  final rows = table.querySelectorAll('tbody tr');
  print('Rows: ${rows.length}');
  for (int i = 0; i < rows.length; i++) {
    print('--- Row $i ---');
    final p = rows[i].querySelector('th')?.text.trim();
    print('TH in row: $p');
  }
}
