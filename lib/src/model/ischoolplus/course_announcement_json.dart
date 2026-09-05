import 'package:flutter_app/src/model/json_init.dart';

class CourseAnnouncementJson {
  String title;
  String detail;

  CourseAnnouncementJson({String? title, String? detail})
      : title = JsonInit.stringInit(title),
        detail = JsonInit.stringInit(detail);
}
