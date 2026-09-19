import 'dart:convert';

import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/course/course_main_extra_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';

class CourseClassroomCacheJson {
  static const int currentSchemaVersion = 2;

  int schemaVersion;
  String year;
  String semester;
  String courseId;
  DateTime updatedAt;
  String candidateSignature;
  Map<String, String> classroomBySlot;

  CourseClassroomCacheJson({
    this.schemaVersion = currentSchemaVersion,
    required this.year,
    required this.semester,
    required this.courseId,
    required this.updatedAt,
    required this.candidateSignature,
    Map<String, String>? classroomBySlot,
  }) : classroomBySlot = classroomBySlot ?? <String, String>{};

  static String cacheKey(SemesterJson semester, String courseId) => '${semester.year}|${semester.semester}|$courseId';

  static String slotKey(Day day, SectionNumber section) => '${day.name}|${section.name}';

  static String classroomSignature(CourseMainInfoJson main) {
    final candidates = main.classroom.map((classroom) => '${classroom.name.trim()}|${classroom.href.trim()}').toList()
      ..sort();
    return jsonEncode(candidates);
  }

  String? getClassroom(Day day, SectionNumber section) => classroomBySlot[slotKey(day, section)];

  factory CourseClassroomCacheJson.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['classroomBySlot'];
    final slots = <String, String>{};
    if (rawSlots is Map) {
      for (final entry in rawSlots.entries) {
        if (entry.key is String && entry.value is String) {
          slots[entry.key as String] = entry.value as String;
        }
      }
    }

    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    return CourseClassroomCacheJson(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      year: json['year'] as String? ?? '',
      semester: json['semester'] as String? ?? '',
      courseId: json['courseId'] as String? ?? '',
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      candidateSignature: json['candidateSignature'] as String? ?? '',
      classroomBySlot: slots,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'year': year,
    'semester': semester,
    'courseId': courseId,
    'updatedAt': updatedAt.toIso8601String(),
    'candidateSignature': candidateSignature,
    'classroomBySlot': classroomBySlot,
  };
}
