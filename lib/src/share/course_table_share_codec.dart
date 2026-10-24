import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:qaq_app/src/model/coursetable/course_table_json.dart';

class CourseTableShareCodec {
  static const int version = 3;
  static const String scheme = 'qaq';
  static const String host = 'course-table';
  static const String path = '/share';
  static const String fileExtension = 'qaqschedule';
  static const String mimeType = 'application/vnd.qaq.schedule';

  static Map<String, dynamic> buildPayload({
    required String account,
    required Iterable<CourseTableJson> courseTables,
    Set<String>? semesterKeys,
    String fallbackName = '',
  }) {
    final normalizedAccount = account.trim();
    final ownTables =
        courseTables
            .where((table) => table.studentId.trim() == normalizedAccount)
            .where((table) => table.getCourseIdList().any((id) => id.trim().isNotEmpty))
            .toList()
          ..sort(_compareCourseTables);

    final semesters = <String, List<Map<String, dynamic>>>{};
    var studentName = '';
    for (final table in ownTables) {
      if (table.studentName.trim().isNotEmpty) {
        studentName = table.studentName.trim();
        break;
      }
    }
    if (studentName.isEmpty) studentName = fallbackName.trim();

    for (final table in ownTables) {
      final semesterKey = semesterKeyOf(table);
      if (semesterKeys != null && !semesterKeys.contains(semesterKey)) continue;

      final courses = _courseIdentifiersOf(table);
      if (courses.isNotEmpty) semesters[semesterKey] = courses;
    }

    return <String, dynamic>{
      'version': version,
      'people': <Map<String, dynamic>>[
        <String, dynamic>{'studentId': normalizedAccount, 'name': studentName, 'semesters': semesters},
      ],
    };
  }

  static String encodeUrl(Map<String, dynamic> payload) {
    final binary = _encodeBinary(payload);
    final compressed = gzip.encode(binary);
    final encoded = base64UrlEncode(compressed).replaceAll('=', '');
    return Uri(scheme: scheme, host: host, path: path, queryParameters: <String, String>{'data': encoded}).toString();
  }

  static Map<String, dynamic> decodeUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != scheme || uri.host != host || uri.path != path) {
      throw const FormatException('Unsupported course table share URL');
    }

    final encoded = uri.queryParameters['data'];
    if (encoded == null || encoded.isEmpty) {
      throw const FormatException('Missing course table share data');
    }

    final padded = encoded.padRight(encoded.length + ((4 - encoded.length % 4) % 4), '=');
    final decompressed = gzip.decode(base64Url.decode(padded));
    if (decompressed.isEmpty) throw const FormatException('Empty course table share data');

    // v1/v2 used gzip-compressed JSON. Keep decoding it so previously exported
    // QR codes and .qaqschedule files remain readable by the future importer.
    if (decompressed.first == 0x7b) {
      final decoded = jsonDecode(utf8.decode(decompressed));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid legacy course table share data');
      }
      return decoded;
    }

    return _decodeBinary(Uint8List.fromList(decompressed));
  }

  static String semesterKeyOf(CourseTableJson table) =>
      '${table.courseSemester.year.trim()}-${table.courseSemester.semester.trim()}';

  static Uint8List _encodeBinary(Map<String, dynamic> payload) {
    final payloadVersion = payload['version'];
    if (payloadVersion != version) {
      throw FormatException('Unsupported course table share version: $payloadVersion');
    }

    final writer = _BinaryWriter()..writeByte(version);
    final people = _asList(payload['people'], 'people');
    writer.writeVarUint(people.length);

    for (final personValue in people) {
      final person = _asMap(personValue, 'person');
      writer
        ..writeString(_asString(person['studentId'], 'studentId'))
        ..writeString(_asString(person['name'], 'name'));

      final semesters = _asMap(person['semesters'], 'semesters');
      final semesterEntries = semesters.entries.toList()..sort((a, b) => _compareSemesterKeys(a.key, b.key));
      writer.writeVarUint(semesterEntries.length);

      for (final semesterEntry in semesterEntries) {
        final semester = _parseSemesterKey(semesterEntry.key);
        writer
          ..writeVarUint(semester.$1)
          ..writeVarUint(semester.$2);

        final courses = _asList(semesterEntry.value, 'courses');
        writer.writeVarUint(courses.length);
        for (final courseValue in courses) {
          final course = _asMap(courseValue, 'course');
          writer
            ..writeIdentifier(_asString(course['snum'], 'snum'))
            ..writeIdentifier(_asString(course['currCode'], 'currCode'));

          final syllabusCodes = _asList(course['syllabusCodes'], 'syllabusCodes');
          writer.writeVarUint(syllabusCodes.length);
          for (final code in syllabusCodes) {
            writer.writeIdentifier(_asString(code, 'syllabusCode'));
          }
        }
      }
    }

    return writer.takeBytes();
  }

  static Map<String, dynamic> _decodeBinary(Uint8List bytes) {
    final reader = _BinaryReader(bytes);
    final binaryVersion = reader.readByte();
    if (binaryVersion != version) {
      throw FormatException('Unsupported course table share version: $binaryVersion');
    }

    final people = <Map<String, dynamic>>[];
    final peopleCount = reader.readVarUint();
    for (var personIndex = 0; personIndex < peopleCount; personIndex++) {
      final studentId = reader.readString();
      final name = reader.readString();
      final semesters = <String, dynamic>{};

      final semesterCount = reader.readVarUint();
      for (var semesterIndex = 0; semesterIndex < semesterCount; semesterIndex++) {
        final year = reader.readVarUint();
        final semester = reader.readVarUint();
        final courses = <Map<String, dynamic>>[];

        final courseCount = reader.readVarUint();
        for (var courseIndex = 0; courseIndex < courseCount; courseIndex++) {
          final snum = reader.readIdentifier();
          final currCode = reader.readIdentifier();
          final syllabusCodes = <String>[];

          final syllabusCodeCount = reader.readVarUint();
          for (var syllabusIndex = 0; syllabusIndex < syllabusCodeCount; syllabusIndex++) {
            syllabusCodes.add(reader.readIdentifier());
          }

          courses.add(<String, dynamic>{'snum': snum, 'currCode': currCode, 'syllabusCodes': syllabusCodes});
        }

        semesters['$year-$semester'] = courses;
      }

      people.add(<String, dynamic>{'studentId': studentId, 'name': name, 'semesters': semesters});
    }

    reader.expectEnd();
    return <String, dynamic>{'version': binaryVersion, 'people': people};
  }

  static List<Map<String, dynamic>> _courseIdentifiersOf(CourseTableJson table) {
    final courses = <String, Map<String, dynamic>>{};
    final syllabusCodes = <String, Set<String>>{};

    for (final dayMap in table.courseInfoMap.values) {
      for (final courseInfo in dayMap.values) {
        final course = courseInfo.main.course;
        final snum = course.id.trim();
        if (snum.isEmpty) continue;

        final sharedCourse = courses.putIfAbsent(
          snum,
          () => <String, dynamic>{'snum': snum, 'currCode': '', 'syllabusCodes': <String>[]},
        );

        final currCode = _queryCode(course.href, expectedPage: 'Curr.jsp');
        if ((sharedCourse['currCode'] as String).isEmpty && currCode.isNotEmpty) {
          sharedCourse['currCode'] = currCode;
        }

        final codes = syllabusCodes.putIfAbsent(snum, () => <String>{});
        _addQueryCode(codes, course.scheduleHref, expectedPage: 'ShowSyllabus.jsp');
        _addQueryCode(codes, courseInfo.extra.course.href, expectedPage: 'ShowSyllabus.jsp');
        for (final teacher in courseInfo.main.teacher) {
          _addQueryCode(codes, teacher.href, expectedPage: 'Teach.jsp');
        }
      }
    }

    final result = courses.values.toList()..sort((a, b) => (a['snum'] as String).compareTo(b['snum'] as String));
    for (final course in result) {
      final codes = syllabusCodes[course['snum']]?.toList() ?? <String>[];
      codes.sort();
      course['syllabusCodes'] = codes;
    }
    return result;
  }

  static void _addQueryCode(Set<String> codes, String href, {required String expectedPage}) {
    final code = _queryCode(href, expectedPage: expectedPage);
    if (code.isNotEmpty) codes.add(code);
  }

  static String _queryCode(String href, {required String expectedPage}) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null || !uri.path.endsWith(expectedPage)) return '';
    return uri.queryParameters['code']?.trim() ?? '';
  }

  static int _compareCourseTables(CourseTableJson a, CourseTableJson b) {
    final year = _number(b.courseSemester.year).compareTo(_number(a.courseSemester.year));
    if (year != 0) return year;
    return _number(b.courseSemester.semester).compareTo(_number(a.courseSemester.semester));
  }

  static int _compareSemesterKeys(String a, String b) {
    final parsedA = _parseSemesterKey(a);
    final parsedB = _parseSemesterKey(b);
    final year = parsedB.$1.compareTo(parsedA.$1);
    if (year != 0) return year;
    return parsedB.$2.compareTo(parsedA.$2);
  }

  static (int, int) _parseSemesterKey(String value) {
    final parts = value.split('-');
    if (parts.length != 2) throw FormatException('Invalid semester key: $value');
    final year = int.tryParse(parts[0]);
    final semester = int.tryParse(parts[1]);
    if (year == null || year < 0 || semester == null || semester < 0) {
      throw FormatException('Invalid semester key: $value');
    }
    return (year, semester);
  }

  static Map<String, dynamic> _asMap(Object? value, String field) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    throw FormatException('Invalid $field');
  }

  static List<dynamic> _asList(Object? value, String field) {
    if (value is List<dynamic>) return value;
    throw FormatException('Invalid $field');
  }

  static String _asString(Object? value, String field) {
    if (value is String) return value;
    throw FormatException('Invalid $field');
  }

  static int _number(String value) => int.tryParse(value.trim()) ?? -1;
}

class _BinaryWriter {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  void writeByte(int value) => _buffer.addByte(value);

  void writeVarUint(int value) {
    if (value < 0) throw const FormatException('VarUint cannot be negative');
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      _buffer.addByte(byte);
    } while (remaining != 0);
  }

  void writeString(String value) {
    final bytes = utf8.encode(value);
    writeVarUint(bytes.length);
    _buffer.add(bytes);
  }

  void writeIdentifier(String value) {
    final normalized = value.trim();
    final numeric = int.tryParse(normalized);
    if (numeric != null && numeric >= 0 && numeric.toString() == normalized) {
      writeVarUint(numeric << 1);
      return;
    }

    final bytes = utf8.encode(normalized);
    writeVarUint((bytes.length << 1) | 1);
    _buffer.add(bytes);
  }

  Uint8List takeBytes() => _buffer.takeBytes();
}

class _BinaryReader {
  _BinaryReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int readByte() {
    if (_offset >= _bytes.length) throw const FormatException('Unexpected end of course table share data');
    return _bytes[_offset++];
  }

  int readVarUint() {
    var value = 0;
    var shift = 0;
    for (var index = 0; index < 10; index++) {
      final byte = readByte();
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return value;
      shift += 7;
    }
    throw const FormatException('Invalid VarUint');
  }

  String readString() => utf8.decode(_readBytes(readVarUint()));

  String readIdentifier() {
    final header = readVarUint();
    if ((header & 1) == 0) return (header >> 1).toString();
    return utf8.decode(_readBytes(header >> 1));
  }

  Uint8List _readBytes(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('Unexpected end of course table share data');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  void expectEnd() {
    if (_offset != _bytes.length) throw const FormatException('Trailing course table share data');
  }
}
