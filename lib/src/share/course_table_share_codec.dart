import 'dart:convert';
import 'dart:io';

import 'package:qaq_app/src/model/coursetable/course_table_json.dart';

class CourseTableShareCodec {
  static const int version = 1;
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

    final semesters = <String, List<String>>{};
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

      final courseIds = table.getCourseIdList().map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList()
        ..sort();
      if (courseIds.isNotEmpty) semesters[semesterKey] = courseIds;
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

  static int _compareCourseTables(CourseTableJson a, CourseTableJson b) {
    final year = _number(b.courseSemester.year).compareTo(_number(a.courseSemester.year));
    if (year != 0) return year;
    return _number(b.courseSemester.semester).compareTo(_number(a.courseSemester.semester));
  }

  static int _number(String value) => int.tryParse(value.trim()) ?? -1;
}
