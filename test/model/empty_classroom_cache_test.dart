import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/model/coursetable/empty_classroom_cache.dart';

void main() {
  group('EmptyClassroomPeriod', () {
    test('uses exact NTUT period intervals and treats gaps as free', () {
      final day = DateTime(2026, 10, 25);
      expect(EmptyClassroomPeriod.at(DateTime(day.year, day.month, day.day, 8, 10)), SectionNumber.T_1);
      expect(EmptyClassroomPeriod.at(DateTime(day.year, day.month, day.day, 9, 0)), isNull);
      expect(EmptyClassroomPeriod.at(DateTime(day.year, day.month, day.day, 9, 5)), isNull);
      expect(EmptyClassroomPeriod.at(DateTime(day.year, day.month, day.day, 12, 10)), SectionNumber.T_N);
      expect(EmptyClassroomPeriod.at(DateTime(day.year, day.month, day.day, 18, 20)), isNull);
      expect(EmptyClassroomPeriod.at(DateTime(day.year, day.month, day.day, 19, 20)), SectionNumber.T_B);
      expect(EmptyClassroomPeriod.at(DateTime(day.year, day.month, day.day, 20, 15)), isNull);
      expect(EmptyClassroomPeriod.at(DateTime(day.year, day.month, day.day, 22, 0)), isNull);
    });
  });

  group('EmptyClassroomSemesterPolicy', () {
    test('keeps only the two newest semesters exposed by the home page', () {
      final semesters = EmptyClassroomSemesterPolicy.newestTwo(<SemesterJson>[
        SemesterJson(year: '114', semester: '2'),
        SemesterJson(year: '115', semester: '2'),
        SemesterJson(year: '115', semester: '1'),
        SemesterJson(year: '115', semester: '2'),
      ]);

      expect(semesters, <SemesterJson>[
        SemesterJson(year: '115', semester: '2'),
        SemesterJson(year: '115', semester: '1'),
      ]);
    });
  });

  test('cache round-trips build state and occupancy', () {
    final cache = EmptyClassroomCacheJson(
      year: '115',
      semester: '1',
      language: 'zh',
      complete: true,
      updatedAt: DateTime(2026, 10, 25),
      rooms: [
        EmptyClassroomRoomJson(
          code: '493',
          name: '一教1F(e)',
          fullName: '一教1F多功能教室',
          capacity: '48',
          sourceUrl: 'https://example.test/Croom.jsp?code=493',
          built: true,
          occupiedByDay: {
            Day.Tuesday: {SectionNumber.T_3, SectionNumber.T_4},
          },
        ),
      ],
    );

    final decoded = EmptyClassroomCacheJson.fromJson(cache.toJson());
    expect(decoded.complete, isTrue);
    expect(decoded.builtCount, 1);
    expect(decoded.rooms.single.isOccupied(Day.Tuesday, SectionNumber.T_3), isTrue);
    expect(decoded.rooms.single.isOccupied(Day.Tuesday, SectionNumber.T_5), isFalse);
  });
}
