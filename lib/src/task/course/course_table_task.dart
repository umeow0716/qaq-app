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
    if (status == TaskStatus.success) {
      super.onStart(R.current.getCourse);
      CourseMainInfo? value;
      if (studentId.length == 5) {
        value = await CourseConnector.getTWTeacherCourseMainInfoList(studentId, semester);
      } else {
        if (LanguageUtil.getLangIndex() == LangEnum.zh) {
          value = await CourseConnector.getTWCourseMainInfoList(studentId, semester);
        } else {
          value = await CourseConnector.getENCourseMainInfoList(studentId, semester);
        }
      }
      super.onEnd();
      if (value != null) {
        final courseTable = CourseTableJson();
        courseTable.courseSemester = semester;
        courseTable.studentId = studentId;
        courseTable.studentName = value.studentName;

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

          bool add = false;
          for (int i = 0; i < 7; i++) {
            final day = Day.values[i];
            final time = courseMainInfo.course.time[day];
            courseInfo.main = courseMainInfo;
            add |= courseTable.setCourseDetailByTimeString(day, time ?? '', courseInfo);
          }
          if (!add) {
            courseTable.setCourseDetailByTime(Day.UnKnown, SectionNumber.T_UnKnown, courseInfo);
          }
        }
        if (studentId == storage.getAccount()) {
          //只儲存自己的課表，並把同一次 request 已解析出的課程 metadata
          // 一起寫入共用 ExtraInfo cache。
          storage.addCourseTable(courseTable);
          await Future.wait([storage.saveCourseTableList(), storage.saveCourseExtraInfoCache()]);
        }
        result = courseTable;
        return TaskStatus.success;
      } else {
        return super.onError(R.current.getCourseError);
      }
    }
    return status;
  }
}
