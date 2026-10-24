import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';

class EmptyClassroomCacheJson {
  static const int currentSchemaVersion = 1;

  int schemaVersion;
  String year;
  String semester;
  String language;
  bool complete;
  DateTime updatedAt;
  List<EmptyClassroomRoomJson> rooms;

  EmptyClassroomCacheJson({
    this.schemaVersion = currentSchemaVersion,
    required this.year,
    required this.semester,
    required this.language,
    required this.complete,
    required this.updatedAt,
    List<EmptyClassroomRoomJson>? rooms,
  }) : rooms = rooms ?? <EmptyClassroomRoomJson>[];

  SemesterJson get courseSemester => SemesterJson(year: year, semester: semester);

  int get builtCount => rooms.where((room) => room.built).length;

  bool matches(SemesterJson semester, String language) =>
      schemaVersion == currentSchemaVersion &&
      year == semester.year &&
      this.semester == semester.semester &&
      this.language == language;

  factory EmptyClassroomCacheJson.fromJson(Map<String, dynamic> json) {
    final rawRooms = json['rooms'];
    final rooms = <EmptyClassroomRoomJson>[];
    if (rawRooms is List) {
      for (final value in rawRooms) {
        if (value is! Map) throw const FormatException('Malformed empty-classroom room cache');
        rooms.add(EmptyClassroomRoomJson.fromJson(Map<String, dynamic>.from(value)));
      }
    } else {
      throw const FormatException('Malformed empty-classroom room list');
    }

    final complete = json['complete'] as bool? ?? false;
    if (complete && (rooms.isEmpty || rooms.any((room) => !room.built))) {
      throw const FormatException('Completed empty-classroom cache contains unfinished rooms');
    }

    return EmptyClassroomCacheJson(
      schemaVersion: json['schemaVersion'] as int? ?? 0,
      year: json['year'] as String? ?? '',
      semester: json['semester'] as String? ?? '',
      language: json['language'] as String? ?? '',
      complete: complete,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      rooms: rooms,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'year': year,
    'semester': semester,
    'language': language,
    'complete': complete,
    'updatedAt': updatedAt.toIso8601String(),
    'rooms': rooms.map((room) => room.toJson()).toList(growable: false),
  };
}

class EmptyClassroomRoomJson {
  String code;
  String name;
  String fullName;
  String capacity;
  String sourceUrl;
  bool built;
  Map<Day, Set<SectionNumber>> occupiedByDay;

  EmptyClassroomRoomJson({
    required this.code,
    required this.name,
    required this.fullName,
    required this.capacity,
    required this.sourceUrl,
    this.built = false,
    Map<Day, Set<SectionNumber>>? occupiedByDay,
  }) : occupiedByDay = occupiedByDay ?? <Day, Set<SectionNumber>>{};

  bool isOccupied(Day day, SectionNumber section) => occupiedByDay[day]?.contains(section) ?? false;

  EmptyClassroomRoomJson copyWith({
    String? code,
    String? name,
    String? fullName,
    String? capacity,
    String? sourceUrl,
    bool? built,
    Map<Day, Set<SectionNumber>>? occupiedByDay,
  }) => EmptyClassroomRoomJson(
    code: code ?? this.code,
    name: name ?? this.name,
    fullName: fullName ?? this.fullName,
    capacity: capacity ?? this.capacity,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    built: built ?? this.built,
    occupiedByDay: occupiedByDay ?? this.occupiedByDay,
  );

  factory EmptyClassroomRoomJson.fromJson(Map<String, dynamic> json) {
    final occupied = <Day, Set<SectionNumber>>{};
    final rawOccupied = json['occupiedByDay'];
    if (rawOccupied is Map) {
      for (final entry in rawOccupied.entries) {
        Day? day;
        for (final value in Day.values) {
          if (value.name == entry.key) {
            day = value;
            break;
          }
        }
        if (day == null || entry.value is! List) continue;
        final sections = <SectionNumber>{};
        for (final name in (entry.value as List).whereType<String>()) {
          for (final value in SectionNumber.values) {
            if (value.name == name) {
              sections.add(value);
              break;
            }
          }
        }
        occupied[day] = sections;
      }
    }

    final code = json['code'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    final sourceUrl = json['sourceUrl'] as String? ?? '';
    if (code.isEmpty || name.isEmpty || sourceUrl.isEmpty) {
      throw const FormatException('Malformed empty-classroom room identity');
    }

    return EmptyClassroomRoomJson(
      code: code,
      name: name,
      fullName: json['fullName'] as String? ?? '',
      capacity: json['capacity'] as String? ?? '',
      sourceUrl: sourceUrl,
      built: json['built'] as bool? ?? false,
      occupiedByDay: occupied,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'name': name,
    'fullName': fullName,
    'capacity': capacity,
    'sourceUrl': sourceUrl,
    'built': built,
    'occupiedByDay': occupiedByDay.map(
      (day, sections) => MapEntry(day.name, sections.map((section) => section.name).toList(growable: false)),
    ),
  };
}

class EmptyClassroomSemesterPolicy {
  const EmptyClassroomSemesterPolicy._();

  static List<SemesterJson> newestTwo(Iterable<SemesterJson> semesters) {
    final unique = <String, SemesterJson>{};
    for (final semester in semesters) {
      if (semester.isEmpty) continue;
      unique['${semester.year}-${semester.semester}'] = semester;
    }
    final values = unique.values.toList(growable: false)
      ..sort((a, b) {
        final yearCompare = (int.tryParse(b.year) ?? -1).compareTo(int.tryParse(a.year) ?? -1);
        if (yearCompare != 0) return yearCompare;
        return (int.tryParse(b.semester) ?? -1).compareTo(int.tryParse(a.semester) ?? -1);
      });
    return values.take(2).toList(growable: false);
  }
}

class EmptyClassroomPeriod {
  const EmptyClassroomPeriod._();

  static const List<SectionNumber> order = <SectionNumber>[
    SectionNumber.T_1,
    SectionNumber.T_2,
    SectionNumber.T_3,
    SectionNumber.T_4,
    SectionNumber.T_N,
    SectionNumber.T_5,
    SectionNumber.T_6,
    SectionNumber.T_7,
    SectionNumber.T_8,
    SectionNumber.T_9,
    SectionNumber.T_A,
    SectionNumber.T_B,
    SectionNumber.T_C,
    SectionNumber.T_D,
  ];

  static const Map<SectionNumber, ({int start, int end})> minutes = <SectionNumber, ({int start, int end})>{
    SectionNumber.T_1: (start: 8 * 60 + 10, end: 9 * 60),
    SectionNumber.T_2: (start: 9 * 60 + 10, end: 10 * 60),
    SectionNumber.T_3: (start: 10 * 60 + 10, end: 11 * 60),
    SectionNumber.T_4: (start: 11 * 60 + 10, end: 12 * 60),
    SectionNumber.T_N: (start: 12 * 60 + 10, end: 13 * 60),
    SectionNumber.T_5: (start: 13 * 60 + 10, end: 14 * 60),
    SectionNumber.T_6: (start: 14 * 60 + 10, end: 15 * 60),
    SectionNumber.T_7: (start: 15 * 60 + 10, end: 16 * 60),
    SectionNumber.T_8: (start: 16 * 60 + 10, end: 17 * 60),
    SectionNumber.T_9: (start: 17 * 60 + 10, end: 18 * 60),
    SectionNumber.T_A: (start: 18 * 60 + 30, end: 19 * 60 + 20),
    SectionNumber.T_B: (start: 19 * 60 + 20, end: 20 * 60 + 10),
    SectionNumber.T_C: (start: 20 * 60 + 20, end: 21 * 60 + 10),
    SectionNumber.T_D: (start: 21 * 60 + 10, end: 22 * 60),
  };

  static SectionNumber? at(DateTime dateTime) {
    final minute = dateTime.hour * 60 + dateTime.minute;
    for (final section in order) {
      final range = minutes[section];
      if (range == null) continue;
      if (minute >= range.start && minute < range.end) return section;
    }
    return null;
  }

  static String label(SectionNumber section) => section.name.substring(2);

  static Day dayFromDateTime(DateTime dateTime) {
    switch (dateTime.weekday) {
      case DateTime.monday:
        return Day.Monday;
      case DateTime.tuesday:
        return Day.Tuesday;
      case DateTime.wednesday:
        return Day.Wednesday;
      case DateTime.thursday:
        return Day.Thursday;
      case DateTime.friday:
        return Day.Friday;
      case DateTime.saturday:
        return Day.Saturday;
      default:
        return Day.Sunday;
    }
  }
}
