import 'package:qaq_app/src/connector/ischool_plus_connector.dart';
import 'package:qaq_app/src/model/ischoolplus/ischool_plus_announcement_json.dart';
import 'package:qaq_app/src/r.dart';

import '../task.dart';
import 'iplus_system_task.dart';

class IPlusCourseAnnouncementDetailTask extends IPlusSystemTask<Map<String, dynamic>> {
  final ISchoolPlusAnnouncementJson data;

  IPlusCourseAnnouncementDetailTask(this.data) : super("lPlusCourseAnnouncementDetailTask");

  @override
  Future<TaskStatus> execute() async {
    final status = await super.execute();
    if (status == TaskStatus.success) {
      super.onStart(R.current.getISchoolPlusCourseAnnouncementDetail);
      final value = await ISchoolPlusConnector.getCourseAnnouncementDetail(data);
      super.onEnd();
      if (value != null) {
        result = Map<String, dynamic>.from(value);
        return TaskStatus.success;
      } else {
        return super.onError(R.current.getISchoolPlusCourseAnnouncementDetailError);
      }
    }
    return status;
  }
}
