import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/r.dart';

import '../task.dart';
import 'course_system_task.dart';

class CourseDepartmentMapTask extends CourseSystemTask<Map<String, String>> {
  final String year;
  final String semester;

  CourseDepartmentMapTask({required this.year, required this.semester}) : super("CourseDepartmentMapTask");

  @override
  Future<TaskStatus> execute() async {
    final status = await super.execute();
    if (status == TaskStatus.success) {
      super.onStart(R.current.searchingCreditInfo);
      final value = await CourseConnector.getDepartmentMap(year, semester);
      final twoYearProgramDepartmentMap = await CourseConnector.getTwoYearUndergraduateDepartmentMap(year);
      super.onEnd();

      final collection = <String, String>{};
      if (value != null) {
        collection.addAll(value);
      }
      if (twoYearProgramDepartmentMap != null) {
        collection.addAll(twoYearProgramDepartmentMap);
      }

      if (collection.isNotEmpty) {
        result = collection;
        return TaskStatus.success;
      } else {
        return TaskStatus.shouldGiveUp;
      }
    }
    return status;
  }
}
