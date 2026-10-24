import 'package:qaq_app/src/model/course/course_class_json.dart';

class CourseTableShareCourse {
  const CourseTableShareCourse({required this.snum, required this.currCode, required this.syllabusCodes});

  final String snum;
  final String currCode;
  final List<String> syllabusCodes;

  factory CourseTableShareCourse.fromJson(Object? value) {
    if (value is String) {
      return CourseTableShareCourse(snum: value.trim(), currCode: '', syllabusCodes: const <String>[]);
    }
    if (value is! Map) throw const FormatException('Invalid shared course');
    final map = value.cast<String, dynamic>();
    final syllabusValue = map['syllabusCodes'];
    final syllabusCodes = syllabusValue is List
        ? syllabusValue.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList()
        : <String>[];
    return CourseTableShareCourse(
      snum: (map['snum'] ?? '').toString().trim(),
      currCode: (map['currCode'] ?? '').toString().trim(),
      syllabusCodes: syllabusCodes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'snum': snum,
    'currCode': currCode,
    'syllabusCodes': syllabusCodes,
  };
}

class CourseTableSharePerson {
  CourseTableSharePerson({
    required this.studentId,
    required this.name,
    required Map<String, List<CourseTableShareCourse>> semesters,
  }) : semesters = Map<String, List<CourseTableShareCourse>>.unmodifiable(
         semesters.map((key, value) => MapEntry(key, List<CourseTableShareCourse>.unmodifiable(value))),
       );

  final String studentId;
  final String name;
  final Map<String, List<CourseTableShareCourse>> semesters;

  factory CourseTableSharePerson.fromJson(Map<String, dynamic> map) {
    final semesterValue = map['semesters'];
    if (semesterValue is! Map) throw const FormatException('Invalid shared semesters');

    final semesters = <String, List<CourseTableShareCourse>>{};
    for (final entry in semesterValue.entries) {
      final value = entry.value;
      if (value is! List) continue;
      final courses = <CourseTableShareCourse>[];
      for (final courseValue in value) {
        final course = CourseTableShareCourse.fromJson(courseValue);
        if (course.snum.isNotEmpty || course.currCode.isNotEmpty) courses.add(course);
      }
      if (courses.isNotEmpty) semesters[entry.key.toString()] = courses;
    }

    return CourseTableSharePerson(
      studentId: (map['studentId'] ?? '').toString().trim(),
      name: (map['name'] ?? '').toString().trim(),
      semesters: semesters,
    );
  }

  static List<CourseTableSharePerson> fromPayload(Map<String, dynamic> payload) {
    final peopleValue = payload['people'];
    if (peopleValue is! List) throw const FormatException('Invalid shared people');

    final people = <CourseTableSharePerson>[];
    for (final value in peopleValue) {
      if (value is! Map) continue;
      final person = CourseTableSharePerson.fromJson(value.cast<String, dynamic>());
      if (person.studentId.isNotEmpty && person.semesters.isNotEmpty) people.add(person);
    }
    return people;
  }

  List<SemesterJson> get semesterList {
    final result = semesters.keys.map(_semesterFromKey).whereType<SemesterJson>().toList()
      ..sort((a, b) {
        final year = (int.tryParse(b.year) ?? -1).compareTo(int.tryParse(a.year) ?? -1);
        if (year != 0) return year;
        return (int.tryParse(b.semester) ?? -1).compareTo(int.tryParse(a.semester) ?? -1);
      });
    return result;
  }

  List<CourseTableShareCourse> coursesForSemester(SemesterJson semester) =>
      semesters['${semester.year.trim()}-${semester.semester.trim()}'] ?? const <CourseTableShareCourse>[];

  bool matches(String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return true;
    return studentId.toLowerCase().contains(query) || name.toLowerCase().contains(query);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'studentId': studentId,
    'name': name,
    'semesters': semesters.map((key, value) => MapEntry(key, value.map((course) => course.toJson()).toList())),
  };

  static SemesterJson? _semesterFromKey(String value) {
    final parts = value.split('-');
    if (parts.length != 2 || int.tryParse(parts[0]) == null || int.tryParse(parts[1]) == null) return null;
    return SemesterJson(year: parts[0], semester: parts[1]);
  }
}
