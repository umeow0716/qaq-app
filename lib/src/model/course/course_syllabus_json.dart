import 'package:qaq_app/src/model/json_init.dart';

class CourseSyllabusJson {
  int year = 0;
  int semester = 0;
  String courseId = '';
  String courseName = '';
  int phase = 0;
  double credit = 0;
  int hour = 0;
  String category = '';
  List<String> teachers = <String>[];
  String className = '';
  int applyStudentCount = 0;
  int withdrawStudentCount = 0;
  String note = '';

  CourseSyllabusJson({
    String? yearSemester,
    String? courseId,
    String? courseName,
    String? phase,
    String? credit,
    String? hour,
    String? category,
    String? teachers,
    String? className,
    String? applyStudentCount,
    String? withdrawStudentCount,
    String? note,
  }) {
    final yearSemesterParts = (yearSemester ?? '0-0').split('-');
    year = int.tryParse(yearSemesterParts.isNotEmpty ? yearSemesterParts[0] : '') ?? 0;
    semester = int.tryParse(yearSemesterParts.length > 1 ? yearSemesterParts[1] : '') ?? 0;
    this.courseId = courseId ?? '';
    this.courseName = JsonInit.stringInit(courseName);
    this.phase = int.tryParse(phase ?? '') ?? 0;
    this.credit = double.tryParse(credit ?? '') ?? 0;
    this.hour = int.tryParse(hour ?? '') ?? 0;
    this.category = JsonInit.stringInit(category);
    this.teachers = JsonInit.listInit<String>(teachers?.split('\n'));
    this.className = JsonInit.stringInit(className);
    this.applyStudentCount = int.tryParse(applyStudentCount ?? '') ?? 0;
    this.withdrawStudentCount = int.tryParse(withdrawStudentCount ?? '') ?? 0;
    this.note = JsonInit.stringInit(note);
  }
}
