import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/course/course_main_extra_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/share/course_table_share_codec.dart';

CourseTableJson table({
  required String studentId,
  required String studentName,
  required String year,
  required String semester,
  required List<String> courseIds,
}) {
  final result = CourseTableJson(
    studentId: studentId,
    studentName: studentName,
    courseSemester: SemesterJson(year: year, semester: semester),
  );
  for (var index = 0; index < courseIds.length; index++) {
    result.setCourseDetailByTime(
      Day.Monday,
      SectionNumber.values[index],
      CourseInfoJson(
        main: CourseMainInfoJson(course: CourseMainJson(id: courseIds[index])),
      ),
    );
  }
  return result;
}

void main() {
  test('exports only the signed-in student and selected semesters', () {
    final payload = CourseTableShareCodec.buildPayload(
      account: '12345678',
      semesterKeys: <String>{'115-1'},
      courseTables: <CourseTableJson>[
        table(
          studentId: '12345678',
          studentName: '測試學生',
          year: '115',
          semester: '1',
          courseIds: <String>['371933', '371934'],
        ),
        table(studentId: '12345678', studentName: '測試學生', year: '114', semester: '2', courseIds: <String>['361463']),
        table(studentId: '87654321', studentName: '其他學生', year: '115', semester: '1', courseIds: <String>['999999']),
      ],
    );

    final people = payload['people']! as List<dynamic>;
    expect(people, hasLength(1));
    final person = people.single as Map<String, dynamic>;
    expect(person['studentId'], '12345678');
    expect(person['name'], '測試學生');
    expect(person['semesters'], <String, dynamic>{
      '115-1': <String>['371933', '371934'],
    });
  });

  test('share URL round-trips the gzip compressed JSON payload', () {
    final payload = <String, dynamic>{
      'version': 1,
      'people': <Map<String, dynamic>>[
        <String, dynamic>{
          'studentId': '12345678',
          'name': '測試學生',
          'semesters': <String, dynamic>{
            '115-1': <String>['371933', '371934'],
          },
        },
      ],
    };

    final url = CourseTableShareCodec.encodeUrl(payload);
    final uri = Uri.parse(url);
    final encoded = uri.queryParameters['data']!;
    final padded = encoded.padRight(encoded.length + ((4 - encoded.length % 4) % 4), '=');
    final decoded = jsonDecode(utf8.decode(gzip.decode(base64Url.decode(padded))));

    expect(uri.scheme, CourseTableShareCodec.scheme);
    expect(uri.host, CourseTableShareCodec.host);
    expect(uri.path, CourseTableShareCodec.path);
    expect(decoded, payload);
  });
}
