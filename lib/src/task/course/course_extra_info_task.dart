import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/connector/course_connector.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/src/store/local_storage.dart';

import '../task.dart';
import 'course_system_task.dart';

class CourseExtraInfoTask extends CourseSystemTask<CourseExtraInfoJson> {
  final String id;

  CourseExtraInfoTask(this.id) : super("CourseExtraInfoTask");

  @override
  Future<TaskStatus> execute() async {
    final storage = LocalStorage.instance;
    final cached = storage.getCourseExtraInfoCache(id);
    if (cached != null) {
      Log.d('[CourseExtraInfoTask] cache hit: $id');
      result = cached;
      return TaskStatus.success;
    }

    Log.d('[CourseExtraInfoTask] cache miss: $id');
    final status = await super.execute();

    if (status == TaskStatus.success) {
      super.onStart(R.current.getCourseDetail);
      final value = await CourseConnector.getCourseExtraInfo(id);
      super.onEnd();

      if (value != null) {
        result = value;
        storage.setCourseExtraInfoCache(id, value);
        await Future.wait([storage.saveCourseExtraInfoCache(), storage.saveCourseCategoryCache()]);
        return TaskStatus.success;
      } else {
        return await super.onError(R.current.getCourseDetailError);
      }
    }
    return status;
  }
}
