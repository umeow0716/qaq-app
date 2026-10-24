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
  List<String>? currCodes,
  List<List<String>>? syllabusCodes,
}) {
  final result = CourseTableJson(
    studentId: studentId,
    studentName: studentName,
    courseSemester: SemesterJson(year: year, semester: semester),
  );
  for (var index = 0; index < courseIds.length; index++) {
    final currentSyllabusCodes = syllabusCodes?[index] ?? <String>[];
    result.setCourseDetailByTime(
      Day.Monday,
      SectionNumber.values[index],
      CourseInfoJson(
        main: CourseMainInfoJson(
          course: CourseMainJson(
            id: courseIds[index],
            href:
                currCodes == null
                    ? ''
                    : 'https://aps.ntut.edu.tw/course/tw/Curr.jsp?format=-2&code=${currCodes[index]}',
            scheduleHref:
                currentSyllabusCodes.isEmpty
                    ? ''
                    : 'https://aps.ntut.edu.tw/course/tw/ShowSyllabus.jsp?snum=${courseIds[index]}&code=${currentSyllabusCodes.first}',
          ),
          teacher:
              currentSyllabusCodes
                  .map(
                    (code) => TeacherJson(
                      href: 'https://aps.ntut.edu.tw/course/tw/Teach.jsp?format=-3&year=$year&sem=$semester&code=$code',
                    ),
                  )
                  .toList(),
        ),
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
          courseIds: <String>['361024', '363589'],
          currCodes: <String>['3314123', '4236123'],
          syllabusCodes: <List<String>>[
            <String>['11126'],
            <String>['11397', '10986'],
          ],
        ),
        table(
          studentId: '12345678',
          studentName: '測試學生',
          year: '114',
          semester: '2',
          courseIds: <String>['361463'],
        ),
        table(
          studentId: '87654321',
          studentName: '其他學生',
          year: '115',
          semester: '1',
          courseIds: <String>['999999'],
        ),
      ],
    );

    final people = payload['people']! as List<dynamic>;
    expect(people, hasLength(1));
    final person = people.single as Map<String, dynamic>;
    expect(person['studentId'], '12345678');
    expect(person['name'], '測試學生');
    expect(person['semesters'], <String, dynamic>{
      '115-1': <Map<String, dynamic>>[
        <String, dynamic>{'snum': '361024', 'currCode': '3314123', 'syllabusCodes': <String>['11126']},
        <String, dynamic>{
          'snum': '363589',
          'currCode': '4236123',
          'syllabusCodes': <String>['10986', '11397'],
        },
      ],
    });
  });

  test('share URL round-trips the gzip compressed JSON payload', () {
    final payload = <String, dynamic>{
      'version': 2,
      'people': <Map<String, dynamic>>[
        <String, dynamic>{
          'studentId': '12345678',
          'name': '測試學生',
          'semesters': <String, dynamic>{
            '115-1': <Map<String, dynamic>>[
              <String, dynamic>{'snum': '361024', 'currCode': '3314123', 'syllabusCodes': <String>['11126']},
            ],
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
