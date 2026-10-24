import 'dart:convert';
import 'dart:io';

import 'package:qaq_app/src/model/coursetable/course_table_json.dart';

class CourseTableShareCodec {
  static const int version = 2;
  static const String scheme = 'qaq';
  static const String host = 'course-table';
  static const String path = '/share';
  static const String fileExtension = 'qaqschedule';
  static const String mimeType = 'application/vnd.qaq.schedule';

  static Map<String, dynamic> buildPayload({
    required String account,
    required Iterable<CourseTableJson> courseTables,
    Set<String>? semesterKeys,
    String fallbackName = '',
  }) {
    final normalizedAccount = account.trim();
    final ownTables =
        courseTables
            .where((table) => table.studentId.trim() == normalizedAccount)
            .where((table) => table.getCourseIdList().any((id) => id.trim().isNotEmpty))
            .toList()
          ..sort(_compareCourseTables);

    final semesters = <String, List<Map<String, dynamic>>>{};
    var studentName = '';
    for (final table in ownTables) {
      if (table.studentName.trim().isNotEmpty) {
        studentName = table.studentName.trim();
        break;
      }
    }
    if (studentName.isEmpty) studentName = fallbackName.trim();

    for (final table in ownTables) {
      final semesterKey = semesterKeyOf(table);
      if (semesterKeys != null && !semesterKeys.contains(semesterKey)) continue;

      final courses = _courseIdentifiersOf(table);
      if (courses.isNotEmpty) semesters[semesterKey] = courses;
    }

    return <String, dynamic>{
      'version': version,
      'people': <Map<String, dynamic>>[
        <String, dynamic>{'studentId': normalizedAccount, 'name': studentName, 'semesters': semesters},
      ],
    };
  }

  static String encodeUrl(Map<String, dynamic> payload) {
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final compressed = gzip.encode(jsonBytes);
    final encoded = base64UrlEncode(compressed).replaceAll('=', '');
    return Uri(scheme: scheme, host: host, path: path, queryParameters: <String, String>{'data': encoded}).toString();
  }

  static String semesterKeyOf(CourseTableJson table) =>
      '${table.courseSemester.year.trim()}-${table.courseSemester.semester.trim()}';

  static List<Map<String, dynamic>> _courseIdentifiersOf(CourseTableJson table) {
    final courses = <String, Map<String, dynamic>>{};
    final syllabusCodes = <String, Set<String>>{};

    for (final dayMap in table.courseInfoMap.values) {
      for (final courseInfo in dayMap.values) {
        final course = courseInfo.main.course;
        final snum = course.id.trim();
        if (snum.isEmpty) continue;

        final sharedCourse = courses.putIfAbsent(
          snum,
          () => <String, dynamic>{'snum': snum, 'currCode': '', 'syllabusCodes': <String>[]},
        );

        final currCode = _queryCode(course.href, expectedPage: 'Curr.jsp');
        if ((sharedCourse['currCode'] as String).isEmpty && currCode.isNotEmpty) {
          sharedCourse['currCode'] = currCode;
        }

        final codes = syllabusCodes.putIfAbsent(snum, () => <String>{});
        _addQueryCode(codes, course.scheduleHref, expectedPage: 'ShowSyllabus.jsp');
        _addQueryCode(codes, courseInfo.extra.course.href, expectedPage: 'ShowSyllabus.jsp');
        for (final teacher in courseInfo.main.teacher) {
          _addQueryCode(codes, teacher.href, expectedPage: 'Teach.jsp');
        }
      }
    }

    final result = courses.values.toList()
      ..sort((a, b) => (a['snum'] as String).compareTo(b['snum'] as String));
    for (final course in result) {
      final codes = syllabusCodes[course['snum']]?.toList() ?? <String>[];
      codes.sort();
      course['syllabusCodes'] = codes;
    }
    return result;
  }

  static void _addQueryCode(Set<String> codes, String href, {required String expectedPage}) {
    final code = _queryCode(href, expectedPage: expectedPage);
    if (code.isNotEmpty) codes.add(code);
  }

  static String _queryCode(String href, {required String expectedPage}) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null || !uri.path.endsWith(expectedPage)) return '';
    return uri.queryParameters['code']?.trim() ?? '';
  }

  static int _compareCourseTables(CourseTableJson a, CourseTableJson b) {
    final year = _number(b.courseSemester.year).compareTo(_number(a.courseSemester.year));
    if (year != 0) return year;
    return _number(b.courseSemester.semester).compareTo(_number(a.courseSemester.semester));
  }

  static int _number(String value) => int.tryParse(value.trim()) ?? -1;
}
