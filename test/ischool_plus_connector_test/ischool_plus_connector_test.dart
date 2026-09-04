// TODO: remove sdk version selector after migrating to null-safety.
// @dart=2.10
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_app/src/connector/blocked_cookies.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/connector/interceptors/request_interceptor.dart';
import 'package:flutter_app/src/connector/interceptors/response_cookie_filter.dart';
import 'package:flutter_app/src/connector/ischool_plus_connector.dart';
import 'package:flutter_app/src/connector/ntut_connector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp();

  final appDocDir = join(tempDir.path, '.cookies');
  final CookieJar cookieJar = PersistCookieJar(storage: FileStorage('$appDocDir/.cookies'));
  final apiInterceptors = [
    ResponseCookieFilter(blockedCookieNamePatterns: blockedCookieNamePatterns),
    CookieManager(cookieJar),
    RequestInterceptors(),
  ];
  await DioConnector.instance.init(
    interceptors: apiInterceptors,
    cookieJar: cookieJar,
  );

  const credentialFilePath = 'test/ischool_plus_connector_test/credential.json';
  final file = File(credentialFilePath);
  final json = jsonDecode(await file.readAsString());
  final userId = json['userId'];
  final password = json['password'];

  dev.log('userId: $userId');
  dev.log('password: $password');

  final Stopwatch stopwatch = Stopwatch()..start();
  test('ntut_login', () async {
    final loginResult = await NTUTConnector.login(userId, password);
    expect(loginResult.isSuccess, isTrue);
    expect(await NTUTConnector.checkSession(), isTrue);
    dev.log('ntut login Done Test execution time: ${stopwatch.elapsed}');
  });
  test('ischool_login', () async {
    final result = await ISchoolPlusConnector.login(userId);
    expect(result, ISchoolPlusConnectorStatus.loginSuccess);
    dev.log('ischool login Done Test execution time: ${stopwatch.elapsed}');
    stopwatch.stop();
  });
}
