import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/network.dart';
import 'package:qaq_app/src/model/ntut/ap_tree_json.dart';
import 'package:qaq_app/src/model/ntut/ntut_calendar_json.dart';
import 'package:qaq_app/src/model/userdata/user_data_json.dart';
import 'package:qaq_app/src/portal/simple_login_result.dart';
import 'package:qaq_app/src/store/local_storage.dart';

class NTUTConnector {
  static const host = "https://nportal.ntut.edu.tw/";
  static const _loginUrl = "${host}login.do";
  static const _checkSessionUrl = "${host}myPortal.do";
  static const _localeReloadUrl = "${host}localeReload.do";
  static const _portalApiUserAgent = "Direk android App";
  static const _getPictureUrl = "${host}photoView.do";
  static const _uploadPictureUrl = "${host}photoUpload.do";
  static const _getTreeUrl = "${host}aptreeList.do";
  static const _getCalendarUrl = "${host}calModeApp.do";
  static const maxAvatarUploadBytes = 20 * 1024 * 1024;

  static Future<SimpleLoginResult> login(String account, String password) async {
    final response = await dio.post<String>(
      _loginUrl,
      data: {"muid": account, "mpassword": password},
      options: Options(headers: {'user-agent': _portalApiUserAgent, 'referer': "${host}index.do"}),
    );
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
      await cookieJar.saveFromResponse(Uri.parse(host), [accountCookie]);

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

  static Future<void> clearSession() => cookieJar.delete(Uri.parse(host), true);

  /// Returns true only when the existing cookie-backed session still reaches
  /// the JSON portal API. A logged-out request returns the HTML login flow.
  static Future<bool> checkSession() async {
    try {
      final response = await dio.get<String>(
        _checkSessionUrl,
        options: Options(headers: {'user-agent': _portalApiUserAgent, 'referer': "${host}index.do"}),
      );

      if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      return _isJsonPayload(response.data);
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return false;
    }
  }

  static Future<void> reloadLocale(String locale) async {
    if (locale != 'en' && locale != 'zh_TW') {
      throw ArgumentError.value(locale, 'locale', 'Unsupported nPortal locale');
    }

    final uri = Uri.parse(_localeReloadUrl).replace(queryParameters: {'locale': locale});

    final response = await dio.get<String>(
      uri.toString(),
      options: Options(headers: {'user-agent': _portalApiUserAgent, 'referer': "${host}index.do"}),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw StateError('NTUT locale reload failed with HTTP ${response.statusCode}.');
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
      final data = {"startDate": startDate, "endDate": endDate};

      final result = (await dio.get<String>(_getCalendarUrl, queryParameters: data)).data!.trim();
      final calendarList = getNTUTCalendarJsonList(json.decode(result));
      return calendarList;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<APTreeJson?> getTree(String? arg) async {
    try {
      final result = (await dio.post<String>(_getTreeUrl, data: arg == null ? null : {"apDn": arg})).data!.trim();
      final apTreeJson = APTreeJson.fromJson(json.decode(result));
      return apTreeJson;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }

  static Future<Uint8List> getUserImageBytes() async {
    final userPhoto = LocalStorage.instance.getUserInfo().userPhoto;

    final response = await dio.get<List<int>>(
      _getPictureUrl,
      queryParameters: {'realname': userPhoto},
      options: Options(
        headers: {'user-agent': _portalApiUserAgent, 'referer': "${host}index.do"},
        responseType: ResponseType.bytes,
      ),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Avatar download failed with HTTP ${response.statusCode}.');
    }

    final contentType = response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    if (!contentType.toLowerCase().startsWith('image/')) {
      throw FormatException('Avatar response is not an image: Content-Type=$contentType');
    }

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Avatar response is empty.');
    }

    return Uint8List.fromList(bytes);
  }

  static Future<String> uploadUserImage(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      throw const FormatException('Avatar image is empty.');
    }
    if (imageBytes.length > maxAvatarUploadBytes) {
      throw StateError('Avatar image exceeds the 20 MB upload limit.');
    }

    final oldFilename = LocalStorage.instance.getUserInfo().userPhoto;
    final uploadUri = Uri.parse(
      _uploadPictureUrl,
    ).replace(queryParameters: {'uploadQuota': '20', 'ldapPhoto': oldFilename});

    final response = await dio.post<String>(
      uploadUri.toString(),
      data: FormData.fromMap({'file[]': MultipartFile.fromBytes(imageBytes, filename: 'avatar.jpg')}),
      options: Options(
        headers: {'user-agent': _portalApiUserAgent, 'referer': "${host}index.do"},
        contentType: Headers.multipartFormDataContentType,
      ),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Avatar upload failed with HTTP ${response.statusCode}.');
    }

    final responseJson = _decodeJsonMap(response.data);
    final newFilename = responseJson?['ldapPhoto']?.toString().trim() ?? '';
    if (newFilename.isEmpty) {
      throw const FormatException('Avatar upload response does not contain ldapPhoto.');
    }
    return newFilename;
  }
}
