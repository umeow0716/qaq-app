import 'package:flutter_app/src/model/coursetable/course_table_json.dart';
import 'package:flutter_app/src/model/json_init.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sprintf/sprintf.dart';

part 'setting_json.g.dart';

@JsonSerializable()
class SettingJson {
  CourseSettingJson course;
  OtherSettingJson other;
  AnnouncementSettingJson announcement;

  SettingJson({CourseSettingJson? course, OtherSettingJson? other, AnnouncementSettingJson? announcement})
    : course = course ?? CourseSettingJson(),
      other = other ?? OtherSettingJson(),
      announcement = announcement ?? AnnouncementSettingJson();

  bool get isEmpty => course.isEmpty && other.isEmpty && announcement.isEmpty;

  @override
  String toString() => sprintf(
    '---------course--------        \n%s \n---------other--------         \n%s \n---------announcement--------  \n%s \n',
    [course.toString(), other.toString(), announcement.toString()],
  );

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
class AnnouncementSettingJson {
  int page;
  int maxPage;

  AnnouncementSettingJson({this.page = 0, this.maxPage = 0});

  bool get isEmpty => page == 0 && maxPage == 0;

  @override
  String toString() => sprintf('page      :%s \n maxPage   :%s \n ', [page.toString(), maxPage.toString()]);

  factory AnnouncementSettingJson.fromJson(Map<String, dynamic> json) => _$AnnouncementSettingJsonFromJson(json);
  Map<String, dynamic> toJson() => _$AnnouncementSettingJsonToJson(this);
}

@JsonSerializable()
class OtherSettingJson {
  String lang;
  bool autoCheckAppUpdate;
  bool useExternalVideoPlayer;
  bool checkIPlusNew;

  OtherSettingJson({
    String? lang,
    this.autoCheckAppUpdate = true,
    this.useExternalVideoPlayer = false,
    this.checkIPlusNew = true,
  }) : lang = JsonInit.stringInit(lang);

  bool get isEmpty => lang.isEmpty;

  @override
  String toString() => sprintf('lang      :%s \n ', [lang]);

  factory OtherSettingJson.fromJson(Map<String, dynamic> json) => _$OtherSettingJsonFromJson(json);
  Map<String, dynamic> toJson() => _$OtherSettingJsonToJson(this);
}
