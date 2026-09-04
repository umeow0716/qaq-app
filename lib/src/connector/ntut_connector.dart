// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/core/connector_parameter.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/model/ntut/ap_tree_json.dart';
import 'package:flutter_app/src/model/ntut/ntut_calendar_json.dart';
import 'package:flutter_app/src/model/userdata/user_data_json.dart';
import 'package:flutter_app/src/portal/simple_login_result.dart';
import 'package:flutter_app/src/store/local_storage.dart';
import 'package:intl/intl.dart';

class NTUTConnector {
  static const host = "https://nportal.ntut.edu.tw/";
  static const _loginUrl = "${host}login.do";
  static const _checkSessionUrl = "${host}myPortal.do";
  static const _portalApiUserAgent = "Direk android App";
  static const _getPictureUrl = "${host}photoView.do";
  static const _getTreeUrl = "${host}aptreeList.do";
  static const _getCalendarUrl = "${host}calModeApp.do";
  static const _changePasswordUrl = "${host}passwordMdy.do";

  static Future<SimpleLoginResult> login(String account, String password) async {
    final parameter = ConnectorParameter(_loginUrl)
      ..userAgent = _portalApiUserAgent
      ..referer = _loginUrl
      ..data = {
        "muid": account,
        "mpassword": password,
      };

    final response = await Connector.getDataByPostResponse(parameter);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('NTUT login failed with HTTP ${response.statusCode}.');
    }

    final responseJson = _decodeJsonMap(response.data);
    if (responseJson == null) {
      throw const FormatException('NTUT login response is not a JSON object.');
    }

    final loginResult = SimpleLoginResult.fromJson(responseJson);

    if (loginResult.isSuccess) {
      // The portal frontend expects the account cookie in addition to the
      // server-managed session cookie returned by login.do.
      final accountCookie = Cookie('muid', account.toLowerCase())..path = '/';
      await DioConnector.instance.cookiesManager.saveFromResponse(
        Uri.parse(host),
        [accountCookie],
      );

      final userInfo = UserInfoJson(
        givenName: loginResult.userNaturalName,
        userMail: loginResult.userMail,
        userPhoto: loginResult.userPhotoName,
        userDn: loginResult.userDn,
        passwordExpiredRemind: loginResult.passwordExpiredRemind,
      );

      LocalStorage.instance.setUserInfo(userInfo);
      await LocalStorage.instance.saveUserData();
    }

    return loginResult;
  }

  /// Returns true only when the existing cookie-backed session still reaches
  /// the JSON portal API. A logged-out request returns the HTML login flow.
  static Future<void> clearSession() => DioConnector.instance.deleteCookiesFor(Uri.parse(host));

  static Future<bool> checkSession() async {
    try {
      final parameter = ConnectorParameter(_checkSessionUrl)
        ..userAgent = _portalApiUserAgent
        ..referer = "${host}index.do";
      final response = await Connector.getDataByGetResponse(parameter);

      if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      return _isJsonPayload(response.data);
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return false;
    }
  }

  static Map<String, dynamic>? _decodeJsonMap(dynamic data) {
    dynamic decoded = data;
    if (decoded is String) {
      decoded = json.decode(decoded);
    }

    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }

  static bool _isJsonPayload(dynamic data) {
    try {
      dynamic decoded = data;
      if (decoded is String) {
        decoded = json.decode(decoded);
      }
      return decoded is Map || decoded is List;
    } catch (_) {
      return false;
    }
  }

  static Future<List<NTUTCalendarJson>?> getCalendar(DateTime startTime, DateTime endTime) async {
    final formatter = DateFormat("yyyy/MM/dd");
    final startDate = formatter.format(startTime);
    final endDate = formatter.format(endTime);
    try {
      final data = {
        "startDate": startDate,
        "endDate": endDate,
      };
      final parameter = ConnectorParameter(_getCalendarUrl);
      parameter.data = data;
      final result = await Connector.getDataByGet(parameter);
      final calendarList = getNTUTCalendarJsonList(json.decode(result));
      return calendarList;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<APTreeJson?> getTree(String? arg) async {
    try {
      final parameter = ConnectorParameter(_getTreeUrl);
      if (arg != null) {
        parameter.data = {"apDn": arg};
      }
      final result = await Connector.getDataByPost(parameter);
      final apTreeJson = APTreeJson.fromJson(json.decode(result));
      return apTreeJson;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<Map<String, Map<String, String>>> getUserImageRequestInfo() async {
    final imageInfo = <String, Map<String, String>>{};
    final userPhoto = LocalStorage.instance.getUserInfo().userPhoto;
    Log.d("getUserImage");

    final url = '$_getPictureUrl?realname=$userPhoto';

    imageInfo['url'] = {'value': url};
    imageInfo['header'] = await Connector.getLoginHeaders(url);

    return imageInfo;
  }

  static Future<String?> changePassword(String password) async {
    try {
      final parameter = ConnectorParameter(_changePasswordUrl);
      final oldPassword = LocalStorage.instance.getPassword();
      parameter.data = {
        "userPassword": password,
        "oldPassword": oldPassword,
        "pwdForceMdy": "profile",
      };
      final result = await Connector.getDataByPost(parameter);
      final jsonResult = json.decode(result);
      if (jsonResult["success"] == 'true') {
        return "";
      } else {
        return jsonResult["returnMsg"];
      }
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }
}
