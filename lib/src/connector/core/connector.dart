import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/connector/ischool_plus_access_guard.dart';

import 'connector_parameter.dart';
import 'dio_connector.dart';

class Connector {
  static Future<String> getDataByPost(ConnectorParameter parameter) async {
    await IStudyAccessGuard.ensureUrlAllowed(parameter.url);
    try {
      String result = await DioConnector.instance.getDataByPost(parameter);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  static Future<String> getDataByGet(ConnectorParameter parameter) async {
    await IStudyAccessGuard.ensureUrlAllowed(parameter.url);
    try {
      String result = await DioConnector.instance.getDataByGet(parameter);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Response> getDataByGetResponse(ConnectorParameter parameter) async {
    await IStudyAccessGuard.ensureUrlAllowed(parameter.url);
    Response result;
    try {
      result = await DioConnector.instance.getDataByGetResponse(parameter);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Response> getDataByPostResponse(ConnectorParameter parameter) async {
    await IStudyAccessGuard.ensureUrlAllowed(parameter.url);
    Response result;
    try {
      result = await DioConnector.instance.getDataByPostResponse(parameter);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, String>?> getLoginHeaders(String url) async {
    try {
      final cookieJar = DioConnector.instance.cookiesManager;
      final headers = Map<String, String>.from(DioConnector.instance.headers);
      final cookies = await cookieJar.loadForRequest(Uri.parse(url));

      headers[HttpHeaders.cookieHeader] = cookies.first.toString();
      headers.remove(HttpHeaders.contentTypeHeader);

      return headers;
    } catch (e) {
      Log.d(e.toString());
      return null;
    }
  }

  static Future<String?> getFileName(String url) async {
    String? fileName;
    try {
      ConnectorParameter parameter = ConnectorParameter(url);
      Map<String, List<String>> headers = await DioConnector.instance.getHeadersByGet(parameter);
      final contentDisposition = headers["content-disposition"];
      if (contentDisposition != null && contentDisposition.isNotEmpty) {
        //代表有名字
        RegExp exp = RegExp("['|\"](?<name>.+)['|\"]");
        final matches = exp.firstMatch(contentDisposition.first);
        fileName = matches?.group(1);
      } else {
        final contentType = headers["content-type"];
        if (contentType != null && contentType.isNotEmpty && contentType.first.toLowerCase().contains("pdf")) {
          //是application/pdf
          fileName = '.pdf';
        }
      }
      final contentLength = headers["content-length"];
      if (contentLength != null && contentLength.isNotEmpty) {
        final size = contentLength.first;
        Log.d("file size = $size");
      }
      Log.d("getFileName $fileName");
      return fileName;
    } catch (e) {
      Log.d(e.toString());
      return null;
    }
  }
}
