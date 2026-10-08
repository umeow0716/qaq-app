import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_http_client.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_models.dart';
import 'package:qaq_app/src/connector/network.dart';
import 'package:qaq_app/src/connector/ntut_certificate_policy.dart';
import 'package:qaq_app/src/connector/score_connector.dart';

void main() {
  final account = Platform.environment['GP_USERNAME'];
  final password = Platform.environment['GP_PASSWORD'];
  test(
    'ranking and teacher course responses are UTF-8 without Big5 overrides',
    () async {
      final connector = GlobalProtectConnector();
      final previousAdapter = dio.httpClientAdapter;
      GlobalProtectConnection? connection;
      GlobalProtectHttpClient? tunnel;
      Dio? probe;
      try {
        configureNetwork(cookies: CookieJar());
        await dio.post<String>(
          'https://nportal.ntut.edu.tw/login.do',
          data: {'muid': account, 'mpassword': password},
          options: Options(headers: {'user-agent': 'Direk android App'}),
        );
        await cookieJar.saveFromResponse(Uri.parse('https://nportal.ntut.edu.tw/'), [
          Cookie('muid', account!.toLowerCase())..path = '/',
        ]);
        connection = await connector.connectWithPassword(username: account, password: password!);
        tunnel = GlobalProtectHttpClient.fromConnection(
          connection,
          badCertificateCallback: NtutCertificatePolicy.allowBadCertificate,
        );
        // This probe deliberately carries APS over GP, as direct APS access from
        // the test machine times out. Production host routing stays unchanged.
        probe = createDio(
          directAdapter: IOHttpClientAdapter(createHttpClient: () => tunnel!.client),
          useGlobalProtect: false,
          cookies: cookieJar,
        );
        dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => tunnel!.client);
        expect(await ScoreConnector.login(), ScoreConnectorStatus.loginSuccess);
        expect(await CourseConnector.login(), CourseConnectorStatus.loginSuccess);
        // A registration page does not always expose an advisor link. Use an
        // actual teacher from one of this account's enrolled course tables.
        String? tutorId;
        final semesters = await CourseConnector.getCourseSemester(account);
        for (final semester in semesters ?? []) {
          final courses = await CourseConnector.getTWCourseMainInfoList(account, semester);
          final teacher = courses?.json
              .expand((course) => course.teacher)
              .where((teacher) => teacher.href.isNotEmpty)
              .firstOrNull;
          if (teacher != null) tutorId = Uri.parse(teacher.href).queryParameters['code'];
          if (tutorId != null) break;
        }
        expect(tutorId, isNotNull, reason: 'Use a real teacher link from authenticated course records.');
        dio.httpClientAdapter = previousAdapter;
        for (final request in <(String, Map<String, String>)>[
          ('https://aps-course.ntut.edu.tw/StuQuery/QryRank.jsp', {'format': '-2'}),
          (
            'https://aps.ntut.edu.tw/course/tw/Teach.jsp',
            {
              'code': tutorId!,
              'format': '-3',
              'year': (DateTime.now().year - (DateTime.now().month >= 8 ? 1911 : 1912)).toString(),
              'sem': DateTime.now().month >= 8 || DateTime.now().month <= 1 ? '1' : '2',
            },
          ),
        ]) {
          final response = request.$1.contains('Teach.jsp')
              ? await probe.post<List<int>>(
                  request.$1,
                  data: request.$2,
                  options: Options(responseType: ResponseType.bytes),
                )
              : await probe.get<List<int>>(
                  request.$1,
                  queryParameters: request.$2,
                  options: Options(responseType: ResponseType.bytes),
                );
          expect(response.statusCode, 200);
          final bytes = response.data!;
          final text = utf8.decode(bytes); // Strict decode: rejects any legacy Big5 bytes.
          final meta = RegExp(
            r'charset\s*=\s*["\x27]?([a-zA-Z0-9_-]+)',
            caseSensitive: false,
          ).firstMatch(text)?.group(1);
          final chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
          stdout.writeln(
            '[encoding] ${response.realUri.host}${response.realUri.path} '
            'Content-Type=${response.headers.value("content-type")} meta=$meta strictUtf8=true chinese=$chinese bytes=${bytes.length}',
          );
          expect(chinese, greaterThan(0), reason: 'Verify a Chinese page, not an ASCII login/error response.');
          expect(text, isNot(contains('\uFFFD')));
          if (request.$1.contains('QryRank.jsp')) expect(text, contains('排名'));
          if (request.$1.contains('Teach.jsp')) {
            expect(text, contains('教師'));
            expect(
              html.parse(text).querySelectorAll('table'),
              isNotEmpty,
              reason: 'Verify the teacher course page, not an error.',
            );
          }
        }
      } finally {
        dio.httpClientAdapter = previousAdapter;
        probe?.close(force: true);
        await tunnel?.close(force: true);
        await connection?.transport.close();
        connector.close();
        configureNetwork(cookies: CookieJar());
      }
    },
    skip: account == null || password == null ? 'Set GP_USERNAME and GP_PASSWORD for live encoding checks.' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
