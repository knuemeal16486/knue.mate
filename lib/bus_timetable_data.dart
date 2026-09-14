/// 버스 노선별 시간표 데이터
/// bus_screen.dart에서 공통으로 사용

class BusTimetableData {
  /// 시간표 데이터 (노선번호 -> 방향(상행/하행) -> 요일(weekday/holiday) -> 시간 목록)
  static const Map<String, Map<String, Map<String, List<String>>>> schedules = {
    "513": {
      "outgoing": {
        "weekday": [
          "06:20",
          "07:15",
          "07:30",
          "08:50",
          "10:05",
          "10:50",
          "11:45",
          "12:39",
          "13:33",
          "14:27",
          "15:35",
          "16:30",
          "17:23",
          "18:16",
          "19:24",
          "20:17",
          "21:07",
          "22:00",
          "22:40",
        ],
        "holiday": [
          "06:20",
          "07:15",
          "07:30",
          "08:50",
          "10:05",
          "10:50",
          "11:45",
          "12:39",
          "13:33",
          "14:27",
          "15:35",
          "16:30",
          "17:23",
          "18:16",
          "19:24",
          "20:17",
          "21:07",
          "22:00",
          "22:40",
        ],
      },
      "incoming": {
        "weekday": [
          "06:05",
          "07:00",
          "08:10",
          "09:20",
          "10:15",
          "11:09",
          "12:03",
          "12:57",
          "14:05",
          "15:00",
          "15:53",
          "16:46",
          "17:39",
          "18:32",
          "19:37",
          "20:30",
          "21:20",
          "22:10",
        ],
        "holiday": [
          "06:05",
          "07:00",
          "08:10",
          "09:20",
          "10:15",
          "11:09",
          "12:03",
          "12:57",
          "14:05",
          "15:00",
          "15:53",
          "16:46",
          "17:39",
          "18:32",
          "19:37",
          "20:30",
          "21:20",
          "22:10",
        ],
      },
    },
    "514": {
      "outgoing": {
        "weekday": [
          "05:30",
          "06:10",
          "06:55",
          "07:50",
          "09:25",
          "10:30",
          "11:17",
          "12:12",
          "13:06",
          "14:00",
          "15:02",
          "16:03",
          "16:56",
          "17:49",
          "18:57",
          "19:50",
          "20:40",
          "21:34",
          "22:27",
        ],
        "holiday": [
          "05:30",
          "06:10",
          "06:55",
          "07:50",
          "09:25",
          "10:30",
          "11:17",
          "12:12",
          "13:06",
          "14:00",
          "15:02",
          "16:03",
          "16:56",
          "17:49",
          "18:57",
          "19:50",
          "20:40",
          "21:34",
          "22:27",
        ],
      },
      "incoming": {
        "weekday": [
          "05:30",
          "06:25",
          "07:35",
          "08:35",
          "09:47",
          "10:42",
          "11:36",
          "12:30",
          "13:32",
          "14:33",
          "15:26",
          "16:19",
          "17:12",
          "18:05",
          "19:10",
          "20:04",
          "20:57",
          "21:50",
          "22:30",
        ],
        "holiday": [
          "05:30",
          "06:25",
          "07:35",
          "08:35",
          "09:47",
          "10:42",
          "11:36",
          "12:30",
          "13:32",
          "14:33",
          "15:26",
          "16:19",
          "17:12",
          "18:05",
          "19:10",
          "20:04",
          "20:57",
          "21:50",
          "22:30",
        ],
      },
    },
    "518": {
      "outgoing": {
        "weekday": [
          "05:40",
          "06:30",
          "07:05",
          "08:05",
          "08:55",
          "09:55",
          "11:25",
          "12:15",
          "12:55",
          "13:45",
          "14:25",
          "15:15",
          "16:25",
          "17:15",
          "18:00",
          "19:05",
          "19:50",
          "20:35",
          "21:20",
          "22:05",
          "22:50",
        ],
        "holiday": [
          "05:40",
          "06:30",
          "07:05",
          "08:05",
          "08:55",
          "09:55",
          "11:25",
          "12:15",
          "12:55",
          "13:45",
          "14:25",
          "15:15",
          "16:25",
          "17:15",
          "18:00",
          "19:05",
          "19:50",
          "20:35",
          "21:20",
          "22:05",
          "22:50",
        ],
      },
      "incoming": {
        "weekday": [
          "05:40",
          "06:15",
          "07:05",
          "07:50",
          "08:50",
          "09:40",
          "10:30",
          "12:00",
          "12:50",
          "13:30",
          "14:20",
          "15:00",
          "15:50",
          "17:00",
          "18:00",
          "18:45",
          "19:40",
          "20:25",
          "21:10",
          "21:55",
          "22:40",
        ],
        "holiday": [
          "05:40",
          "06:15",
          "07:05",
          "07:50",
          "08:50",
          "09:40",
          "10:30",
          "12:00",
          "12:50",
          "13:30",
          "14:20",
          "15:00",
          "15:50",
          "17:00",
          "18:00",
          "18:45",
          "19:40",
          "20:25",
          "21:10",
          "21:55",
          "22:40",
        ],
      },
    },
    // 913 — 평동↔미호종점 (2024-08-10 개정).
    //
    // 다른 노선과 달리 **교원대가 종점이 아니라 경유지**다:
    //   incoming(평동 출발)  = 평동 출발   — 상행. 교원대는 29번째 경유.
    //   outgoing(미호종점 출발) = 미호종점 출발 — 하행. 교원대는 7번째 경유.
    //   knue_up(교원대 상행) = 평동발 버스의 교원대 도착/경유 시각.
    //   knue_down(교원대 하행) = 미호종점발 버스의 교원대 도착/경유 시각.
    "913": {
      "outgoing": {
        "weekday": [
          "05:30",
          "06:45",
          "07:55",
          "09:20",
          "10:45",
          "12:20",
          "13:45",
          "15:05",
          "16:30",
          "18:10",
          "19:45",
          "20:50",
          "22:30",
        ],
        "holiday": [
          "05:30",
          "06:45",
          "07:55",
          "09:20",
          "10:45",
          "12:20",
          "13:45",
          "15:05",
          "16:30",
          "18:10",
          "19:45",
          "20:50",
          "22:30",
        ],
      },
      "incoming": {
        "weekday": [
          "05:40",
          "06:50",
          "08:05",
          "09:40",
          "11:15",
          "12:40",
          "14:00",
          "15:25",
          "17:00",
          "18:30",
          "19:45",
          "21:25",
        ],
        "holiday": [
          "05:40",
          "06:50",
          "08:05",
          "09:40",
          "11:15",
          "12:40",
          "14:00",
          "15:25",
          "17:00",
          "18:30",
          "19:45",
          "21:25",
        ],
      },
      "knue_up": {
        "weekday": [
          "06:30",
          "07:40",
          "09:03",
          "10:30",
          "12:05",
          "13:30",
          "14:50",
          "16:15",
          "17:53",
          "19:28",
          "20:35",
          "22:15",
        ],
        "holiday": [
          "06:30",
          "07:40",
          "09:03",
          "10:30",
          "12:05",
          "13:30",
          "14:50",
          "16:15",
          "17:53",
          "19:28",
          "20:35",
          "22:15",
        ],
      },
      "knue_down": {
        "weekday": [
          "05:43",
          "06:58",
          "08:10",
          "09:33",
          "10:58",
          "12:33",
          "13:58",
          "15:18",
          "16:44",
          "18:25",
          "19:58",
          "21:03",
          "22:42",
        ],
        "holiday": [
          "05:43",
          "06:58",
          "08:10",
          "09:33",
          "10:58",
          "12:33",
          "13:58",
          "15:18",
          "16:44",
          "18:25",
          "19:58",
          "21:03",
          "22:42",
        ],
      },
    },
  };

  /// 913번 노선 상세 정보 (평동 출발 -> 교원대 경유 -> 미호종점 도착: 상행)
  static const List<Route913Trip> route913PyeongdongToMiho = [
    Route913Trip(
      originTime: "05:40",
      knueTime: "06:30",
      destinationTime: "06:45",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "06:50",
      knueTime: "07:40",
      destinationTime: "07:55",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "08:05",
      knueTime: "09:03",
      destinationTime: "09:20",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "09:40",
      knueTime: "10:30",
      destinationTime: "10:45",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "11:15",
      knueTime: "12:05",
      destinationTime: "12:20",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "12:40",
      knueTime: "13:30",
      destinationTime: "13:45",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "14:00",
      knueTime: "14:50",
      destinationTime: "15:05",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "15:25",
      knueTime: "16:15",
      destinationTime: "16:30",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "17:00",
      knueTime: "17:53",
      destinationTime: "18:10",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "18:30",
      knueTime: "19:28",
      destinationTime: "19:45",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "19:45",
      knueTime: "20:35",
      destinationTime: "20:50",
      originName: "평동",
      destinationName: "미호종점",
    ),
    Route913Trip(
      originTime: "21:25",
      knueTime: "22:15",
      destinationTime: "22:30",
      originName: "평동",
      destinationName: "미호종점",
    ),
  ];

  /// 913번 노선 상세 정보 (미호종점 출발 -> 교원대 경유 -> 평동 도착: 하행)
  static const List<Route913Trip> route913MihoToPyeongdong = [
    Route913Trip(
      originTime: "05:30",
      knueTime: "05:43",
      destinationTime: "06:35",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "06:45",
      knueTime: "06:58",
      destinationTime: "07:50",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "07:55",
      knueTime: "08:10",
      destinationTime: "09:10",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "09:20",
      knueTime: "09:33",
      destinationTime: "10:25",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "10:45",
      knueTime: "10:58",
      destinationTime: "11:50",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "12:20",
      knueTime: "12:33",
      destinationTime: "13:25",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "13:45",
      knueTime: "13:58",
      destinationTime: "14:50",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "15:05",
      knueTime: "15:18",
      destinationTime: "16:10",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "16:30",
      knueTime: "16:44",
      destinationTime: "17:40",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "18:10",
      knueTime: "18:25",
      destinationTime: "19:25",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "19:45",
      knueTime: "19:58",
      destinationTime: "20:50",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "20:50",
      knueTime: "21:03",
      destinationTime: "21:55",
      originName: "미호종점",
      destinationName: "평동",
    ),
    Route913Trip(
      originTime: "22:30",
      knueTime: "22:42",
      destinationTime: "23:30",
      originName: "미호종점",
      destinationName: "평동",
    ),
  ];

  /// 승차 정류장 오프셋 데이터 (노선번호 -> 정류장명 -> 오프셋)
  /// 913번 종점 시간표 원본 (출발, 도착) 짝.
  ///
  /// [schedules]의 913 항목은 여기서 출발 시각만 뽑아 쓴다. 도착 시각까지
  /// 남겨 두는 이유는, 나중에 교원대 통과 시각을 낼 때 이 둘 사이를 갈라야
  /// 하기 때문이다. 두 표가 어긋나지 않는지는 테스트가 지킨다.
  static const Map<String, List<List<String>>> route913Terminal = {
    "평동→미호종점": [
      ["05:40", "06:45"],
      ["06:50", "07:55"],
      ["08:05", "09:20"],
      ["09:40", "10:45"],
      ["11:15", "12:20"],
      ["12:40", "13:45"],
      ["14:00", "15:05"],
      ["15:25", "16:30"],
      ["17:00", "18:10"],
      ["18:30", "19:45"],
      ["19:45", "20:50"],
      ["21:25", "22:30"],
    ],
    "미호종점→평동": [
      ["05:30", "06:35"],
      ["06:45", "07:50"],
      ["07:55", "09:10"],
      ["09:20", "10:25"],
      ["10:45", "11:50"],
      ["12:20", "13:25"],
      ["13:45", "14:50"],
      ["15:05", "16:10"],
      ["16:30", "17:40"],
      ["18:10", "19:25"],
      ["19:45", "20:50"],
      ["20:50", "21:55"],
      ["22:30", "23:30"],
    ],
  };

  static const Map<String, Map<String, int>> boardingStops = {
    "513": {"고속버스터미널": 23, "사창사거리(충북대)": 35},
    "514": {"현대백화점": 24, "사창사거리(충북대)": 32, "성안길(청주대교)": 44},
    "518": {"오송역": 10, "만수공원": 5, "오송119안전센터": 3},
    "913": {},
  };



  /// 시간표 가져오기
  static List<String>? getTimetable(
    String routeNumber,
    bool isOutgoing,
    bool isWeekday,
  ) {
    final direction = isOutgoing ? "outgoing" : "incoming";
    final dayType = isWeekday ? "weekday" : "holiday";
    return schedules[routeNumber]?[direction]?[dayType];
  }

  /// 다음 버스 시간 가져오기
  static String? getNextBusTime(
    String routeNumber,
    bool isOutgoing,
    bool isWeekday,
  ) {
    final timetable = getTimetable(routeNumber, isOutgoing, isWeekday);
    if (timetable == null || timetable.isEmpty) return null;

    final now = DateTime.now();
    final currentTime =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    for (final time in timetable) {
      if (time.compareTo(currentTime) > 0) {
        return time;
      }
    }
    return null;
  }

  /// 특정시간대 고정노선 콜버스 데이터
  static const List<CallBusScheduleItem> gangnaeCallBusSchedules = [
    CallBusScheduleItem(
      round: 1,
      departurePlace: "태성3",
      departureTime: "06:30",
      stops: ["산단", "저산1", "당곡", "사곡3"],
      arrivalPlace: "미호",
      arrivalTime: "07:05",
    ),
    CallBusScheduleItem(
      round: 2,
      departurePlace: "미호",
      departureTime: "07:10",
      stops: ["태성3", "산단", "저산1", "태성3"],
      arrivalPlace: "미호",
      arrivalTime: "08:05",
    ),
    CallBusScheduleItem(
      round: 3,
      departurePlace: "미호",
      departureTime: "08:15",
      stops: ["태성3", "저산1", "산단", "태성3"],
      arrivalPlace: "미호",
      arrivalTime: "09:15",
    ),
    CallBusScheduleItem(
      round: 4,
      departurePlace: "미호",
      departureTime: "14:50",
      stops: ["태성3", "산단", "저산1", "태성3"],
      arrivalPlace: "미호",
      arrivalTime: "15:45",
    ),
    CallBusScheduleItem(
      round: 5,
      departurePlace: "미호",
      departureTime: "15:55",
      stops: ["태성3", "저산1", "산단", "태성3"],
      arrivalPlace: "미호",
      arrivalTime: "16:50",
    ),
  ];

  static const List<CallBusScheduleItem> osongCallBusSchedules = [
    CallBusScheduleItem(
      round: 1,
      departurePlace: "오송읍",
      departureTime: "07:15",
      stops: ["오송역", "쌍청1리", "호계리", "상정리", "공북리", "한국철도시설공단"],
      arrivalPlace: "조치원",
      arrivalTime: "08:20",
    ),
    CallBusScheduleItem(
      round: 2,
      departurePlace: "조치원",
      departureTime: "08:20",
      stops: ["한국철도시설공단", "공북리", "상정리", "호계리", "쌍청1리", "오송역"],
      arrivalPlace: "오송읍",
      arrivalTime: "09:25",
    ),
    CallBusScheduleItem(
      round: 3,
      departurePlace: "오송읍",
      departureTime: "09:40",
      stops: ["오송역", "쌍청1리", "호계리", "상정리", "공북리", "한국철도시설공단"],
      arrivalPlace: "조치원",
      arrivalTime: "10:45",
    ),
    CallBusScheduleItem(
      round: 4,
      departurePlace: "조치원",
      departureTime: "10:45",
      stops: ["한국철도시설공단", "공북리", "상정리", "호계리", "쌍청1리", "오송역"],
      arrivalPlace: "오송읍",
      arrivalTime: "11:50",
    ),
    CallBusScheduleItem(
      round: 5,
      departurePlace: "조치원",
      departureTime: "14:05",
      stops: ["한국철도시설공단", "공북리", "상정리", "호계리", "쌍청1리", "오송역"],
      arrivalPlace: "오송읍",
      arrivalTime: "15:10",
    ),
    CallBusScheduleItem(
      round: 6,
      departurePlace: "오송읍",
      departureTime: "15:30",
      stops: ["오송역", "쌍청1리", "호계리", "상정리", "공북리", "한국철도시설공단"],
      arrivalPlace: "조치원",
      arrivalTime: "16:35",
    ),
    CallBusScheduleItem(
      round: 7,
      departurePlace: "조치원",
      departureTime: "17:55",
      stops: ["한국철도시설공단", "공북리", "상정리", "호계리", "쌍청1리", "오송역"],
      arrivalPlace: "오송읍",
      arrivalTime: "19:00",
    ),
  ];
}

/// 콜버스 고정노선 시간표 아이템 모델
class CallBusScheduleItem {
  final int round;
  final String departurePlace;
  final String departureTime;
  final List<String> stops;
  final String arrivalPlace;
  final String arrivalTime;

  const CallBusScheduleItem({
    required this.round,
    required this.departurePlace,
    required this.departureTime,
    required this.stops,
    required this.arrivalPlace,
    required this.arrivalTime,
  });
}

/// 913번 운행 상세 정보 모델 (출발지, 교원대 경유, 종점 도착)
class Route913Trip {
  final String originTime; // 출발지 시각
  final String knueTime; // 교원대 경유 시각
  final String destinationTime; // 종점 도착 시각
  final String originName; // 출발지명
  final String destinationName; // 도착지명

  const Route913Trip({
    required this.originTime,
    required this.knueTime,
    required this.destinationTime,
    required this.originName,
    required this.destinationName,
  });
}
