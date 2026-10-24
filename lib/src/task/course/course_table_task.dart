import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/course/course_main_extra_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/util/language_util.dart';

import '../task.dart';
import 'course_system_task.dart';

class CourseTableTask extends CourseSystemTask<CourseTableJson> {
  final String studentId;
  final SemesterJson semester;

  CourseTableTask(this.studentId, this.semester) : super("CourseTableTask");

  @override
  Future<TaskStatus> execute() async {
    final status = await super.execute();
    if (status != TaskStatus.success) return status;

    super.onStart(R.current.getCourse);
    final courseTable = await loadAfterLogin();
    super.onEnd();
    if (courseTable == null) return super.onError(R.current.getCourseError);

    result = courseTable;
    return TaskStatus.success;
  }

  /// Loads one semester after the course-system session has already been
  /// authenticated. Batch callers can use the shared request pool without
  /// racing CourseSystemTask's shared login state.
  Future<CourseTableJson?> loadAfterLogin({Duration? timeout, bool persist = true}) async {
    final value = await _fetchCourseMainInfo(timeout: timeout);
    if (value == null) return null;

    final courseTable = _buildCourseTable(value);
    if (persist) {
      final storage = LocalStorage.instance;
      if (studentId == storage.getAccount()) {
        // Only own schedules belong to favorites/storage. Imported schedules
        // have a separate cache.
        storage.addCourseTable(courseTable);
        await Future.wait([storage.saveCourseTableList(), storage.saveCourseExtraInfoCache()]);
      }
    }
    return courseTable;
  }

  Future<CourseMainInfo?> _fetchCourseMainInfo({Duration? timeout}) {
    if (studentId.length == 5) {
      return CourseConnector.getTWTeacherCourseMainInfoList(studentId, semester, timeout: timeout);
    }
    if (LanguageUtil.getLangIndex() == LangEnum.zh) {
      return CourseConnector.getTWCourseMainInfoList(studentId, semester, timeout: timeout);
    }
    return CourseConnector.getENCourseMainInfoList(studentId, semester, timeout: timeout);
  }

  CourseTableJson _buildCourseTable(CourseMainInfo value) {
    final courseTable = CourseTableJson(
      courseSemester: semester,
      studentId: studentId,
      studentName: value.studentName,
    );
    final storage = LocalStorage.instance;

    for (final courseMainInfo in value.json) {
      final courseInfo = CourseInfoJson();
      final courseId = courseMainInfo.course.id;
      if (courseId.isNotEmpty) {
        final tableMetadata = CourseExtraInfoJson(
          courseSemester: semester,
          course: CourseExtraJson(
            id: courseId,
            name: courseMainInfo.course.name,
            href: courseMainInfo.course.scheduleHref,
            openClass: courseMainInfo.getOpenClassName(),
          ),
        );
        storage.setCourseExtraInfoCache(courseId, tableMetadata);
        courseInfo.extra = storage.getCourseExtraInfoCache(courseId) ?? tableMetadata;
      }

      var add = false;
      for (var i = 0; i < 7; i++) {
        final day = Day.values[i];
        final time = courseMainInfo.course.time[day];
        courseInfo.main = courseMainInfo;
        add |= courseTable.setCourseDetailByTimeString(day, time ?? '', courseInfo);
      }
      if (!add) {
        courseTable.setCourseDetailByTime(Day.UnKnown, SectionNumber.T_UnKnown, courseInfo);
      }
    }

    return courseTable;
  }
}
