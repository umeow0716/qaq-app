import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/course/course_main_extra_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/share/course_table_share_data.dart';
import 'package:qaq_app/src/store/local_storage.dart';

import '../task.dart';
import 'course_system_task.dart';

class SharedCourseTableTask extends CourseSystemTask<CourseTableJson> {
  SharedCourseTableTask(this.person, this.semester) : super('SharedCourseTableTask');

  final CourseTableSharePerson person;
  final SemesterJson semester;

  @override
  Future<TaskStatus> execute() async {
    final status = await super.execute();
    if (status != TaskStatus.success) return status;

    final sharedCourses = person.coursesForSemester(semester);
    if (sharedCourses.isEmpty) return super.onError(R.current.getCourseError);

    super.onStart(R.current.getCourse);
    final courseTable = CourseTableJson(
      courseSemester: semester,
      studentId: person.studentId,
      studentName: person.name,
    );
    final storage = LocalStorage.instance;
    var resolvedCourses = 0;

    for (final sharedCourse in sharedCourses) {
      final main = await CourseConnector.getTWCourseMainInfoByShareIdentifier(sharedCourse, semester);
      if (main == null || main.course.id.isEmpty) continue;

      resolvedCourses++;
      final courseInfo = CourseInfoJson(main: main);
      final tableMetadata = CourseExtraInfoJson(
        courseSemester: semester,
        course: CourseExtraJson(
          id: main.course.id,
          name: main.course.name,
          href: main.course.scheduleHref,
          openClass: main.getOpenClassName(),
        ),
      );
      storage.setCourseExtraInfoCache(main.course.id, tableMetadata);
      courseInfo.extra = storage.getCourseExtraInfoCache(main.course.id) ?? tableMetadata;

      var added = false;
      for (var index = 0; index < 7; index++) {
        final day = Day.values[index];
        added |= courseTable.setCourseDetailByTimeString(day, main.course.time[day] ?? '', courseInfo);
      }
      if (!added) {
        courseTable.setCourseDetailByTime(Day.UnKnown, SectionNumber.T_UnKnown, courseInfo);
      }
    }
    super.onEnd();

    if (resolvedCourses == 0) return super.onError(R.current.getCourseError);

    storage.addCourseTable(courseTable);
    await Future.wait(<Future<void>>[storage.saveCourseTableList(), storage.saveCourseExtraInfoCache()]);
    result = courseTable;
    return TaskStatus.success;
  }
}
