import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/model/json_init.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sprintf/sprintf.dart';

part 'setting_json.g.dart';

@JsonSerializable()
class SettingJson {
  CourseSettingJson course;
  OtherSettingJson other;

  SettingJson({CourseSettingJson? course, OtherSettingJson? other})
    : course = course ?? CourseSettingJson(),
      other = other ?? OtherSettingJson();

  bool get isEmpty => course.isEmpty && other.isEmpty;

  @override
  String toString() => sprintf('---------course--------        \n%s \n---------other--------         \n%s \n', [
    course.toString(),
    other.toString(),
  ]);

  factory SettingJson.fromJson(Map<String, dynamic> json) => _$SettingJsonFromJson(json);
  Map<String, dynamic> toJson() => _$SettingJsonToJson(this);
}

@JsonSerializable()
class CourseSettingJson {
  CourseTableJson info;

  CourseSettingJson({CourseTableJson? info}) : info = info ?? CourseTableJson();

  bool get isEmpty => info.isEmpty;

  @override
  String toString() => sprintf('---------courseInfo--------       :\n%s \n', [info.toString()]);

  factory CourseSettingJson.fromJson(Map<String, dynamic> json) => _$CourseSettingJsonFromJson(json);
  Map<String, dynamic> toJson() => _$CourseSettingJsonToJson(this);
}

@JsonSerializable()
class OtherSettingJson {
  String lang;
  bool useExternalVideoPlayer;
  bool checkIPlusNew;
  bool autoConnectIStudyVpn;

  OtherSettingJson({
    String? lang,
    this.useExternalVideoPlayer = false,
    this.checkIPlusNew = true,
    this.autoConnectIStudyVpn = false,
  }) : lang = JsonInit.stringInit(lang);

  bool get isEmpty => lang.isEmpty;

  @override
  String toString() => sprintf('lang      :%s \n ', [lang]);

  factory OtherSettingJson.fromJson(Map<String, dynamic> json) => _$OtherSettingJsonFromJson(json);
  Map<String, dynamic> toJson() => _$OtherSettingJsonToJson(this);
}
