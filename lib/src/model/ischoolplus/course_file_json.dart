import 'package:qaq_app/src/model/json_init.dart';
import 'package:intl/intl.dart';

enum CourseFileType { pdf, word, powerPoint, excel, rar, link, unknown }

class CourseFileJson {
  String name;
  DateTime time;
  List<FileType> fileType;

  CourseFileJson({String? name, List<FileType>? fileType, DateTime? time})
    : name = JsonInit.stringInit(name),
      fileType = fileType ?? <FileType>[],
      time = time ?? DateTime.now();

  String get timeString {
    final formatter = DateFormat.yMd();
    return formatter.format(time);
  }
}

class FileType {
  CourseFileType type;
  String href;
  dynamic postData;

  FileType({CourseFileType? type, String? href})
    : type = type ?? CourseFileType.unknown,
      href = JsonInit.stringInit(href);

  String get fileUrl => href;
}
