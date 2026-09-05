import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/json_init.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sprintf/sprintf.dart';

part 'course_table_json.g.dart';

// ignore: constant_identifier_names
enum Day { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday, UnKnown }

// ignore: constant_identifier_names
enum SectionNumber { T_1, T_2, T_3, T_4, T_N, T_5, T_6, T_7, T_8, T_9, T_A, T_B, T_C, T_D, T_UnKnown }

@JsonSerializable()
class CourseTableJson {
  SemesterJson courseSemester;
  String studentId;
  String studentName;
  Map<Day, Map<SectionNumber, CourseInfoJson>> courseInfoMap;

  CourseTableJson({
    SemesterJson? courseSemester,
    Map<Day, Map<SectionNumber, CourseInfoJson>>? courseInfoMap,
    String? studentId,
    String? studentName,
  })  : studentId = JsonInit.stringInit(studentId),
        studentName = JsonInit.stringInit(studentName),
        courseSemester = courseSemester ?? SemesterJson(),
        courseInfoMap = courseInfoMap ?? <Day, Map<SectionNumber, CourseInfoJson>>{} {
    for (final day in Day.values) {
      this.courseInfoMap.putIfAbsent(day, () => <SectionNumber, CourseInfoJson>{});
    }
  }

  int getTotalCredit() {
    var credit = 0;
    for (final courseId in getCourseIdList()) {
      credit += getCreditByCourseId(courseId);
    }
    return credit;
  }

  int getCreditByCourseId(String courseId) {
    for (final day in Day.values) {
      for (final number in SectionNumber.values) {
        final courseDetail = courseInfoMap[day]?[number];
        if (courseDetail?.main.course.id == courseId) {
          try {
            return double.parse(courseDetail!.main.course.credits).toInt();
          } catch (_) {
            return 0;
          }
        }
      }
    }
    return 0;
  }

  bool isDayInCourseTable(Day day) {
    for (final number in SectionNumber.values) {
      if (courseInfoMap[day]?[number] != null) return true;
    }
    return false;
  }

  bool isSectionNumberInCourseTable(SectionNumber number) {
    for (final day in Day.values) {
      if (courseInfoMap[day]?.containsKey(number) ?? false) return true;
    }
    return false;
  }

  factory CourseTableJson.fromJson(Map<String, dynamic> json) => _$CourseTableJsonFromJson(json);
  Map<String, dynamic> toJson() => _$CourseTableJsonToJson(this);

  @override
  String toString() {
    var courseInfoString = '';
    for (final day in Day.values) {
      for (final number in SectionNumber.values) {
        courseInfoString += '$day  $number\n';
        courseInfoString += '${courseInfoMap[day]?[number]}\n';
      }
    }
    return sprintf(
        'studentId :%s \n ---------courseSemester-------- \n%s \n---------courseInfo--------     \n%s \n',
        [studentId, courseSemester.toString(), courseInfoString]);
  }

  bool get isEmpty => studentId.isEmpty && courseSemester.isEmpty;

  CourseInfoJson? getCourseDetailByTime(Day day, SectionNumber sectionNumber) => courseInfoMap[day]?[sectionNumber];

  void setCourseDetailByTime(Day day, SectionNumber sectionNumber, CourseInfoJson courseInfo) {
    final dayMap = courseInfoMap.putIfAbsent(day, () => <SectionNumber, CourseInfoJson>{});
    if (day == Day.UnKnown) {
      for (final value in SectionNumber.values) {
        if (courseInfo.main.course.id.isEmpty) continue;
        if (!dayMap.containsKey(value)) {
          dayMap[value] = courseInfo;
          break;
        }
      }
    } else {
      dayMap[sectionNumber] = courseInfo;
    }
  }

  bool setCourseDetailByTimeString(Day day, String sectionNumber, CourseInfoJson courseInfo) {
    var add = false;
    for (final value in SectionNumber.values) {
      final time = value.toString().split('_')[1];
      if (sectionNumber.contains(time)) {
        setCourseDetailByTime(day, value, courseInfo);
        add = true;
      }
    }
    return add;
  }

  List<String> getCourseIdList() {
    final courseIdList = <String>[];
    for (final day in Day.values) {
      for (final number in SectionNumber.values) {
        final courseInfo = courseInfoMap[day]?[number];
        if (courseInfo != null) {
          final id = courseInfo.main.course.id;
          if (!courseIdList.contains(id)) courseIdList.add(id);
        }
      }
    }
    return courseIdList;
  }

  String? getCourseNameByCourseId(String courseId) {
    for (final day in Day.values) {
      for (final number in SectionNumber.values) {
        final courseDetail = courseInfoMap[day]?[number];
        if (courseDetail?.main.course.id == courseId) return courseDetail!.main.course.name;
      }
    }
    return null;
  }

  CourseInfoJson? getCourseInfoByCourseName(String courseName) {
    for (final day in Day.values) {
      for (final number in SectionNumber.values) {
        final courseDetail = courseInfoMap[day]?[number];
        if (courseDetail?.main.course.name == courseName) return courseDetail;
      }
    }
    return null;
  }
}

@JsonSerializable()
class CourseInfoJson {
  CourseMainInfoJson main;
  CourseExtraInfoJson extra;

  CourseInfoJson({CourseMainInfoJson? main, CourseExtraInfoJson? extra})
      : main = main ?? CourseMainInfoJson(),
        extra = extra ?? CourseExtraInfoJson();

  bool get isEmpty => main.isEmpty && extra.isEmpty;

  @override
  String toString() => sprintf(
      '---------main--------  \n%s \n---------extra-------- \n%s \n', [main.toString(), extra.toString()]);

  factory CourseInfoJson.fromJson(Map<String, dynamic> json) => _$CourseInfoJsonFromJson(json);
  Map<String, dynamic> toJson() => _$CourseInfoJsonToJson(this);
}
