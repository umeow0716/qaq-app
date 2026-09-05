import 'package:flutter_app/src/model/coursetable/course_table_json.dart';
import 'package:flutter_app/src/model/json_init.dart';
import 'package:flutter_app/src/util/language_util.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sprintf/sprintf.dart';

part 'course_class_json.g.dart';

@JsonSerializable()
class CourseMainJson {
  String name;
  String id;
  String href;
  String note;
  String stage;
  String credits;
  String hours;
  String scheduleHref;
  Map<Day, String> time;

  CourseMainJson({
    String? name,
    String? href,
    String? id,
    String? credits,
    String? hours,
    String? stage,
    String? note,
    Map<Day, String>? time,
    String? scheduleHref,
  }) : name = JsonInit.stringInit(name),
       id = JsonInit.stringInit(id),
       href = JsonInit.stringInit(href),
       note = JsonInit.stringInit(note),
       stage = JsonInit.stringInit(stage),
       credits = JsonInit.stringInit(credits),
       hours = JsonInit.stringInit(hours),
       scheduleHref = JsonInit.stringInit(scheduleHref),
       time = time ?? <Day, String>{};

  bool get isEmpty =>
      name.isEmpty &&
      href.isEmpty &&
      note.isEmpty &&
      stage.isEmpty &&
      credits.isEmpty &&
      hours.isEmpty &&
      scheduleHref.isEmpty;

  @override
  String toString() => sprintf(
    'name    :%s \nid      :%s \nhref    :%s \nstage   :%s \ncredits :%s \nhours   :%s \nscheduleHref   :%s \nnote    :%s \n',
    [name, id, href, stage, credits, hours, scheduleHref, note],
  );

  factory CourseMainJson.fromJson(Map<String, dynamic> json) => _$CourseMainJsonFromJson(json);
  Map<String, dynamic> toJson() => _$CourseMainJsonToJson(this);
}

@JsonSerializable()
class CourseExtraJson {
  String id;
  String name;
  String href;
  String category;
  String selectNumber;
  String withdrawNumber;
  String openClass;

  CourseExtraJson({
    String? id,
    String? name,
    String? category,
    String? selectNumber,
    String? withdrawNumber,
    String? href,
    String? openClass,
  }) : id = JsonInit.stringInit(id),
       name = JsonInit.stringInit(name),
       href = JsonInit.stringInit(href),
       category = JsonInit.stringInit(category),
       selectNumber = JsonInit.stringInit(selectNumber),
       withdrawNumber = JsonInit.stringInit(withdrawNumber),
       openClass = JsonInit.stringInit(openClass);

  bool get isEmpty =>
      id.isEmpty &&
      name.isEmpty &&
      category.isEmpty &&
      selectNumber.isEmpty &&
      withdrawNumber.isEmpty &&
      openClass.isEmpty;

  @override
  String toString() => sprintf(
    'id             :%s \nname           :%s \ncategory       :%s \nselectNumber   :%s \nwithdrawNumber :%s \nopenClass :%s \n',
    [id, name, category, selectNumber, withdrawNumber, openClass],
  );

  factory CourseExtraJson.fromJson(Map<String, dynamic> json) => _$CourseExtraJsonFromJson(json);
  Map<String, dynamic> toJson() => _$CourseExtraJsonToJson(this);
}

@JsonSerializable()
class ClassJson {
  String name;
  String href;

  ClassJson({String? name, String? href}) : name = JsonInit.stringInit(name), href = JsonInit.stringInit(href);

  bool get isEmpty => name.isEmpty && href.isEmpty;

  @override
  String toString() => sprintf('name : %s \nhref : %s \n', [name, href]);

  factory ClassJson.fromJson(Map<String, dynamic> json) => _$ClassJsonFromJson(json);
  Map<String, dynamic> toJson() => _$ClassJsonToJson(this);
}

@JsonSerializable()
class ClassroomJson {
  String name;
  String href;
  bool mainUse;

  ClassroomJson({String? name, String? href, this.mainUse = false})
    : name = JsonInit.stringInit(name),
      href = JsonInit.stringInit(href);

  bool get isEmpty => name.isEmpty && href.isEmpty;

  @override
  String toString() => sprintf('name    : %s \nhref    : %s \nmainUse : %s \n', [name, href, mainUse.toString()]);

  factory ClassroomJson.fromJson(Map<String, dynamic> json) => _$ClassroomJsonFromJson(json);
  Map<String, dynamic> toJson() => _$ClassroomJsonToJson(this);
}

@JsonSerializable()
class TeacherJson {
  String name;
  String href;

  TeacherJson({String? name, String? href}) : name = JsonInit.stringInit(name), href = JsonInit.stringInit(href);

  bool get isEmpty => name.isEmpty && href.isEmpty;

  @override
  String toString() => sprintf('name : %s \nhref : %s \n', [name, href]);

  factory TeacherJson.fromJson(Map<String, dynamic> json) => _$TeacherJsonFromJson(json);
  Map<String, dynamic> toJson() => _$TeacherJsonToJson(this);
}

@JsonSerializable()
class SemesterJson {
  String year;
  String semester;

  SemesterJson({String? year, String? semester})
    : year = JsonInit.stringInit(year),
      semester = JsonInit.stringInit(semester);

  factory SemesterJson.fromJson(Map<String, dynamic> json) => _$SemesterJsonFromJson(json);
  Map<String, dynamic> toJson() => _$SemesterJsonToJson(this);

  bool get isEmpty => year.isEmpty && semester.isEmpty;

  @override
  String toString() => sprintf('year     : %s \nsemester : %s \n', [year, semester]);

  @override
  bool operator ==(Object other) {
    if (other is! SemesterJson) return false;
    return int.tryParse(other.semester) == int.tryParse(semester) && int.tryParse(other.year) == int.tryParse(year);
  }

  @override
  int get hashCode => Object.hashAll([semester.hashCode, year.hashCode]);
}

@JsonSerializable()
class ClassmateJson {
  String className;
  String studentEnglishName;
  String studentName;
  String studentId;
  String href;
  bool isSelect;

  ClassmateJson({
    String? className,
    String? studentEnglishName,
    String? studentName,
    String? studentId,
    this.isSelect = false,
    String? href,
  }) : className = JsonInit.stringInit(className),
       studentEnglishName = JsonInit.stringInit(studentEnglishName),
       studentName = JsonInit.stringInit(studentName),
       studentId = JsonInit.stringInit(studentId),
       href = JsonInit.stringInit(href);

  bool get isEmpty =>
      className.isEmpty && studentEnglishName.isEmpty && studentName.isEmpty && studentId.isEmpty && href.isEmpty;

  @override
  String toString() => sprintf(
    'className           : %s \nstudentEnglishName  : %s \nstudentName         : %s \nstudentId           : %s \nhref                : %s \nisSelect            : %s \n',
    [className, studentEnglishName, studentName, studentId, href, isSelect.toString()],
  );

  String getName() {
    var name = LanguageUtil.getLangIndex() == LangEnum.en ? studentEnglishName : studentName;
    if (!name.contains(RegExp(r'\w'))) name = studentName;
    return name;
  }

  factory ClassmateJson.fromJson(Map<String, dynamic> json) => _$ClassmateJsonFromJson(json);
  Map<String, dynamic> toJson() => _$ClassmateJsonToJson(this);
}
