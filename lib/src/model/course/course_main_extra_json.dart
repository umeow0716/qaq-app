import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sprintf/sprintf.dart';

part 'course_main_extra_json.g.dart';

@JsonSerializable()
class CourseExtraInfoJson {
  SemesterJson courseSemester;
  CourseExtraJson course;
  List<ClassmateJson> classmate;
  DateTime? classmateUpdatedAt;
  DateTime? courseExtraUpdatedAt;

  CourseExtraInfoJson({
    SemesterJson? courseSemester,
    CourseExtraJson? course,
    List<ClassmateJson>? classmate,
    this.classmateUpdatedAt,
    this.courseExtraUpdatedAt,
  }) : classmate = classmate ?? <ClassmateJson>[],
       courseSemester = courseSemester ?? SemesterJson(),
       course = course ?? CourseExtraJson();

  bool get isEmpty =>
      classmate.isEmpty &&
      classmateUpdatedAt == null &&
      courseExtraUpdatedAt == null &&
      courseSemester.isEmpty &&
      course.isEmpty;

  @override
  String toString() => sprintf(
    '---------courseSemester--------  \n%s \n---------course--------          \n%s \n---------classmateList--------   \n%s \n',
    [courseSemester.toString(), course.toString(), classmate.toString()],
  );

  factory CourseExtraInfoJson.fromJson(Map<String, dynamic> json) => _$CourseExtraInfoJsonFromJson(json);
  Map<String, dynamic> toJson() => _$CourseExtraInfoJsonToJson(this);
}

@JsonSerializable()
class CourseMainInfoJson {
  CourseMainJson course;
  List<TeacherJson> teacher;
  List<ClassroomJson> classroom;
  List<ClassJson> openClass;

  CourseMainInfoJson({
    CourseMainJson? course,
    List<TeacherJson>? teacher,
    List<ClassroomJson>? classroom,
    List<ClassJson>? openClass,
  }) : course = course ?? CourseMainJson(),
       teacher = teacher ?? <TeacherJson>[],
       classroom = classroom ?? <ClassroomJson>[],
       openClass = openClass ?? <ClassJson>[];

  String getOpenClassName() => openClass.map((value) => value.name).join(' ');
  String getTeacherName() => teacher.map((value) => value.name).join(' ');
  String getClassroomName() => classroom.map((value) => value.name).join(' ');
  List<String> getClassroomNameList() => classroom.map((value) => value.name).toList();
  List<String> getClassroomHrefList() => classroom.map((value) => value.href).toList();

  bool get isEmpty => course.isEmpty && teacher.isEmpty && classroom.isEmpty && openClass.isEmpty;

  @override
  String toString() => sprintf(
    '---------course--------         \n%s \n---------teacherList--------    \n%s \n---------classroomList--------  \n%s \n---------openClassList--------  \n%s \n',
    [course.toString(), teacher.toString(), classroom.toString(), openClass.toString()],
  );

  factory CourseMainInfoJson.fromJson(Map<String, dynamic> json) => _$CourseMainInfoJsonFromJson(json);
  Map<String, dynamic> toJson() => _$CourseMainInfoJsonToJson(this);
}
