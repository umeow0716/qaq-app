import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/r.dart';

import '../task.dart';
import 'course_system_task.dart';

class CourseYearTask extends CourseSystemTask<List<String>> {
  CourseYearTask() : super("CourseYearTask");

  @override
  Future<TaskStatus> execute() async {
    final status = await super.execute();
    if (status == TaskStatus.success) {
      super.onStart(R.current.searchingYear);
      final List<String>? value = await CourseConnector.getYearList();
      super.onEnd();
      if (value != null) {
        result = value;
        return TaskStatus.success;
      } else {
        return TaskStatus.shouldGiveUp;
      }
    }
    return status;
  }
}
