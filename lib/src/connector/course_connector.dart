import 'package:dio/dio.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/core/connector_parameter.dart';
import 'package:flutter_app/src/connector/ntut_connector.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course/course_score_json.dart';
import 'package:flutter_app/src/model/course/course_syllabus_json.dart';
import 'package:flutter_app/src/model/coursetable/course_table_json.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

enum CourseConnectorStatus { loginSuccess, loginFail, unknownError }

class CourseMainInfo {
  List<CourseMainInfoJson> json = <CourseMainInfoJson>[];
  String studentName = '';
}

class CourseConnector {
  static const _ssoLoginUrl = "${NTUTConnector.host}ssoIndex.do";
  static const String _courseCNHost = "https://aps.ntut.edu.tw/course/tw/";
  static const String _courseENHost = "https://aps.ntut.edu.tw/course/en/";
  static const String _postCourseCNUrl = "${_courseCNHost}Select.jsp";
  static const String _getSyllabusCNUrl = "${_courseCNHost}ShowSyllabus.jsp";
  static const String _postTeacherCourseCNUrl = "${_courseCNHost}Teach.jsp";
  static const String _postCourseENUrl = "${_courseENHost}Select.jsp";
  static const String _creditUrl = "${_courseCNHost}Cprog.jsp";
  static const String _getCourseDepartmentUrl = "${_courseCNHost}Subj.jsp";

  static Future<CourseConnectorStatus> login() async {
    try {
      Map<String, String> data = {
        "apUrl": "https://aps.ntut.edu.tw/course/tw/courseSID.jsp",
        "apOu": "aa_0010-oauth",
        "sso": "true",
        "datetime1": DateTime.now().millisecondsSinceEpoch.toString(),
      };
      var parameter = ConnectorParameter(_ssoLoginUrl);
      parameter.data = data;
      final result = await Connector.getDataByGet(parameter);

      var tagNode = parse(result);
      final nodes = tagNode.getElementsByTagName("input");
      data = {};
      for (Element node in nodes) {
        final name = node.attributes['name'];
        final value = node.attributes['value'];
        if (name != null && value != null) {
          data[name] = value;
        }
      }
      final action = tagNode.getElementsByTagName("form")[0].attributes["action"];
      if (action == null) throw StateError("SSO form action is missing");
      String jumpUrl = "${NTUTConnector.host}$action";
      parameter = ConnectorParameter(jumpUrl);
      parameter.data = data;
      final response = await Connector.getDataByPostResponse(parameter);

      tagNode = parse(response.toString());
      final redirectHref = tagNode.getElementsByTagName("a").first.attributes["href"];
      if (redirectHref == null) throw StateError("Course SSO redirect is missing");
      jumpUrl = redirectHref;
      parameter = ConnectorParameter(jumpUrl);

      await Connector.getDataByPostResponse(parameter);
      return CourseConnectorStatus.loginSuccess;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return CourseConnectorStatus.loginFail;
    }
  }

  // It should use code with key (59 -> CSIE, 32 -> Electric), and department name with value.
  static Future<Map<String, String>?> getDepartmentMap(String year, String semester) async {
    try {
      ConnectorParameter parameter = ConnectorParameter(_getCourseDepartmentUrl);
      parameter.data = {"format": "-2", "year": year, "sem": semester};
      String result = await Connector.getDataByGet(parameter);

      Document tagNode = parse(result);
      List<Element> departmentNodes = tagNode.getElementsByTagName("a");

      Map<String, String> departmentMap = {};
      for (Element element in departmentNodes) {
        final href = element.attributes["href"];
        if (href == null || href.isEmpty) {
          continue;
        }
        String codeParameter = href.split("&").firstWhere((parameter) => parameter.contains("code"), orElse: () => "");
        if (codeParameter == "") {
          continue;
        }
        String code = codeParameter.split("=")[1];
        String departmentName = element.text;
        departmentMap.putIfAbsent(code, () => departmentName);
      }

      return departmentMap;
    } catch (e, stack) {
      Log.eWithStack(e, stack);
      return null;
    }
  }

  static Future<Map<String, String>?> getTwoYearUndergraduateDepartmentMap(String year) async {
    try {
      ConnectorParameter parameter = ConnectorParameter(_creditUrl);
      parameter.data = {"format": "-3", "year": year, "matric": "6"};
      String result = await Connector.getDataByGet(parameter);

      Document tagNode = parse(result);
      List<Element> departmentNodes = tagNode.getElementsByTagName("a");

      Map<String, String> departmentMap = {};
      for (Element element in departmentNodes) {
        final href = element.attributes["href"];
        if (href == null || href.isEmpty) {
          continue;
        }
        String divisionParameter = href
            .split("&")
            .firstWhere((parameter) => parameter.contains("division"), orElse: () => "");
        if (divisionParameter == "") {
          continue;
        }
        final String code = divisionParameter.split("=")[1];
        final RegExp regExp = RegExp(".+【(.+)】");
        final RegExpMatch? matches = regExp.firstMatch(element.text);
        if (matches == null || matches.groupCount == 0) {
          continue;
        }
        final departmentName = matches.group(1);
        if (departmentName == null || departmentName.isEmpty) {
          continue;
        }
        departmentMap.putIfAbsent(code, () => departmentName);
      }

      return departmentMap;
    } catch (e, stack) {
      Log.eWithStack(e, stack);
      return null;
    }
  }

  static Future<Map<Day, Map<SectionNumber, Set<String>>>?> getClassroomUsage(String url) async {
    try {
      final classroomUsageUrl = url.replaceFirst('/course/en/', '/course/tw/');
      final parameter = ConnectorParameter(classroomUsageUrl);
      final result = await Connector.getDataByGet(parameter);
      final document = parse(result);
      final tables = document.getElementsByTagName('table');
      if (tables.length < 2) return null;

      final usage = <Day, Map<SectionNumber, Set<String>>>{};
      final dayOrder = <Day>[
        Day.Sunday,
        Day.Monday,
        Day.Tuesday,
        Day.Wednesday,
        Day.Thursday,
        Day.Friday,
        Day.Saturday,
      ];

      final rows = tables[1].getElementsByTagName('tr');
      var parsedSectionRows = 0;
      for (final row in rows.skip(1)) {
        final cells = row.children.where((element) => element.localName == 'td').toList();
        if (cells.length < 8) continue;

        final section = _sectionNumberFromClassroomLabel(cells[0].text);
        if (section == null) continue;
        parsedSectionRows++;

        for (int dayIndex = 0; dayIndex < dayOrder.length; dayIndex++) {
          final courseIdentifiers = <String>{};
          final cell = cells[dayIndex + 1];

          // Croom.jsp exposes both identifiers for the same class:
          //   (361463) ... Curr.jsp?...&code=2B03024
          // The Select/ShowSyllabus flow normally uses the six-digit snum,
          // while Curr.jsp uses the alphanumeric course code. Cache both so
          // either representation from the course table can match.
          final snumMatch = RegExp(r'\((\d{6})\)').firstMatch(strQ2B(cell.text));
          final snum = snumMatch?.group(1);
          if (snum != null && snum.isNotEmpty) {
            courseIdentifiers.add(_normalizeCourseIdentifier(snum));
          }

          for (final anchor in cell.getElementsByTagName('a')) {
            final href = anchor.attributes['href'];
            if (href == null || !href.contains('Curr.jsp')) continue;

            final uri = Uri.tryParse(href);
            final courseCode = uri?.queryParameters['code'];
            if (courseCode != null && courseCode.trim().isNotEmpty) {
              courseIdentifiers.add(_normalizeCourseIdentifier(courseCode));
            }
          }

          if (courseIdentifiers.isNotEmpty) {
            usage.putIfAbsent(dayOrder[dayIndex], () => <SectionNumber, Set<String>>{})[section] = courseIdentifiers;
          }
        }
      }

      // A classroom page always has section rows even when no class uses a
      // particular room. Zero parsed rows means the response was not the
      // expected Croom.jsp shape (login/error/malformed HTML), so do not mark
      // an empty result as a fresh seven-day cache entry.
      if (parsedSectionRows == 0) return null;
      return usage;
    } catch (e, stack) {
      Log.eWithStack('getClassroomUsage($url): $e', stack);
      return null;
    }
  }

  static String _normalizeCourseIdentifier(String value) => strQ2B(value).replaceAll(RegExp(r'\s'), '').toUpperCase();

  static SectionNumber? _sectionNumberFromClassroomLabel(String value) {
    final match = RegExp(r'第\s*([1-9NABCD])\s*節', caseSensitive: false).firstMatch(strQ2B(value));
    switch (match?.group(1)?.toUpperCase()) {
      case '1':
        return SectionNumber.T_1;
      case '2':
        return SectionNumber.T_2;
      case '3':
        return SectionNumber.T_3;
      case '4':
        return SectionNumber.T_4;
      case 'N':
        return SectionNumber.T_N;
      case '5':
        return SectionNumber.T_5;
      case '6':
        return SectionNumber.T_6;
      case '7':
        return SectionNumber.T_7;
      case '8':
        return SectionNumber.T_8;
      case '9':
        return SectionNumber.T_9;
      case 'A':
        return SectionNumber.T_A;
      case 'B':
        return SectionNumber.T_B;
      case 'C':
        return SectionNumber.T_C;
      case 'D':
        return SectionNumber.T_D;
      default:
        return null;
    }
  }

  static Future<CourseExtraInfoJson?> getCourseExtraInfo(String courseId) async {
    try {
      Map<String, String> data = {"code": courseId, "format": "-1"};
      var parameter = ConnectorParameter(_postCourseCNUrl);
      parameter.data = data;
      var result = await Connector.getDataByPost(parameter);
      var tagNode = parse(result);
      final courseNodes = tagNode.getElementsByTagName("table");

      CourseExtraInfoJson courseExtraInfo = CourseExtraInfoJson();

      //取得學期資料
      var nodes = courseNodes[0].getElementsByTagName("td");
      SemesterJson semester = SemesterJson();

      // Previously, the title string of the first course table was stored separately in its `<td>` element,
      // but it currently stores all the information in a row,
      // e.g. "學號：110310144　　姓名：xxx　　班級：電機三甲　　　 112 學年度 第 1 學期　上課時間表"
      // so the RegExp is used to filter out only the number parts
      final titleString = nodes[0].text;
      final RegExp studentSemesterDetailFilter = RegExp(r'\b[\dA-Z]+\b');
      final Iterable<RegExpMatch> studentSemesterDetailMatches = studentSemesterDetailFilter.allMatches(titleString);
      // "studentSemesterDetails" should consist of three numerical values
      // ex: [110310144, 112, 1]
      final List<String> studentSemesterDetails = studentSemesterDetailMatches
          .map((match) => match.group(0))
          .whereType<String>()
          .toList();
      if (studentSemesterDetails.isEmpty) {
        throw RangeError("[TAT] course_connector.dart: studentSemesterDetails list is empty");
      }
      if (studentSemesterDetails.length < 3) {
        throw RangeError("[TAT] course_connector.dart: studentSemesterDetails list has range less than 3");
      }
      semester.year = studentSemesterDetails[1];
      semester.semester = studentSemesterDetails[2];

      courseExtraInfo.courseSemester = semester;

      CourseExtraJson courseExtra = CourseExtraJson();

      nodes = courseNodes[1].getElementsByTagName("tr");
      final List<String> courseIds = nodes.skip(2).map((node) => node.getElementsByTagName("td")[0].text).toList();
      final courseIdPosition = courseIds.indexWhere((element) => element.contains(courseId));
      if (courseIdPosition == -1) {
        throw StateError('[TAT] course_connector.dart: CourseId not found: $courseId');
      }
      final node = nodes[courseIdPosition + 2];
      final classExtraInfoNodes = node.getElementsByTagName("td");
      courseExtra.id = strQ2B(classExtraInfoNodes[0].text).replaceAll(RegExp(r"\s"), "");
      courseExtra.name = classExtraInfoNodes[1].getElementsByTagName("a")[0].text;
      courseExtra.openClass = classExtraInfoNodes[7].getElementsByTagName("a")[0].text;

      // if the courseExtraInfo.herf (課程大綱連結) is empty,
      // the category of the course will be set to ▲ (校訂專業必修) as default
      if (classExtraInfoNodes[18].text.trim() != "" &&
          classExtraInfoNodes[18].getElementsByTagName("a")[0].attributes.containsKey("href")) {
        courseExtra.href =
            _courseCNHost + (classExtraInfoNodes[18].getElementsByTagName("a")[0].attributes["href"] ?? "");
        parameter = ConnectorParameter(courseExtra.href);
        result = await Connector.getDataByPost(parameter);
        tagNode = parse(result);
        nodes = tagNode.getElementsByTagName("tr");
        final syllabusCells = nodes[1].getElementsByTagName("td");
        courseExtra.category = syllabusCells[6].text.trim();
        // ShowSyllabus.jsp columns are:
        // ... category[6], teacher[7], class[8], enrolled[9], withdrawn[10].
        // These values are authoritative; never infer enrollment from the
        // iStudy classmate-list length because the two systems can differ.
        if (syllabusCells.length > 10) {
          courseExtra.selectNumber = strQ2B(syllabusCells[9].text).trim();
          courseExtra.withdrawNumber = strQ2B(syllabusCells[10].text).trim();
        }
      } else {
        courseExtra.category = constCourseType[4];
      }

      // Some courses do not expose the syllabus link in Select.jsp even
      // though ShowSyllabus.jsp is still addressable by course id. Try that
      // endpoint once so enrollment/withdrawal counts can still come from the
      // authoritative syllabus page.
      if (!_isNumericCourseCount(courseExtra.selectNumber) || !_isNumericCourseCount(courseExtra.withdrawNumber)) {
        final syllabus = await getCourseCategory(courseId);
        if (syllabus.courseId.isNotEmpty) {
          if (syllabus.category.isNotEmpty) courseExtra.category = syllabus.category;
          if (syllabus.className.isNotEmpty) courseExtra.openClass = syllabus.className;
          courseExtra.selectNumber = syllabus.applyStudentCount.toString();
          courseExtra.withdrawNumber = syllabus.withdrawStudentCount.toString();
        }
      }

      courseExtraInfo.course = courseExtra;
      return courseExtraInfo;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static bool _isNumericCourseCount(String value) => int.tryParse(value.trim()) != null;

  static Future<CourseSyllabusJson> getCourseCategory(String courseId) async {
    try {
      Map<String, String> data = {"snum": courseId};
      ConnectorParameter parameter = ConnectorParameter(_getSyllabusCNUrl);
      parameter.data = data;
      String result = await Connector.getDataByGet(parameter);
      Document tagNode = parse(result);

      var tables = tagNode.getElementsByTagName("table");
      var trs = tables[0].getElementsByTagName("tr");
      var syllabusRow = trs[1].getElementsByTagName("td");

      var model = CourseSyllabusJson(
        yearSemester: syllabusRow[0].text,
        courseId: syllabusRow[1].text,
        courseName: syllabusRow[2].text,
        phase: syllabusRow[3].text,
        credit: syllabusRow[4].text,
        hour: syllabusRow[5].text,
        category: syllabusRow[6].text,
        teachers: syllabusRow[7].text,
        className: syllabusRow[8].text,
        applyStudentCount: syllabusRow[9].text,
        withdrawStudentCount: syllabusRow[10].text,
        note: syllabusRow[11].text,
      );

      return model;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return CourseSyllabusJson();
    }
  }

  static Future<List<SemesterJson>?> getCourseSemester(String studentId) async {
    try {
      ConnectorParameter parameter;
      Document tagNode;
      Element node;
      List<Element> nodes;

      Map<String, String> data = {"code": studentId, "format": "-3"};
      parameter = ConnectorParameter(_postCourseCNUrl);
      parameter.data = data;
      Response response = await Connector.getDataByPostResponse(parameter);
      tagNode = parse(response.toString());
      node = tagNode.getElementsByTagName("table")[0];
      nodes = node.getElementsByTagName("tr");
      List<SemesterJson> semesterJsonList = [];
      for (int i = 1; i < nodes.length; i++) {
        node = nodes[i];
        String year, semester;
        year = node.getElementsByTagName("a")[0].text.split(" ")[0];
        semester = node.getElementsByTagName("a")[0].text.split(" ")[2];
        semesterJsonList.add(SemesterJson(year: year, semester: semester));
      }
      return semesterJsonList;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static String strQ2B(String input) {
    List<int> newString = [];
    for (int c in input.codeUnits) {
      if (c == 12288) {
        c = 32;
        continue;
      }
      if (c > 65280 && c < 65375) {
        c = (c - 65248);
      }
      newString.add(c);
    }
    return String.fromCharCodes(newString);
  }

  static Future<CourseMainInfo?> getENCourseMainInfoList(String studentId, SemesterJson semester) async {
    var info = CourseMainInfo();
    try {
      ConnectorParameter parameter;
      Document tagNode;
      List<Element> courseNodes, nodesOne, nodes;
      List<Day> dayEnum = [Day.Sunday, Day.Monday, Day.Tuesday, Day.Wednesday, Day.Thursday, Day.Friday, Day.Saturday];
      Map<String, String> data = {"code": studentId, "format": "-2", "year": semester.year, "sem": semester.semester};
      parameter = ConnectorParameter(_postCourseENUrl);
      parameter.data = data;
      parameter.charsetName = 'utf-8';
      Response response = await Connector.getDataByPostResponse(parameter);
      tagNode = parse(response.toString());
      nodes = tagNode.getElementsByTagName("table");
      courseNodes = nodes[1].getElementsByTagName("tr");
      String studentName;
      try {
        studentName = strQ2B(nodes[0].getElementsByTagName("td")[4].text).replaceAll(RegExp(r"[\n| ]"), "");
      } catch (e, stack) {
        Log.eWithStack(e.toString(), stack);
        studentName = "";
      }
      info.studentName = studentName;

      List<CourseMainInfoJson> courseMainInfoList = [];
      for (int i = 1; i < courseNodes.length - 1; i++) {
        CourseMainInfoJson courseMainInfo = CourseMainInfoJson();
        CourseMainJson courseMain = CourseMainJson();
        nodesOne = courseNodes[i].getElementsByTagName("td");
        if (nodesOne[16].text.contains("Withdraw")) {
          continue;
        }
        //取得課號
        courseMain.id = strQ2B(nodesOne[0].text).replaceAll(RegExp(r"[\n| ]"), "");
        //取的課程名稱/課程連結
        nodes = nodesOne[1].getElementsByTagName("a"); //確定是否有連結
        if (nodes.isNotEmpty) {
          courseMain.name = nodes[0].text;
          final href = nodes[0].attributes["href"] ?? "";
          courseMain.href = href.startsWith("http") ? href : _courseENHost + href;
        } else {
          courseMain.name = nodesOne[1].text;
        }
        courseMain.credits = nodesOne[2].text.replaceAll("\n", ""); //學分
        courseMain.hours = nodesOne[3].text.replaceAll("\n", ""); //時數

        //時間
        for (int j = 0; j < 7; j++) {
          Day day = dayEnum[j]; //要做變換網站是從星期日開始
          String time = nodesOne[j + 6].text;
          time = strQ2B(time);
          courseMain.time[day] = time;
        }

        courseMainInfo.course = courseMain;

        int length;
        //取得老師名稱
        length = nodesOne[4].innerHtml.split("<br>").length;
        for (String name in nodesOne[4].innerHtml.split("<br>")) {
          TeacherJson teacher = TeacherJson();
          teacher.name = name.replaceAll("\n", "");
          courseMainInfo.teacher.add(teacher);
        }

        //取得教室名稱。英文課表若有教室連結也保留下來，背景教室解析
        // 會統一改用中文版 Croom.jsp 解析星期/節次。
        final classroomAnchors = nodesOne[13].getElementsByTagName("a");
        if (classroomAnchors.isNotEmpty) {
          for (final node in classroomAnchors) {
            final classroom = ClassroomJson();
            classroom.name = node.text.replaceAll("\n", "");
            final href = node.attributes["href"] ?? "";
            classroom.href = href.startsWith("http") ? href : _courseENHost + href;
            courseMainInfo.classroom.add(classroom);
          }
        } else {
          length = nodesOne[13].innerHtml.split("<br>").length;
          for (String name in nodesOne[13].innerHtml.split("<br>").getRange(0, length - 1)) {
            final classroom = ClassroomJson();
            classroom.name = name.replaceAll("\n", "");
            courseMainInfo.classroom.add(classroom);
          }
        }

        //取得開設教室名稱
        for (Element node in nodesOne[5].getElementsByTagName("a")) {
          ClassJson classInfo = ClassJson();
          classInfo.name = node.text;
          classInfo.href = _courseCNHost + (node.attributes["href"] ?? "");
          courseMainInfo.openClass.add(classInfo);
        }
        courseMainInfoList.add(courseMainInfo);
      }
      info.json = courseMainInfoList;
      return info;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<CourseMainInfo?> getTWCourseMainInfoList(String studentId, SemesterJson semester) async {
    var info = CourseMainInfo();
    try {
      ConnectorParameter parameter;
      Document tagNode;
      Element node;
      List<Element> courseNodes, nodesOne, nodes;
      List<Day> dayEnum = [Day.Sunday, Day.Monday, Day.Tuesday, Day.Wednesday, Day.Thursday, Day.Friday, Day.Saturday];
      Map<String, String> data = {"code": studentId, "format": "-2", "year": semester.year, "sem": semester.semester};
      parameter = ConnectorParameter(_postCourseCNUrl);
      parameter.data = data;
      Response response = await Connector.getDataByPostResponse(parameter);
      tagNode = parse(response.toString());
      node = tagNode.getElementsByTagName("table")[1];
      courseNodes = node.getElementsByTagName("tr");
      String studentName;
      try {
        studentName = RegExp(r"姓名：([\u4E00-\u9FA5]+)").firstMatch(courseNodes[0].text)?.group(1) ?? "";
      } catch (e) {
        studentName = "";
      }
      info.studentName = studentName;
      List<CourseMainInfoJson> courseMainInfoList = [];
      for (int i = 2; i < courseNodes.length - 1; i++) {
        CourseMainInfoJson courseMainInfo = CourseMainInfoJson();
        CourseMainJson courseMain = CourseMainJson();

        nodesOne = courseNodes[i].getElementsByTagName("td");
        if (nodesOne[16].text.contains("撤選")) {
          continue;
        }
        //取得課號
        courseMain.id = strQ2B(nodesOne[0].text).replaceAll(RegExp(r"\s"), "");

        //取的課程名稱/課程連結
        nodes = nodesOne[1].getElementsByTagName("a"); //確定是否有連結
        if (nodes.isNotEmpty) {
          courseMain.name = nodes[0].text;
          final href = nodes[0].attributes["href"] ?? "";
          courseMain.href = href.startsWith("http") ? href : _courseCNHost + href;
        } else {
          courseMain.name = nodesOne[1].text;
        }
        courseMain.stage = nodesOne[2].text.replaceAll("\n", ""); //階段
        courseMain.credits = nodesOne[3].text.replaceAll("\n", ""); //學分
        courseMain.hours = nodesOne[4].text.replaceAll("\n", ""); //時數
        courseMain.note = nodesOne[19].text.replaceAll("\n", ""); //備註
        if (nodesOne[18].getElementsByTagName("a").isNotEmpty) {
          courseMain.scheduleHref =
              _courseCNHost + (nodesOne[18].getElementsByTagName("a")[0].attributes["href"] ?? ""); //教學進度大綱
        }

        //時間
        for (int j = 0; j < 7; j++) {
          Day day = dayEnum[j]; //要做變換網站是從星期日開始
          String time = nodesOne[j + 8].text;
          time = strQ2B(time);
          courseMain.time[day] = time;
        }

        courseMainInfo.course = courseMain;

        //取得老師名稱
        for (Element node in nodesOne[6].getElementsByTagName("a")) {
          TeacherJson teacher = TeacherJson();
          teacher.name = node.text;
          teacher.href = _courseCNHost + (node.attributes["href"] ?? "");
          courseMainInfo.teacher.add(teacher);
        }

        //取得教室名稱
        for (Element node in nodesOne[15].getElementsByTagName("a")) {
          ClassroomJson classroom = ClassroomJson();
          classroom.name = node.text;
          classroom.href = _courseCNHost + (node.attributes["href"] ?? "");
          courseMainInfo.classroom.add(classroom);
        }

        //取得開設教室名稱
        for (Element node in nodesOne[7].getElementsByTagName("a")) {
          ClassJson classInfo = ClassJson();
          classInfo.name = node.text;
          classInfo.href = _courseCNHost + (node.attributes["href"] ?? "");
          courseMainInfo.openClass.add(classInfo);
        }

        courseMainInfoList.add(courseMainInfo);
      }
      info.json = courseMainInfoList;
      return info;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<CourseMainInfo?> getTWTeacherCourseMainInfoList(String studentId, SemesterJson semester) async {
    var info = CourseMainInfo();
    try {
      ConnectorParameter parameter;
      Document tagNode;
      Element node;
      List<Element> courseNodes, nodesOne, nodes;
      List<Day> dayEnum = [Day.Sunday, Day.Monday, Day.Tuesday, Day.Wednesday, Day.Thursday, Day.Friday, Day.Saturday];
      Map<String, String> data = {"code": studentId, "format": "-3", "year": semester.year, "sem": semester.semester};
      parameter = ConnectorParameter(_postTeacherCourseCNUrl);
      parameter.data = data;
      parameter.charsetName = 'big5';
      Response response = await Connector.getDataByPostResponse(parameter);
      tagNode = parse(response.toString());
      node = tagNode.getElementsByTagName("table")[0];
      courseNodes = node.getElementsByTagName("tr");
      String studentName;
      try {
        studentName = courseNodes[0].text.replaceAll("　　", " ").split(" ")[2];
      } catch (e) {
        studentName = "";
      }
      info.studentName = studentName;
      List<CourseMainInfoJson> courseMainInfoList = [];
      for (int i = 2; i < courseNodes.length - 1; i++) {
        CourseMainInfoJson courseMainInfo = CourseMainInfoJson();
        CourseMainJson courseMain = CourseMainJson();

        nodesOne = courseNodes[i].getElementsByTagName("td");
        if (nodesOne[16].text.contains("撤選")) {
          continue;
        }
        //取得課號
        nodes = nodesOne[0].getElementsByTagName("a"); //確定是否有課號
        if (nodes.isNotEmpty) {
          courseMain.id = nodes[0].text;
          courseMain.href = _courseCNHost + (nodes[0].attributes["href"] ?? "");
        }
        //取的課程名稱/課程連結
        nodes = nodesOne[1].getElementsByTagName("a"); //確定是否有連結
        if (nodes.isNotEmpty) {
          courseMain.name = nodes[0].text;
        } else {
          courseMain.name = nodesOne[1].text;
        }
        courseMain.stage = nodesOne[2].text.replaceAll("\n", ""); //階段
        courseMain.credits = nodesOne[3].text.replaceAll("\n", ""); //學分
        courseMain.hours = nodesOne[4].text.replaceAll("\n", ""); //時數
        courseMain.note = nodesOne[20].text.replaceAll("\n", ""); //備註
        if (nodesOne[19].getElementsByTagName("a").isNotEmpty) {
          courseMain.scheduleHref =
              _courseCNHost + (nodesOne[19].getElementsByTagName("a")[0].attributes["href"] ?? ""); //教學進度大綱
        }

        //時間
        for (int j = 0; j < 7; j++) {
          Day day = dayEnum[j]; //要做變換網站是從星期日開始
          String time = nodesOne[j + 8].text;
          time = strQ2B(time);
          courseMain.time[day] = time;
        }

        courseMainInfo.course = courseMain;

        //取得老師名稱
        TeacherJson teacher = TeacherJson();
        teacher.name = "";
        teacher.href = "";
        courseMainInfo.teacher.add(teacher);

        //取得教室名稱
        for (Element node in nodesOne[15].getElementsByTagName("a")) {
          ClassroomJson classroom = ClassroomJson();
          classroom.name = node.text;
          classroom.href = _courseCNHost + (node.attributes["href"] ?? "");
          courseMainInfo.classroom.add(classroom);
        }

        //取得開設教室名稱
        for (Element node in nodesOne[7].getElementsByTagName("a")) {
          ClassJson classInfo = ClassJson();
          classInfo.name = node.text;
          classInfo.href = _courseCNHost + (node.attributes["href"] ?? "");
          courseMainInfo.openClass.add(classInfo);
        }

        courseMainInfoList.add(courseMainInfo);
      }
      info.json = courseMainInfoList;
      return info;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<List<String>?> getYearList() async {
    ConnectorParameter parameter;
    String result;
    Document tagNode;
    Element node;
    List<Element> nodes;
    List<String> resultList = [];
    try {
      parameter = ConnectorParameter("https://aps.ntut.edu.tw/course/tw/Cprog.jsp");
      parameter.data = {"format": "-1"};
      result = await Connector.getDataByPost(parameter);
      tagNode = parse(result);
      nodes = tagNode.getElementsByTagName("a");
      for (int i = 0; i < nodes.length; i++) {
        node = nodes[i];
        resultList.add(node.text);
      }
      return resultList;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  /*
  Map Key
  name 名稱
  code 參數
  */
  static Future<List<Map>?> getDivisionList(String year) async {
    ConnectorParameter parameter;
    String result;
    Document tagNode;
    Element node;
    List<Element> nodes;
    List<Map> resultList = [];
    try {
      parameter = ConnectorParameter(_creditUrl);
      parameter.data = {"format": "-2", "year": year};
      result = await Connector.getDataByPost(parameter);
      tagNode = parse(result);
      nodes = tagNode.getElementsByTagName("a");
      for (int i = 0; i < nodes.length; i++) {
        node = nodes[i];
        Map<String, String> code = Uri.parse(node.attributes["href"] ?? "").queryParameters;
        resultList.add({"name": node.text, "code": code});
      }
      return resultList;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  /*
  Map Key
  name 名稱
  code 參數
  */
  static Future<List<Map>?> getDepartmentList(Map code) async {
    ConnectorParameter parameter;
    String result;
    Document tagNode;
    Element node;
    List<Element> nodes;
    List<Map> resultList = [];
    try {
      parameter = ConnectorParameter(_creditUrl);
      parameter.data = code;
      result = await Connector.getDataByPost(parameter);
      tagNode = parse(result);
      node = tagNode.getElementsByTagName("table").first;
      nodes = node.getElementsByTagName("a");
      for (int i = 0; i < nodes.length; i++) {
        node = nodes[i];
        Map<String, String> code = Uri.parse(node.attributes["href"] ?? "").queryParameters;
        String name = node.text.replaceAll(RegExp("[ |s]"), "");
        resultList.add({"name": name, "code": code});
      }
      return resultList;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  /*
  Map Key
  minGraduationCredits
  */
  static Future<GraduationInformationJson?> getCreditInfo(Map code, String select) async {
    ConnectorParameter parameter;
    String result;
    Document tagNode;
    Element anode, trNode, node, tdNode;
    List<Element> trNodes, tdNodes;
    GraduationInformationJson graduationInformation = GraduationInformationJson();
    try {
      Log.d("select is $select");
      parameter = ConnectorParameter(_creditUrl);
      parameter.data = code;
      result = await Connector.getDataByPost(parameter);
      tagNode = parse(result);
      node = tagNode.getElementsByTagName("table").first;
      trNodes = node.getElementsByTagName("tr");
      trNodes.removeAt(0);
      bool pass = false;
      for (int i = 0; i < trNodes.length; i++) {
        trNode = trNodes[i];
        anode = trNode.getElementsByTagName("a").first;
        String name = anode.text.replaceAll(RegExp("[ |s]"), "");
        if (name.contains(select)) {
          tdNodes = trNode.getElementsByTagName("td");
          Log.d(trNode.innerHtml);
          for (int j = 1; j < tdNodes.length; j++) {
            tdNode = tdNodes[j];
            /*
              "○", //	  必	部訂共同必修
              "△", //	必	校訂共同必修
              "☆", //	選	共同選修
              "●", //	  必	部訂專業必修
              "▲", //	  必	校訂專業必修
              "★" //	  選	專業選修
             */
            String creditString = tdNode.text.replaceAll(RegExp(r"[\s|\n]"), "");
            switch (j - 1) {
              case 0:
                graduationInformation.courseTypeMinCredit["○"] = int.parse(creditString);
                break;
              case 1:
                graduationInformation.courseTypeMinCredit["△"] = int.parse(creditString);
                break;
              case 2:
                graduationInformation.courseTypeMinCredit["☆"] = int.parse(creditString);
                break;
              case 3:
                graduationInformation.courseTypeMinCredit["●"] = int.parse(creditString);
                break;
              case 4:
                graduationInformation.courseTypeMinCredit["▲"] = int.parse(creditString);
                break;
              case 5:
                graduationInformation.courseTypeMinCredit["★"] = int.parse(creditString);
                break;
              case 6:
                graduationInformation.outerDepartmentMaxCredit = int.parse(creditString);
                break;
              case 7:
                graduationInformation.lowCredit = int.parse(creditString);
                break;
            }
          }
          pass = true;
          Log.d(graduationInformation.courseTypeMinCredit.toString());
          break;
        }
      }
      if (!pass) {
        Log.d("not find $select");
      }
      return graduationInformation;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }
}
