import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:logger/logger.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_http_client.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_models.dart';
import 'package:qaq_app/src/connector/ischool_plus_connector.dart';
import 'package:qaq_app/src/connector/network.dart';
import 'package:qaq_app/src/connector/ntut_certificate_policy.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/connector/score_connector.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

// Optional private captures stay outside the repository; never print bodies,
// credentials, query strings, or cookies in test output.
class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.delegate, this.directory);
  final HttpClientAdapter delegate;
  final String? directory;
  int sequence = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) async {
    final response = await delegate.fetch(options, body, cancel);
    if (directory == null) return response;
    final bytes = BytesBuilder();
    await for (final chunk in response.stream) {
      bytes.add(chunk);
    }
    final data = bytes.takeBytes();
    final name = '${++sequence}-${options.uri.host}-${options.uri.path.replaceAll('/', '_')}.body';
    await File('$directory/$name').writeAsBytes(data);
    return ResponseBody.fromBytes(
      data,
      response.statusCode,
      headers: response.headers,
      isRedirect: response.isRedirect,
      statusMessage: response.statusMessage,
    );
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final account = Platform.environment['GP_USERNAME'];
  final password = Platform.environment['GP_PASSWORD'];
  test(
    'authenticated read methods return usable campus data',
    () async {
      // Flutter's widget-test binding otherwise replaces HTTP with empty 400s.
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (_) async => null,
      );
      final originalDebugPrint = debugPrint;
      final originalLogger = Log.logger;
      debugPrint = (String? message, {int? wrapWidth}) {};
      Log.logger = Logger(output: _SilentOutput());
      final previousAdapter = dio.httpClientAdapter;
      final connector = GlobalProtectConnector();
      GlobalProtectConnection? connection;
      GlobalProtectHttpClient? tunnel;
      final failures = <String>[];
      Future<T?> check<T>(String name, Future<T> Function() run, bool Function(T) valid) async {
        try {
          final value = await run();
          if (!valid(value)) {
            failures.add(name);
            stdout.writeln('[FAIL] $name returned unusable data');
          } else {
            stdout.writeln('[PASS] $name');
          }
          return value;
        } catch (_) {
          failures.add(name);
          stdout.writeln('[FAIL] $name threw an exception');
          return null;
        }
      }

      try {
        await LocalStorage.instance.init(cookieJar: CookieJar());
        dio.httpClientAdapter = _CaptureAdapter(previousAdapter, Platform.environment['CONNECTOR_CAPTURE_DIR']);
        LocalStorage.instance.setAccount(account!);
        LocalStorage.instance.setPassword(password!);
        await check('NTUT.login', () => NTUTConnector.login(account, password), (v) => v.isSuccess);
        await check('NTUT.checkSession', NTUTConnector.checkSession, (v) => v);
        await check(
          'NTUT.getCalendar',
          () => NTUTConnector.getCalendar(DateTime(2026, 1), DateTime(2027, 1)),
          (v) => v != null && v.isNotEmpty,
        );
        await check('NTUT.getTree', () => NTUTConnector.getTree(null), (v) => v != null && v.apList.isNotEmpty);
        await check('NTUT.getUserImageBytes', NTUTConnector.getUserImageBytes, (v) => v.isNotEmpty);
        // The test machine cannot directly reach APS; carry those probes over GP.
        // Production routing is unchanged and covered separately by network tests.
        connection = await connector.connectWithPassword(username: account, password: password);
        tunnel = GlobalProtectHttpClient.fromConnection(
          connection,
          badCertificateCallback: NtutCertificatePolicy.allowBadCertificate,
        );
        dio.httpClientAdapter = _CaptureAdapter(
          IOHttpClientAdapter(createHttpClient: () => tunnel!.client),
          Platform.environment['CONNECTOR_CAPTURE_DIR'],
        );
        await check('Score.login', ScoreConnector.login, (v) => v == ScoreConnectorStatus.loginSuccess);
        await check(
          'Score.getScoreRankList',
          ScoreConnector.getScoreRankList,
          (v) => v.isNotEmpty && v.any((s) => s.courseScoreList.isNotEmpty),
        );
        await check('Course.login', CourseConnector.login, (v) => v == CourseConnectorStatus.loginSuccess);
        final semesters = await check(
          'Course.getCourseSemester',
          () => CourseConnector.getCourseSemester(account),
          (v) => v != null && v.isNotEmpty,
        );
        CourseMainInfo? tw;
        SemesterJson? semester;
        for (final candidate in semesters ?? <SemesterJson>[]) {
          tw = await CourseConnector.getTWCourseMainInfoList(account, candidate);
          if (tw != null && tw.json.isNotEmpty) {
            semester = candidate;
            break;
          }
        }
        if (tw == null || tw.json.isEmpty) {
          failures.add('Course.getTWCourseMainInfoList');
        } else {
          stdout.writeln('[PASS] Course.getTWCourseMainInfoList');
          await check(
            'Course.getENCourseMainInfoList',
            () => CourseConnector.getENCourseMainInfoList(account, semester!),
            (v) => v != null && v.json.isNotEmpty,
          );
          final course = tw.json.first;
          await check(
            'Course.getCourseCategory',
            () => CourseConnector.getCourseCategory(course.course.id),
            (v) => v.courseId.isNotEmpty,
          );
          await check(
            'Course.getCourseExtraInfo',
            () => CourseConnector.getCourseExtraInfo(course.course.id),
            (v) => v != null && v.course.id.isNotEmpty,
          );
          final room = tw.json.expand((c) => c.classroom).where((r) => r.href.isNotEmpty).firstOrNull;
          if (room != null) {
            await check(
              'Course.getClassroomUsage',
              () => CourseConnector.getClassroomUsage(room.href),
              (v) => v != null,
            );
          }
          final teacher = tw.json.expand((c) => c.teacher).where((t) => t.href.isNotEmpty).firstOrNull;
          final teacherId = teacher == null ? null : Uri.parse(teacher.href).queryParameters['code'];
          if (teacherId != null) {
            await check(
              'Course.getTWTeacherCourseMainInfoList',
              () => CourseConnector.getTWTeacherCourseMainInfoList(teacherId, semester!),
              (v) => v != null && v.json.isNotEmpty,
            );
          }
          await check(
            'Course.getDepartmentMap',
            () => CourseConnector.getDepartmentMap(semester!.year, semester.semester),
            (v) => v != null && v.isNotEmpty,
          );
          await check(
            'Course.getTwoYearUndergraduateDepartmentMap',
            () => CourseConnector.getTwoYearUndergraduateDepartmentMap(semester!.year),
            (v) => v != null,
          );
        }
        var checkedRoom = false;
        var checkedTeacher = false;
        for (final candidate in semesters ?? <SemesterJson>[]) {
          final info = await CourseConnector.getTWCourseMainInfoList(account, candidate);
          if (info == null) continue;
          final room = info.json.expand((c) => c.classroom).where((r) => r.href.isNotEmpty).firstOrNull;
          if (!checkedRoom && room != null) {
            await check(
              'Course.getClassroomUsage',
              () => CourseConnector.getClassroomUsage(room.href),
              (v) => v != null,
            );
            checkedRoom = true;
          }
          final teacher = info.json.expand((c) => c.teacher).where((t) => t.href.isNotEmpty).firstOrNull;
          final teacherId = teacher == null ? null : Uri.parse(teacher.href).queryParameters['code'];
          if (!checkedTeacher && teacherId != null) {
            await check(
              'Course.getTWTeacherCourseMainInfoList',
              () => CourseConnector.getTWTeacherCourseMainInfoList(teacherId, candidate),
              (v) => v != null && v.json.isNotEmpty,
            );
            checkedTeacher = true;
          }
          if (checkedRoom && checkedTeacher) break;
        }
        if (!checkedRoom) stdout.writeln('[UNAVAILABLE] no classroom links');
        if (!checkedTeacher) stdout.writeln('[UNAVAILABLE] no teacher links');
        final years = await check('Course.getYearList', CourseConnector.getYearList, (v) => v != null && v.isNotEmpty);
        if (years != null && years.isNotEmpty) {
          final year = RegExp(r'\d+').firstMatch(years.first)!.group(0)!;
          final divisions = await check(
            'Course.getDivisionList',
            () => CourseConnector.getDivisionList(year),
            (v) => v != null && v.isNotEmpty,
          );
          if (divisions != null && divisions.isNotEmpty) {
            final departments = await check(
              'Course.getDepartmentList',
              () => CourseConnector.getDepartmentList(divisions.first['code'] as Map),
              (v) => v != null && v.isNotEmpty,
            );
            if (departments != null && departments.isNotEmpty) {
              final selected = departments.first;
              await check(
                'Course.getCreditInfo',
                () => CourseConnector.getCreditInfo(divisions.first['code'] as Map, selected['name'] as String),
                (v) => v != null && v.lowCredit > 0,
              );
            }
          }
        }
        await check(
          'iSchool.getSSOIndexResponse',
          ISchoolPlusConnector.getSSOIndexResponse,
          (v) => v.contains('ssoForm'),
        );
        await check(
          'iSchool.login',
          () => ISchoolPlusConnector.login(account),
          (v) => v == ISchoolPlusConnectorStatus.loginSuccess,
        );
        final bar = await dio.get<String>('https://istudy.ntut.edu.tw/learn/mooc_sysbar.php');
        final options = html
            .parse(bar.data)
            .querySelectorAll('#selcourse option')
            .where((o) => (o.attributes['value'] ?? '').isNotEmpty && o.text.contains('_'))
            .toList();
        if (options.isNotEmpty) {
          var checkedFileUrl = false;
          var checkedDetail = false;
          String? selectedId;
          for (final option in options.reversed.take(10)) {
            final id = option.text.trim().split('_').last;
            selectedId = id;
            if (!checkedFileUrl) {
              final files = await ISchoolPlusConnector.getCourseFile(id);
              expect(files.status, IPlusReturnStatus.success);
              final file = files.result?.firstOrNull;
              if (file != null) {
                await check(
                  'iSchool.getRealFileUrl',
                  () => ISchoolPlusConnector.getRealFileUrl(
                    Map<String, String>.from(file.fileType.first.postData as Map),
                  ),
                  (v) => v != null && v.length == 2,
                );
                checkedFileUrl = true;
              }
            }
            if (!checkedDetail) {
              final announcements = await ISchoolPlusConnector.getCourseAnnouncement(id);
              expect(announcements.status, IPlusReturnStatus.success);
              final announcement = announcements.result?.firstOrNull;
              if (announcement != null) {
                await check(
                  'iSchool.getCourseAnnouncementDetail',
                  () => ISchoolPlusConnector.getCourseAnnouncementDetail(announcement),
                  (v) => v != null,
                );
                checkedDetail = true;
              }
            }
            if (checkedFileUrl && checkedDetail) break;
          }
          if (!checkedFileUrl) stdout.writeln('[UNAVAILABLE] no resources in the sampled enrolled courses');
          if (!checkedDetail) stdout.writeln('[UNAVAILABLE] no announcements in the sampled enrolled courses');
          final id = selectedId!;
          await check(
            'iSchool.getCourseStudent',
            () => ISchoolPlusConnector.getCourseStudent(id),
            (v) => v.status == IPlusReturnStatus.success && v.result != null,
          );
          await check(
            'iSchool.getCourseFile',
            () => ISchoolPlusConnector.getCourseFile(id),
            (v) => v.status == IPlusReturnStatus.success && v.result != null,
          );
          await check(
            'iSchool.getCourseAnnouncement',
            () => ISchoolPlusConnector.getCourseAnnouncement(id),
            (v) => v.status == IPlusReturnStatus.success && v.result != null,
          );
          final board = await check('iSchool.getBid', () => ISchoolPlusConnector.getBid(id), (v) => v.isNotEmpty);
          if (board != null && board.isNotEmpty) {
            await check(
              'iSchool.getCourseSubscribe',
              () => ISchoolPlusConnector.getCourseSubscribe(board),
              (_) => true,
            );
          }
        } else {
          stdout.writeln('[UNAVAILABLE] no enrolled iSchool courses');
        }
        await check('iSchool.getSubscribeNotice', ISchoolPlusConnector.getSubscribeNotice, (v) => v != null);
        await tunnel.close(force: true);
        tunnel = null;
        await connection.transport.close();
        final savedSession = connection.session;
        final savedGateway = connection.gateway;
        connection = await connector.resumeWithSession(gateway: savedGateway, session: savedSession);
        tunnel = GlobalProtectHttpClient.fromConnection(
          connection,
          badCertificateCallback: NtutCertificatePolicy.allowBadCertificate,
        );
        dio.httpClientAdapter = _CaptureAdapter(
          IOHttpClientAdapter(createHttpClient: () => tunnel!.client),
          Platform.environment['CONNECTOR_CAPTURE_DIR'],
        );
        await check(
          'GP.resumeWithSession',
          () => dio.get<String>('https://istudy.ntut.edu.tw/learn/mooc_sysbar.php'),
          (v) => v.statusCode == 200 && v.realUri.path == '/learn/mooc_sysbar.php',
        );
        expect(failures, isEmpty, reason: 'Failures contain method names only; inspect private captures locally.');
      } finally {
        dio.httpClientAdapter = previousAdapter;
        await tunnel?.close(force: true);
        await connection?.transport.close();
        connector.close();
        configureNetwork(cookies: CookieJar());
        debugPrint = originalDebugPrint;
        Log.logger = originalLogger;
      }
    },
    skip: account == null || password == null ? 'Set GP_USERNAME and GP_PASSWORD for live method checks.' : false,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
