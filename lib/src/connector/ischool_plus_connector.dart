import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio_redirect_interceptor/dio_redirect_interceptor.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/network.dart';
import 'package:qaq_app/src/model/ischoolplus/course_file_json.dart';
import 'package:qaq_app/src/model/ischoolplus/ischool_plus_announcement_json.dart';
import 'package:qaq_app/src/util/html_utils.dart';

import '../model/course/course_student.dart';
import 'global_protect/global_protect_routing.dart';
import 'ntut_connector.dart';

enum ISchoolPlusConnectorStatus { loginSuccess, loginGetSSOIndexError, loginRedirectionError }

enum IPlusReturnStatus { success, fail, noPermission }

class ReturnWithStatus<T> {
  IPlusReturnStatus status = IPlusReturnStatus.fail;
  T? result;
}

class ISchoolPlusConnector {
  static const String _iSchoolPlusUrl = 'https://istudy.ntut.edu.tw/';

  static const String _getCourseName = "${_iSchoolPlusUrl}learn/mooc_sysbar.php";
  static const _getCourseStudentList = "${_iSchoolPlusUrl}learn/learn_ranking.php";
  static const _ssoLoginUrl = "${NTUTConnector.host}ssoIndex.do";

  /// Parse the portal SSO form, then let Dio follow the OAuth redirects through
  /// the GP routing adapter. Only application-level "connection lost" is retried.
  static Future<ISchoolPlusConnectorStatus> login(String account) async {
    try {
      final ssoIndexResponse = await getSSOIndexResponse();
      if (ssoIndexResponse.isEmpty) return ISchoolPlusConnectorStatus.loginGetSSOIndexError;

      final ssoIndexTagNode = html.parse(ssoIndexResponse);
      final ssoIndexNodes = ssoIndexTagNode.getElementsByTagName("input");
      final ssoIndexJumpUrl = ssoIndexTagNode.getElementsByTagName("form")[0].attributes["action"];
      if (ssoIndexJumpUrl == null || ssoIndexJumpUrl.isEmpty) {
        return ISchoolPlusConnectorStatus.loginGetSSOIndexError;
      }

      final Map<String, String> oauthData = {};
      for (final node in ssoIndexNodes) {
        final name = node.attributes['name'];
        final value = node.attributes['value'];
        if (name != null && value != null) {
          oauthData[name] = value;
        }
      }

      for (int retry = 0; retry < 3; retry++) {
        final response = await dio.post<String>(
          Uri.parse(_ssoLoginUrl).resolve(ssoIndexJumpUrl).toString(),
          data: oauthData,
        );
        // Dio follows the OAuth 302 using the same cookies and routes each hop.
        if (response.statusCode != HttpStatus.ok || !GlobalProtectRouting.isStudyHost(response.realUri.host)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }
        final login2Result = response.data ?? '';
        if (login2Result.contains("lost")) {
          log("[QAQ] ischool_plus_connector.dart: connection lost during redirection, retrying...");
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }
        return ISchoolPlusConnectorStatus.loginSuccess;
      }
      return ISchoolPlusConnectorStatus.loginRedirectionError;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      rethrow;
    }
  }

  static Future<String> getSSOIndexResponse() async {
    final data = {"apOu": "ischool_plus_oauth", "datetime1": DateTime.now().millisecondsSinceEpoch.toString()};
    for (int retry = 0; retry < 5; retry++) {
      final response = (await dio.get<String>(_ssoLoginUrl, queryParameters: data)).data!.trim();
      if (response.contains("ssoForm")) return response;
      log("[QAQ] ischool_plus_connector.dart: failed to get ssoForm, retrying...");
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return "";
  }

  static Future<ReturnWithStatus<List<CourseStudent>>> getCourseStudent(String courseId) => _withCourse(() async {
    try {
      if (!await _selectCourse(courseId)) {
        final returnResult = ReturnWithStatus<List<CourseStudent>>();
        returnResult.status = IPlusReturnStatus.noPermission;
        return returnResult;
      }

      String result = (await dio.get<String>(_getCourseStudentList)).data!.trim();

      html.Document tagNode = html.parse(result);
      html.Element table = tagNode.querySelectorAll('table')[1];
      List<html.Element> nodes = table.querySelectorAll('tr');

      List<CourseStudent> courseStudents = <CourseStudent>[];
      for (int i = 0; i < nodes.length; i++) {
        final cells = nodes[i].querySelectorAll('td');
        if (cells.length < 2) continue;
        html.Element node = cells[1];

        final infoNode = node.querySelector('div');
        if (infoNode == null) continue;
        final information = RegExp(r'^(\S+)\s+\((.*)\)$').firstMatch(infoNode.text.trim());
        if (information == null) continue;
        final studentId = information.group(1)!;
        final studentName = information.group(2)!;

        // 過濾掉校務人士，如有多身分考慮枚舉或過濾 Email
        if (studentId == 'istudyoaa') {
          continue;
        }

        CourseStudent courseStudent = CourseStudent(department: "", id: studentId, name: studentName);
        courseStudents.add(courseStudent);
      }
      courseStudents.sort((a, b) => a.id.compareTo(b.id));

      final returnResult = ReturnWithStatus<List<CourseStudent>>();
      returnResult.status = IPlusReturnStatus.success;
      returnResult.result = courseStudents;
      return returnResult;
    } catch (e, stack) {
      Log.eWithStack(e, stack);
      final returnResult = ReturnWithStatus<List<CourseStudent>>();
      returnResult.status = IPlusReturnStatus.fail;
      return returnResult;
    }
  });

  static Future<ReturnWithStatus<List<CourseFileJson>>> getCourseFile(String courseId) => _withCourse(() async {
    var value = ReturnWithStatus<List<CourseFileJson>>();
    try {
      List<CourseFileJson> courseFileList = [];
      if (!await _selectCourse(courseId)) {
        value.status = IPlusReturnStatus.noPermission;
        return value;
      }

      var result = (await dio.get<String>("${_iSchoolPlusUrl}learn/path/launch.php")).data!.trim();
      var exp = RegExp(r"cid=(?<cid>[\w|-]+,)");
      var matches = exp.firstMatch(result);
      final cid = matches?.group(1);
      if (cid == null || cid.isEmpty) {
        value.status = IPlusReturnStatus.fail;
        return value;
      }

      result = (await dio.get<String>(
        "${_iSchoolPlusUrl}learn/path/pathtree.php",
        queryParameters: {'cid': cid},
      )).data!.trim();
      var tagNode = html.parse(result);
      final fetchResourceForm = tagNode.getElementById("fetchResourceForm");
      if (fetchResourceForm == null) {
        value.status = IPlusReturnStatus.fail;
        return value;
      }
      final nodes = fetchResourceForm.getElementsByTagName("input");

      Map<String, String> downloadPost = {
        'is_player': '',
        'href': '',
        'prev_href': '',
        'prev_node_id': '',
        'prev_node_title': '',
        'is_download': '',
        'begin_time': '',
        'course_id': '',
        'read_key': '',
      };

      for (html.Element node in nodes) {
        //將資料團入上方Map
        final key = node.attributes['name'];
        if (key != null && downloadPost.containsKey(key)) {
          downloadPost[key] = node.attributes['value'] ?? '';
        }
      }
      //取得下載檔案XML
      result = (await dio.get<String>("${_iSchoolPlusUrl}learn/path/SCORM_loadCA.php")).data!.trim();
      tagNode = html.parse(result);
      final itemNodes = tagNode.getElementsByTagName("item");
      final resourceNodes = tagNode.getElementsByTagName("resource");
      for (int i = 0; i < itemNodes.length; i++) {
        final itemNode = itemNodes[i];
        if (!itemNode.attributes.containsKey("identifierref")) {
          //代表是目錄不是一個檔案
          continue;
        }
        final itemId = itemNode.attributes["identifierref"];
        html.Element? resourceNode;
        for (final candidate in resourceNodes) {
          if (candidate.attributes["identifier"] == itemId) {
            resourceNode = candidate;
            break;
          }
        }
        if (resourceNode == null) continue;
        final base = resourceNode.attributes["xml:base"] ?? '';
        final resourceHref = resourceNode.attributes["href"] ?? '';
        String href = '$base@$resourceHref';

        CourseFileJson courseFile = CourseFileJson();
        courseFile.name = itemNodes[i].text.split("\t")[0].replaceAll(RegExp(r"[\s|\n| ]"), "");
        FileType fileType = FileType();
        downloadPost['href'] = href;
        fileType.postData = Map.of(downloadPost); //紀錄  需要使用Map.of不一個改全部都改
        fileType.type = CourseFileType.unknown;
        courseFile.fileType = [fileType];
        courseFileList.add(courseFile);
      }
      value.status = IPlusReturnStatus.success;
      value.result = courseFileList;
      return value;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      value.status = IPlusReturnStatus.fail;
      return value;
    }
  });

  /// Resolve the resource URL without downloading the file body. This is the
  /// only campus request that intentionally exposes the original redirect:
  /// SCORM returns a preview Location whose path must become a download URL.
  static Future<List<String>?> getRealFileUrl(Map<String, String> postParameter) async {
    try {
      final response = await dio.post<String>(
        "${_iSchoolPlusUrl}learn/path/SCORM_fetchResource.php",
        data: postParameter,
        options: Options(
          headers: {'referer': "${_iSchoolPlusUrl}learn/path/pathtree.php?cid=${postParameter['course_id']}"},
          extra: {RedirectInterceptor.followRedirects: false},
        ),
      );
      if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final locations = response.headers[HttpHeaders.locationHeader];
        if (locations == null || locations.length != 1 || locations.single.trim().isEmpty) return null;
        final destination = response.realUri.resolve(locations.single);
        final url = destination.replace(path: destination.path.replaceAll('download_preview', 'download')).toString();
        return [url, url];
      }
      if (response.statusCode != HttpStatus.ok) return null;
      final body = response.data ?? '';
      // Quoted values are non-greedy so another assignment or quote on the
      // same line cannot become part of the resource URL.
      final quoted = RegExp(r'''(["'])(.*?)\1''');
      final values = quoted.allMatches(body).map((match) => match.group(2)!).toList();
      final navigation = RegExp(
        r'''(?:\blocation(?:\.href)?\s*=\s*|\b(?:window\.open|location\.(?:replace|assign))\s*\(\s*)(["'])(.*?)\1''',
      ).firstMatch(body)?.group(2);
      final target = values
          .where((value) => value.startsWith('http://') || value.startsWith('https://') || value.startsWith('/'))
          .firstOrNull;
      final destination = navigation ?? target;
      if (destination != null &&
          (destination.startsWith('http://') || destination.startsWith('https://') || destination.startsWith('/'))) {
        final url = response.realUri.resolve(destination).toString();
        return [url, url];
      }
      final previewPath =
          navigation ??
          values.where((value) => value.isNotEmpty && !value.contains('<') && !value.contains(' ')).firstOrNull;
      if (previewPath == null) return null;
      final previewUri = response.realUri.resolve(previewPath);
      final preview = await dio.get<String>(previewUri.toString());
      final match = RegExp(r'''\bDEFAULT_URL\s*=\s*(["'])(.*?)\1''').firstMatch(preview.data ?? '');
      final downloadPath = match?.group(2);
      if (downloadPath == null || downloadPath.isEmpty) return null;
      return [preview.realUri.resolve(downloadPath).toString(), preview.realUri.toString()];
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<ReturnWithStatus<List<ISchoolPlusAnnouncementJson>>> getCourseAnnouncement(String courseId) =>
      _withCourse(() async {
        String result;
        var value = ReturnWithStatus<List<ISchoolPlusAnnouncementJson>>();
        try {
          if (!await _selectCourse(courseId)) {
            value.status = IPlusReturnStatus.noPermission;
            return value;
          }

          html.Document tagNode;
          List<html.Element> nodes;
          html.Element node;
          Map<String, String> data = {"cid": "", "bid": "", "nid": ""};
          List<ISchoolPlusAnnouncementJson> announcementList = [];

          result = (await dio.post<String>("${_iSchoolPlusUrl}forum/m_node_list.php", data: data)).data!.trim();
          tagNode = html.parse(result);
          final bidNode = tagNode.getElementById("bid");
          final boardId = bidNode?.attributes["value"] ?? "";

          final formSearch = tagNode.getElementById("formSearch");
          if (formSearch == null) {
            value.status = IPlusReturnStatus.fail;
            return value;
          }
          node = formSearch;
          nodes = node.getElementsByTagName("input");
          final selectPage = tagNode.getElementById("selectPage")?.attributes['value'] ?? "1";
          final inputPerPage = tagNode.getElementById("inputPerPage")?.attributes['value'] ?? "10";
          data = {
            "token": "",
            "bid": boardId,
            "curtab": "",
            "action": "getNews",
            "tpc": "1",
            "selectPage": selectPage,
            "inputPerPage": inputPerPage,
          };
          for (html.Element node in nodes) {
            final name = node.attributes['name'];
            if (name != null && data.containsKey(name)) {
              data[name] = node.attributes['value'] ?? '';
            }
          }

          result = (await dio.post<String>(
            "${_iSchoolPlusUrl}mooc/controllers/forum_ajax.php",
            data: data,
          )).data!.trim();
          Map<String, dynamic> jsonData = {};
          final decoded = json.decode(result);
          if (decoded is! Map) {
            value.status = IPlusReturnStatus.fail;
            return value;
          }
          final Map<dynamic, dynamic> j = decoded;
          // WMPro uses code=-1 for an empty board as well as other failures.
          // Only its measured "no data" response is a successful empty list.
          if (j['code'] == -1 && j['total_rows']?.toString() == '0' && j['message'] == '沒有任何資料') {
            value.status = IPlusReturnStatus.success;
            value.result = [];
            return value;
          }
          if (j["code"] != 0) return value;
          final dataValue = j['data'];
          if (dataValue is Map) {
            jsonData = Map<String, dynamic>.from(dataValue);
          }
          int totalRows = int.tryParse(j['total_rows']?.toString() ?? '0') ?? 0;
          if (totalRows > 0) {
            for (final key in jsonData.keys) {
              final keyName = key.toString();
              final rawItem = jsonData[keyName];
              if (rawItem is! Map) continue;
              ISchoolPlusAnnouncementJson courseInfo = ISchoolPlusAnnouncementJson.fromJson(
                Map<String, dynamic>.from(rawItem),
              );
              courseInfo.subject = HtmlUtils.clean(courseInfo.subject); //處理HTM特殊字
              courseInfo.token = data['token'] ?? '';
              courseInfo.bid = keyName.split("|").first;
              courseInfo.nid = keyName.split("|").last;
              announcementList.add(courseInfo);
            }
          }
          value.status = IPlusReturnStatus.success;
          value.result = announcementList;
          return value;
        } catch (e, stack) {
          Log.eWithStack(e.toString(), stack);
          value.status = IPlusReturnStatus.fail;
          return value;
        }
      });

  static Future<Map?> getCourseAnnouncementDetail(ISchoolPlusAnnouncementJson value) async {
    String result;
    try {
      html.Document tagNode;
      List<html.Element> nodes;
      html.Element node;
      Map<String, String> data = {
        'token': value.token,
        'cid': value.cid,
        'bid': value.bid,
        'nid': value.nid,
        'mnode': '',
        'subject': '',
        'content': '',
        'awppathre': '',
        'nowpage': '1',
      };

      result = (await dio.post<String>("${_iSchoolPlusUrl}forum/m_node_chain.php", data: data)).data!.trim();
      tagNode = html.parse(result);
      node = tagNode.getElementsByClassName("main node-info").first;
      Map detail = {};

      String title = node.attributes["data-title"] ?? "";
      node = tagNode.getElementsByClassName("author-name").first;
      String sender = node.text;
      node = tagNode.getElementsByClassName("post-time").first;
      String postTime = node.text;
      node = tagNode.getElementsByClassName("bottom-tmp").first;
      node = node.getElementsByClassName("content").first;
      String body = node.innerHtml;
      node = tagNode.getElementsByClassName("bottom-tmp").first;
      nodes = node.getElementsByClassName("file");
      Map<String, String> fileMap = {}; // name , url
      if (nodes.isNotEmpty) {
        node = nodes.first;
        nodes = node.getElementsByTagName("a");
        for (html.Element node in nodes) {
          String href = node.attributes["href"] ?? "";
          if (href.isEmpty) continue;
          fileMap[node.text] = Uri.parse("${_iSchoolPlusUrl}forum/m_node_chain.php").resolve(href).toString();
        }
      }
      detail["title"] = title;
      detail["sender"] = sender;
      detail["postTime"] = postTime;
      detail["body"] = body;
      detail["file"] = fileMap;
      return detail;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<bool> courseSubscribe(String bid, bool subscribe) async {
    try {
      if (await getCourseSubscribe(bid) == subscribe) return true;
      await dio.post<String>("${_iSchoolPlusUrl}forum/subscribe.php", data: {"bid": bid});
      return await getCourseSubscribe(bid) == subscribe;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return false;
    }
  }

  static Future<List<String>?> getSubscribeNotice() async {
    html.Document tagNode;
    String result;
    List<String> courseNameList = [];
    try {
      result = (await dio.post<String>("${_iSchoolPlusUrl}learn/my_forum.php")).data!.trim();
      tagNode = html.parse(result);
      // Include only data rows: headers and demo courses do not necessarily
      // contain the semester_name_courseId naming convention.
      for (final row in tagNode.querySelectorAll('tr')) {
        final cells = row.getElementsByTagName('td');
        if (cells.length < 2 || int.tryParse(cells.first.text.trim()) == null) continue;
        final label = cells[1].text.trim();
        final parts = label.split('_');
        courseNameList.add(parts.length >= 3 ? parts.sublist(1, parts.length - 1).join('_') : label);
      }
      return courseNameList;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  /// Read the board's current button label; subscribe.php is a toggle, so
  /// using that endpoint for a read briefly changes the user's subscription.
  static Future<bool> getCourseSubscribe(String bid) async {
    if (bid.isEmpty) throw ArgumentError.value(bid, 'bid', 'Board id must not be empty');
    final response = await dio.post<String>("${_iSchoolPlusUrl}forum/m_node_list.php", data: {'bid': bid});
    final button = html.parse(response.data).getElementById('subscribe');
    final label = button?.text.trim().toLowerCase() ?? '';
    if (label.contains('取消訂閱') || label.contains('unsubscribe')) return true;
    if (label == '訂閱' || label == 'subscribe') return false;
    throw const FormatException('Forum page does not expose a subscription state.');
  }

  static Future<String> getBid(String courseId) => _withCourse(() async {
    if (!await _selectCourse(courseId)) throw StateError('Course is not accessible.');
    final response = await dio.post<String>("${_iSchoolPlusUrl}forum/m_node_list.php");
    final boardId = html.parse(response.data).getElementById('bid')?.attributes['value'];
    if (boardId == null || boardId.isEmpty) throw const FormatException('Course board id is missing.');
    return boardId;
  });

  // WMPro stores the selected course in the HTTP session. Keep each switch
  // and its dependent reads together so parallel callers cannot mix courses.
  static Future<void> _courseQueue = Future<void>.value();

  static Future<T> _withCourse<T>(Future<T> Function() operation) {
    final result = _courseQueue.then((_) => operation());
    _courseQueue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<bool> _selectCourse(String courseId) async {
    html.Document tagNode;
    html.Element node;
    List<html.Element> nodes;
    String result;
    try {
      result = (await dio.get<String>(_getCourseName)).data!.trim();
      tagNode = html.parse(result);
      final courseSelect = tagNode.getElementById("selcourse");
      if (courseSelect == null) return false;
      node = courseSelect;
      nodes = node.getElementsByTagName("option");
      String? courseValue;
      for (int i = 1; i < nodes.length; i++) {
        node = nodes[i];
        String name = node.text.trim().split("_").last;
        if (name == courseId) {
          courseValue = node.attributes["value"];
          break;
        }
      }
      if (courseValue == null) {
        return false;
      }
      String xml = "<manifest><ticket/><course_id>$courseValue</course_id><env/></manifest>";

      await dio.post<String>("${_iSchoolPlusUrl}learn/goto_course.php", data: xml);
      return true;
    } catch (e, stack) {
      Log.eWithStack(e, stack);
      return false;
    }
  }
}
