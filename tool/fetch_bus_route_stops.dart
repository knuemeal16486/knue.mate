// 버스 노선 10개의 정류장 목록을 공공데이터포털에서 받아 lib/bus_route_snapshot.dart를
// 만든다(2026-11-12).
//
//   dart run tool/fetch_bus_route_stops.dart
//
// 노선정보(BusRouteInfoInqireService) 키는 운영 빌드에 일부러 넣지 않았다. 그래서
// 앱은 이 스냅샷으로 정류장 순서·방향·좌표를 안다. 청주시가 노선을 개정하면 이걸
// 다시 돌린다. .env의 BUS_ROUTE_API_KEY를 쓴다.
//
// 노선 목록은 lib/bus_service.dart의 _kRoutes와 같아야 한다(bus_route_snapshot_test가
// 확인한다).

import 'dart:convert';
import 'dart:io';

const routes = <int, String>{
  513: 'CJB270008000',
  514: 'CJB270008300',
  518: 'CJB270024700',
  913: 'CJB270014300',
  500: 'CJB270007100',
  502: 'CJB270007300',
  503: 'CJB270026400',
  509: 'CJB270026500',
  511: 'CJB270007500',
  747: 'CJB270011200',
};

String _env(String name) {
  for (final line in File('.env').readAsLinesSync()) {
    final i = line.indexOf('=');
    if (i > 0 && line.substring(0, i).trim() == name) return line.substring(i + 1).trim();
  }
  throw StateError('.env에 $name이 없다');
}

String _q(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

Future<void> main() async {
  final key = _env('BUS_ROUTE_API_KEY');
  final client = HttpClient();
  final out = StringBuffer()
    ..writeln('// 생성 파일 — tool/fetch_bus_route_stops.dart가 만든다. 손으로 고치지 않는다.')
    ..writeln('//')
    ..writeln('// 공공데이터포털 노선정보(getRouteAcctoThrghSttnList) 응답을 그대로 옮긴 것.')
    ..writeln('// 운영 빌드엔 노선정보 키가 없어서 앱은 이걸로 정류장 순서·방향(upDownCd)·')
    ..writeln('// 좌표를 안다. 노선이 개정되면 도구를 다시 돌린다.')
    ..writeln()
    ..writeln("import 'bus_model.dart';")
    ..writeln()
    ..writeln("const String kRouteSnapshotDate = '${DateTime.now().toIso8601String().substring(0, 10)}';")
    ..writeln()
    ..writeln('/// routeId → 정류장(nodeOrd 순).')
    ..writeln('const Map<String, List<RouteStop>> kRouteStopsSnapshot = {');

  for (final e in routes.entries) {
    final uri = Uri.https('apis.data.go.kr', '/1613000/BusRouteInfoInqireService/getRouteAcctoThrghSttnList', {
      'serviceKey': key,
      'cityCode': '33010',
      'routeId': e.value,
      '_type': 'json',
      'numOfRows': '300',
    });
    final req = await client.getUrl(uri);
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final items = (((body['response'] as Map)['body'] as Map)['items'] as Map)['item'];
    final list = [for (final x in (items is List ? items : [items])) (x as Map).cast<String, dynamic>()]
      ..sort((a, b) => (a['nodeord'] as num).compareTo(b['nodeord'] as num));
    if (list.isEmpty) throw StateError('${e.key}번 정류장이 비었다');

    out.writeln('  // ${e.key}번 — ${list.length}개');
    out.writeln("  '${e.value}': [");
    for (final s in list) {
      out.writeln('    RouteStop('
          'nodeId: ${_q('${s['nodeid']}')}, '
          'nodeName: ${_q('${s['nodenm']}')}, '
          '${s['nodeno'] == null ? '' : "nodeNo: ${_q('${s['nodeno']}')}, "}'
          'nodeOrd: ${(s['nodeord'] as num).toInt()}, '
          'latitude: ${s['gpslati']}, longitude: ${s['gpslong']}, '
          'upDownCd: ${s['updowncd']}),');
    }
    out.writeln('  ],');
    stdout.writeln('${e.key}번: ${list.length}개');
  }
  out.writeln('};');
  client.close();
  File('lib/bus_route_snapshot.dart').writeAsStringSync(out.toString());
  stdout.writeln('→ lib/bus_route_snapshot.dart');
}
