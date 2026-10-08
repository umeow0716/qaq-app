import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/connector/ischool_plus_connector.dart';
import 'package:qaq_app/src/connector/network.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/connector/score_connector.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/model/ischoolplus/ischool_plus_announcement_json.dart';
import 'package:qaq_app/src/model/userdata/user_data_json.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(options);
    // Consume multipart request streams too, just as a real adapter does.
    if (body != null) await body.drain<void>();
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok(String body, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(body, 200, headers: headers);
ResponseBody _redirect(String location, {int status = 302}) => ResponseBody.fromString(
  '',
  status,
  headers: {
    'location': [location],
  },
  isRedirect: false,
);
String _row(List<String> cells, {String tag = 'td'}) => '<tr>${cells.map((c) => '<$tag>$c</$tag>').join()}</tr>';
String _table(List<List<String>> rows) => '<table>${rows.map((r) => _row(r)).join()}</table>';
const _title = '學號：123456789　姓名：測試學生　班級：資訊四甲　115 學年度 第 1 學期 上課時間表';
final _syllabus = _table([
  List.filled(12, '標題'),
  ['115-1', '371933', '測試課程', '1', '3', '3', '▲', '測試教師', '資訊四甲', '30', '2', '備註'],
]);
List<String> _twCells({bool syllabus = true}) => [
  '３７１９３３',
  '<a href="Curr.jsp?code=AB001">測試課程</a>',
  '1',
  '3',
  '3',
  '',
  '<a href="Teach.jsp?code=T001">測試教師</a>',
  '<a href="Select.jsp?code=C001">資訊四甲</a>',
  '',
  '１２',
  '',
  '',
  '',
  '',
  '',
  '<a href="Croom.jsp?code=R001">測試教室</a>',
  '',
  '',
  syllabus ? '<a href="ShowSyllabus.jsp?snum=371933">大綱</a>' : '',
  '備註',
];
String _tw({bool syllabus = true}) =>
    _table([
      [_title],
    ]) +
    _table([
      [_title],
      List.filled(20, '欄位'),
      List.filled(20, ''),
      _twCells(syllabus: syllabus),
      ['總計'],
    ]);
String _selection =
    '<select id="selcourse"><option value="">選擇</option>'
    '<option value="C001">1151_測試課程_371933</option>'
    '<option value="C002">1151_另一課程_371934</option></select>';
const _board =
    '<input id="bid" value="B001"><form id="formSearch">'
    '<input name="token" value="test-token"><input name="bid" value="B001"></form>'
    '<input id="selectPage" value="1"><input id="inputPerPage" value="10">';
String _sso(String destination) =>
    '<form id="ssoForm" action="/oauth2Server.do">'
    '<input name="redirect_uri" value="$destination"><input name="code" value="test-code"></form>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter originalAdapter;
  late Logger originalLogger;
  late _Adapter adapter;
  void respond(FutureOr<ResponseBody> Function(RequestOptions) handler) {
    adapter = _Adapter(handler);
    dio.httpClientAdapter = adapter;
  }

  void body(String value) => respond((_) => _ok(value));

  setUp(() async {
    originalAdapter = dio.httpClientAdapter;
    originalLogger = Log.logger;
    Log.logger = Logger(output: _SilentOutput());
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    await LocalStorage.instance.init(cookieJar: CookieJar());
    respond((_) => throw StateError('Unexpected request'));
  });
  tearDown(() {
    dio.httpClientAdapter = originalAdapter;
    Log.logger = originalLogger;
    configureNetwork(cookies: CookieJar());
  });

  group('NTUTConnector', () {
    test('login stores returned profile and portal account cookie', () async {
      body(jsonEncode({'success': true, 'givenName': '測試學生', 'userPhoto': 'avatar.jpg'}));
      final value = await NTUTConnector.login('Student', 'test-password');
      expect(value.isSuccess, isTrue);
      expect(LocalStorage.instance.getUserInfo().userPhoto, 'avatar.jpg');
      expect((await cookieJar.loadForRequest(Uri.parse(NTUTConnector.host))).single.value, 'student');
      expect(adapter.requests.single.data, {'muid': 'Student', 'mpassword': 'test-password'});
    });
    test('invalid credentials are returned as a failure', () async {
      body('{"success":false,"errorMsg":"密碼錯誤"}');
      expect((await NTUTConnector.login('Student', 'invalid')).isSuccess, isFalse);
    });
    test('checkSession accepts JSON and rejects redirected login HTML', () async {
      body('{"apList":[]}');
      expect(await NTUTConnector.checkSession(), isTrue);
      respond((r) => r.uri.path == '/myPortal.do' ? _redirect('/login.do') : _ok('<html>Login</html>'));
      expect(await NTUTConnector.checkSession(), isFalse);
      expect(adapter.requests.last.method, 'GET');
    });
    test('clearSession deletes portal cookies', () async {
      final uri = Uri.parse(NTUTConnector.host);
      await cookieJar.saveFromResponse(uri, [Cookie('session', 'test')]);
      await NTUTConnector.clearSession();
      expect(await cookieJar.loadForRequest(uri), isEmpty);
    });
    test('reloadLocale sends supported locale and rejects invalid locale', () async {
      body('{}');
      await NTUTConnector.reloadLocale('zh_TW');
      expect(adapter.requests.single.uri.queryParameters['locale'], 'zh_TW');
      await expectLater(NTUTConnector.reloadLocale('invalid'), throwsArgumentError);
      expect(adapter.requests, hasLength(1));
    });
    test('getCalendar decodes events and date parameters', () async {
      body('[{"calTitle":"開學","calStart":0},{"calTitle":""}]');
      final events = await NTUTConnector.getCalendar(DateTime(2026, 9, 1), DateTime(2026, 10, 1));
      expect(events!.single.calTitle, '開學');
      expect(adapter.requests.single.uri.queryParameters, {'startDate': '2026/09/01', 'endDate': '2026/10/01'});
    });
    test('getTree omits apDn at root and sends it for child nodes', () async {
      body('{"apList":[{"description":"課程"}]}');
      expect((await NTUTConnector.getTree(null))!.apList.single.description, '課程');
      expect(adapter.requests.single.data, isNull);
      await NTUTConnector.getTree('child');
      expect(adapter.requests.last.data, {'apDn': 'child'});
    });
    test('getUserImageBytes requires image content and nonempty bytes', () async {
      LocalStorage.instance.setUserInfo(UserInfoJson(userPhoto: 'avatar.jpg'));
      respond(
        (_) => ResponseBody.fromBytes(
          [137, 80, 78, 71],
          200,
          headers: {
            'content-type': ['image/png'],
          },
        ),
      );
      expect(await NTUTConnector.getUserImageBytes(), [137, 80, 78, 71]);
      expect(adapter.requests.single.uri.queryParameters['realname'], 'avatar.jpg');
      body('<html>Login</html>');
      await expectLater(NTUTConnector.getUserImageBytes(), throwsFormatException);
    });
    test('uploadUserImage uses multipart and validates input and returned filename', () async {
      await expectLater(NTUTConnector.uploadUserImage(Uint8List(0)), throwsFormatException);
      await expectLater(
        NTUTConnector.uploadUserImage(Uint8List(NTUTConnector.maxAvatarUploadBytes + 1)),
        throwsStateError,
      );
      expect(adapter.requests, isEmpty);
      body('{"ldapPhoto":"new-avatar.jpg"}');
      expect(await NTUTConnector.uploadUserImage(Uint8List.fromList([1, 2, 3])), 'new-avatar.jpg');
      expect(adapter.requests.single.data, isA<FormData>());
      expect(adapter.requests.single.contentType, startsWith('multipart/form-data'));
      body('{}');
      await expectLater(NTUTConnector.uploadUserImage(Uint8List.fromList([1])), throwsFormatException);
    });
  });

  group('CourseConnector', () {
    test('login lets Dio follow OAuth POST 302 as GET once', () async {
      respond(
        (r) => switch (r.uri.path) {
          '/ssoIndex.do' => _ok(_sso('https://aps.ntut.edu.tw/course/tw/courseSID.jsp')),
          '/oauth2Server.do' => _redirect('https://aps.ntut.edu.tw/course/tw/courseSID.jsp'),
          '/course/tw/courseSID.jsp' => _ok('課程系統'),
          _ => throw StateError('Unexpected request'),
        },
      );
      expect(await CourseConnector.login(), CourseConnectorStatus.loginSuccess);
      expect(adapter.requests.map((r) => r.method), ['GET', 'POST', 'GET']);
    });
    test('HTML SSO link uses GET and validates final destination', () async {
      respond(
        (r) => switch (r.uri.path) {
          '/ssoIndex.do' => _ok(_sso('https://aps.ntut.edu.tw/course/tw/courseSID.jsp')),
          '/oauth2Server.do' => _ok('<a href="https://aps.ntut.edu.tw/course/tw/courseSID.jsp">Continue</a>'),
          '/course/tw/courseSID.jsp' => _redirect('https://nportal.ntut.edu.tw/login.do'),
          _ => _ok('<html>Login</html>'),
        },
      );
      expect(await CourseConnector.login(), CourseConnectorStatus.loginFail);
      expect(adapter.requests[2].method, 'GET');
    });
    test('getDepartmentMap reads department codes', () async {
      body('<a href="Subj.jsp?format=-2&amp;code=59">資訊工程系</a><a href="help.jsp">Help</a>');
      expect(await CourseConnector.getDepartmentMap('115', '1'), {'59': '資訊工程系'});
    });
    test('getTwoYearUndergraduateDepartmentMap reads division and bracketed names', () async {
      body('<a href="Cprog.jsp?format=-3&amp;division=6">二技【資訊工程系】</a>');
      expect(await CourseConnector.getTwoYearUndergraduateDepartmentMap('115'), {'6': '資訊工程系'});
    });
    test('getCourseSemester parses year and semester', () async {
      body(
        _table([
          ['學期'],
          ['<a href="Select.jsp?year=115&amp;sem=1">115 學年度 1 學期</a>'],
        ]),
      );
      final semesters = await CourseConnector.getCourseSemester('Student');
      expect(semesters!.single, SemesterJson(year: '115', semester: '1'));
    });
    test('getTWCourseMainInfoList skips empty layout rows and keeps URLs', () async {
      body(_tw());
      final info = await CourseConnector.getTWCourseMainInfoList('Student', SemesterJson(year: '115', semester: '1'));
      expect(info!.json, hasLength(1));
      final course = info.json.single;
      expect(course.course.id, '371933');
      expect(course.course.time[Day.Monday], '12');
      expect(course.teacher.single.href, 'https://aps.ntut.edu.tw/course/tw/Teach.jsp?code=T001');
      expect(course.classroom.single.name, '測試教室');
    });
    test('getENCourseMainInfoList parses course, teacher and classroom', () async {
      body(
        _table([
              ['', '', '', '', 'Test Student'],
            ]) +
            _table([
              List.filled(17, 'Header'),
              List.filled(17, ''),
              [
                '371933',
                '<a href="Curr.jsp?code=AB001">Test Course</a>',
                '3',
                '3',
                'Test Teacher',
                '<a href="Select.jsp?code=C001">Class</a>',
                '',
                '12',
                '',
                '',
                '',
                '',
                '',
                '<a href="Croom.jsp?code=R001">Room</a>',
                '',
                '',
                '',
              ],
              ['Total'],
            ]),
      );
      final info = await CourseConnector.getENCourseMainInfoList('Student', SemesterJson(year: '115', semester: '1'));
      expect(info!.json.single.course.name, 'Test Course');
      expect(info.studentName, 'TestStudent');
      expect(info.json.single.classroom.single.href, contains('/course/en/Croom.jsp'));
    });
    test('getTWTeacherCourseMainInfoList parses teacher timetable', () async {
      final cells = _twCells();
      cells[0] = '<a href="Curr.jsp?code=AB001">371933</a>';
      cells.insert(19, '');
      body(
        _table([
          ['教師 姓名 測試教師'],
          List.filled(21, '欄位'),
          List.filled(21, ''),
          cells,
          ['總計'],
        ]),
      );
      final info = await CourseConnector.getTWTeacherCourseMainInfoList(
        'T001',
        SemesterJson(year: '115', semester: '1'),
      );
      expect(info!.json.single.course.id, '371933');
      expect(info.studentName, '測試教師');
    });
    test('getCourseCategory parses enrollment and category', () async {
      body(_syllabus);
      final syllabus = await CourseConnector.getCourseCategory('371933');
      expect(syllabus.courseId, '371933');
      expect(syllabus.applyStudentCount, 30);
      expect(syllabus.withdrawStudentCount, 2);
    });
    test('getCourseExtraInfo skips footers and resolves syllabus', () async {
      respond((r) => _ok(r.uri.path.endsWith('Select.jsp') ? _tw() : _syllabus));
      final info = await CourseConnector.getCourseExtraInfo('371933');
      expect(info!.course.id, '371933');
      expect(info.course.selectNumber, '30');
      expect(info.course.withdrawNumber, '2');
      expect(info.courseSemester, SemesterJson(year: '115', semester: '1'));
    });
    test('getCourseExtraInfo fetches syllabus when timetable has no link', () async {
      respond((r) => _ok(r.uri.path.endsWith('Select.jsp') ? _tw(syllabus: false) : _syllabus));
      expect((await CourseConnector.getCourseExtraInfo('371933'))!.course.selectNumber, '30');
      expect(adapter.requests.last.uri.queryParameters['snum'], '371933');
    });
    test('getClassroomUsage uses Chinese page and keeps both course identifiers', () async {
      body(
        _table([
              ['教室'],
            ]) +
            _table([
              ['節次', '日', '一', '二', '三', '四', '五', '六'],
              ['第１節', '', '(371933)<a href="Curr.jsp?code=AB001">課程</a>', '', '', '', '', ''],
            ]),
      );
      final usage = await CourseConnector.getClassroomUsage('https://aps.ntut.edu.tw/course/en/Croom.jsp?code=R001');
      expect(usage![Day.Monday]![SectionNumber.T_1], {'371933', 'AB001'});
      expect(adapter.requests.single.uri.path, '/course/tw/Croom.jsp');
    });
    test('getYearList excludes unrelated footer anchors', () async {
      body('<a href="Cprog.jsp?format=-2&amp;year=115"> 115 學年度入學</a><a href="help.jsp">輔系事宜</a>');
      expect(await CourseConnector.getYearList(), [' 115 學年度入學']);
    });
    test('getDivisionList keeps query parameters', () async {
      body('<a href="Cprog.jsp?format=-3&amp;year=115&amp;matric=4">四技</a>');
      final divisions = await CourseConnector.getDivisionList('115');
      expect(divisions!.single['code'], {'format': '-3', 'year': '115', 'matric': '4'});
    });
    test('getDepartmentList normalizes whitespace without removing s', () async {
      body(
        _table([
          ['<a href="Cprog.jsp?division=59"> 資訊\n Science </a>'],
        ]),
      );
      expect((await CourseConnector.getDepartmentList({'matric': '4'}))!.single['name'], '資訊Science');
    });
    test('getCreditInfo reads all eight graduation requirements', () async {
      body(
        _table([
          ['系所'],
          ['<a href="Cprog.jsp?division=59">資訊 Science</a>', '10', '20', '5', '30', '40', '15', '12', '128'],
        ]),
      );
      final info = await CourseConnector.getCreditInfo({'matric': '4'}, '資訊Science');
      expect(info!.lowCredit, 128);
      expect(info.outerDepartmentMaxCredit, 12);
      expect(info.courseTypeMinCredit.values, [10, 20, 5, 30, 40, 15]);
    });
    test('getCreditInfo returns no result for an unmatched department', () async {
      body(
        _table([
          ['系所'],
          ['<a href="Cprog.jsp?division=59">資訊工程系</a>', '10', '20', '5', '30', '40', '15', '12', '128'],
        ]),
      );
      expect(await CourseConnector.getCreditInfo({'matric': '4'}, '不存在'), isNull);
    });
    test('strQ2B preserves fullwidth spaces as ASCII spaces', () {
      expect(CourseConnector.strQ2B('Ａ　１２'), 'A 12');
      expect(ScoreConnector.strQ2B('Ａ　１２'), 'A 12');
    });
  });

  group('ISchoolPlusConnector', () {
    ResponseBody select(RequestOptions r, ResponseBody Function(RequestOptions) other) => switch (r.uri.path) {
      '/learn/mooc_sysbar.php' => _ok(_selection),
      '/learn/goto_course.php' => _ok('ok'),
      _ => other(r),
    };
    test('login follows redirects without replaying OAuth POST', () async {
      respond(
        (r) => switch (r.uri.path) {
          '/ssoIndex.do' => _ok(_sso('https://istudy.ntut.edu.tw/login2.php')),
          '/oauth2Server.do' => _redirect('https://istudy.ntut.edu.tw/login2.php'),
          '/login2.php' => _redirect('/mooc/index.php'),
          _ => _ok('Learning portal'),
        },
      );
      expect(await ISchoolPlusConnector.login('Student'), ISchoolPlusConnectorStatus.loginSuccess);
      expect(adapter.requests.map((r) => r.method), ['GET', 'POST', 'GET', 'GET']);
    });
    test('getSSOIndexResponse retries missing forms', () async {
      var calls = 0;
      respond((_) => _ok(++calls == 1 ? 'not ready' : _sso('https://istudy.ntut.edu.tw/login2.php')));
      expect(await ISchoolPlusConnector.getSSOIndexResponse(), contains('ssoForm'));
      expect(calls, 2);
    });
    test('getCourseStudent parses and sorts students, excluding system users', () async {
      respond(
        (r) => select(
          r,
          (_) => _ok(
            _table([
                  ['排名'],
                ]) +
                _table([
                  ['1', '<div>123456790&nbsp;(測試乙)</div>'],
                  ['2', '<div>123456789 (測試甲)</div>'],
                  ['3', '<div>istudyoaa (教務處)</div>'],
                ]),
          ),
        ),
      );
      final result = await ISchoolPlusConnector.getCourseStudent('371933');
      expect(result.status, IPlusReturnStatus.success);
      expect(result.result!.map((s) => s.id), ['123456789', '123456790']);
      expect(result.result!.first.name, '測試甲');
      expect(adapter.requests[1].data, contains('<course_id>C001</course_id>'));
    });
    test('inaccessible course returns noPermission without requesting students', () async {
      body(_selection);
      expect((await ISchoolPlusConnector.getCourseStudent('missing')).status, IPlusReturnStatus.noPermission);
      expect(adapter.requests, hasLength(1));
    });
    test('getCourseFile associates SCORM items with independent form parameters', () async {
      respond(
        (r) => select(
          r,
          (r) => switch (r.uri.path) {
            '/learn/path/launch.php' => _ok('cid=C001,'),
            '/learn/path/pathtree.php' => _ok(
              '<form id="fetchResourceForm"><input name="course_id" value="C001"></form>',
            ),
            _ => _ok(
              '<manifest><item identifierref="R1"><title>講義一</title></item><item identifierref="R2"><title>講義二</title></item>'
              '<resource identifier="R1" xml:base="https://istudycloud.ntut.edu.tw/" href="one.pdf"/>'
              '<resource identifier="R2" xml:base="https://istudycloud.ntut.edu.tw/" href="two.pdf"/></manifest>',
            ),
          },
        ),
      );
      final result = await ISchoolPlusConnector.getCourseFile('371933');
      expect(result.status, IPlusReturnStatus.success);
      expect(result.result, hasLength(2));
      expect(result.result![0].fileType.single.postData['href'], endsWith('@one.pdf'));
      expect(result.result![1].fileType.single.postData['href'], endsWith('@two.pdf'));
    });
    for (final status in [301, 302, 303, 307, 308]) {
      test('getRealFileUrl exposes $status without fetching the download', () async {
        respond((_) => _redirect('/download_preview.php?file=one.pdf', status: status));
        expect(await ISchoolPlusConnector.getRealFileUrl({'course_id': 'C001'}), [
          'https://istudy.ntut.edu.tw/download.php?file=one.pdf',
          'https://istudy.ntut.edu.tw/download.php?file=one.pdf',
        ]);
        expect(adapter.requests, hasLength(1));
      });
    }
    test('getRealFileUrl isolates absolute URL from other quoted values', () async {
      body('location.href="https://istudycloud.ntut.edu.tw/one.pdf"; var other="noise";');
      expect((await ISchoolPlusConnector.getRealFileUrl({}))!.first, 'https://istudycloud.ntut.edu.tw/one.pdf');
    });
    test('getRealFileUrl resolves PDF URL against final redirected preview URI', () async {
      respond(
        (r) => switch (r.uri.path) {
          '/learn/path/SCORM_fetchResource.php' => _ok(
            '<script type="text/javascript">var encoding="UTF-8"; location.href="preview/viewer.html";</script>',
          ),
          '/learn/path/preview/viewer.html' => _redirect('/learn/path/pdf/viewer.html'),
          _ => _ok("const DEFAULT_URL = '../one.pdf'; const other = 'noise';"),
        },
      );
      expect(await ISchoolPlusConnector.getRealFileUrl({}), [
        'https://istudy.ntut.edu.tw/learn/path/one.pdf',
        'https://istudy.ntut.edu.tw/learn/path/pdf/viewer.html',
      ]);
    });
    test('getCourseAnnouncement parses forum response and token', () async {
      respond(
        (r) => select(
          r,
          (r) => _ok(
            r.uri.path.endsWith('m_node_list.php')
                ? _board
                : '{"code":0,"total_rows":"1","data":{"B001|N001":{"subject":"Hello &amp; world","cid":"C001"}}}',
          ),
        ),
      );
      final result = await ISchoolPlusConnector.getCourseAnnouncement('371933');
      expect(result.status, IPlusReturnStatus.success);
      expect(result.result!.single.subject, 'Hello & world');
      expect(result.result!.single.bid, 'B001');
      expect(result.result!.single.nid, 'N001');
      expect(result.result!.single.token, 'test-token');
    });
    test('getCourseAnnouncement accepts measured empty-board response', () async {
      respond(
        (r) => select(
          r,
          (r) =>
              _ok(r.uri.path.endsWith('m_node_list.php') ? _board : '{"code":-1,"message":"沒有任何資料","total_rows":"0"}'),
        ),
      );
      final result = await ISchoolPlusConnector.getCourseAnnouncement('371933');
      expect(result.status, IPlusReturnStatus.success);
      expect(result.result, isEmpty);
    });
    test('getCourseAnnouncement does not mark server errors as success', () async {
      respond(
        (r) => select(
          r,
          (r) => _ok(r.uri.path.endsWith('m_node_list.php') ? _board : '{"code":-2,"message":"not authorized"}'),
        ),
      );
      expect((await ISchoolPlusConnector.getCourseAnnouncement('371933')).status, IPlusReturnStatus.fail);
    });
    test('getCourseAnnouncementDetail resolves attachment links', () async {
      body(
        '<div class="main node-info" data-title="公告"></div><div class="author-name">測試教師</div>'
        '<div class="post-time">2026-10-08</div><div class="bottom-tmp"><div class="content"><p>內容</p></div>'
        '<div class="file"><a href="/files/one.pdf">one</a><a href="https://istudycloud.ntut.edu.tw/two.pdf">two</a></div></div>',
      );
      final info = ISchoolPlusAnnouncementJson.fromJson({'subject': '公告'});
      final detail = await ISchoolPlusConnector.getCourseAnnouncementDetail(info);
      expect(detail!['title'], '公告');
      expect(detail['file'], {
        'one': 'https://istudy.ntut.edu.tw/files/one.pdf',
        'two': 'https://istudycloud.ntut.edu.tw/two.pdf',
      });
    });
    test('getSubscribeNotice tolerates demo rows and retains underscores in names', () async {
      body(
        _table([
          ['課號', '課程名稱'],
          ['1001', 'DEMO課程'],
          ['1002', '1151_測試_課程_371933'],
        ]),
      );
      expect(await ISchoolPlusConnector.getSubscribeNotice(), ['DEMO課程', '測試_課程']);
    });
    test('getBid selects requested course each time without cached board state', () async {
      var course = '';
      respond(
        (r) => select(r, (r) {
          if (r.uri.path.endsWith('m_node_list.php')) {
            return _ok('<input id="bid" value="${course == 'C001' ? 'B001' : 'B002'}">');
          }
          throw StateError('Unexpected request');
        }),
      );
      // Observe the course switch while keeping the same transport behavior.
      final base = adapter.respond;
      respond((r) {
        if (r.uri.path.endsWith('goto_course.php')) course = r.data.toString().contains('C001') ? 'C001' : 'C002';
        return base(r);
      });
      expect(await ISchoolPlusConnector.getBid('371933'), 'B001');
      expect(await ISchoolPlusConnector.getBid('371934'), 'B002');
    });
    test('parallel course reads do not cross the server session course context', () async {
      var selected = '';
      respond((r) async {
        if (r.uri.path.endsWith('mooc_sysbar.php')) return _ok(_selection);
        if (r.uri.path.endsWith('goto_course.php')) {
          selected = r.data.toString().contains('C001') ? 'C001' : 'C002';
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return _ok('ok');
        }
        return _ok('<input id="bid" value="${selected == 'C001' ? 'B001' : 'B002'}">');
      });
      expect(await Future.wait([ISchoolPlusConnector.getBid('371933'), ISchoolPlusConnector.getBid('371934')]), [
        'B001',
        'B002',
      ]);
      await expectLater(ISchoolPlusConnector.getBid('missing'), throwsStateError);
      expect(await ISchoolPlusConnector.getBid('371933'), 'B001');
    });
    test('getCourseSubscribe reads state without toggling it', () async {
      body('<a id="subscribe">取消訂閱</a>');
      expect(await ISchoolPlusConnector.getCourseSubscribe('B001'), isTrue);
      expect(adapter.requests.single.uri.path, '/forum/m_node_list.php');
      body('<a id="subscribe">Subscribe</a>');
      expect(await ISchoolPlusConnector.getCourseSubscribe('B001'), isFalse);
      await expectLater(ISchoolPlusConnector.getCourseSubscribe(''), throwsArgumentError);
    });
    test('courseSubscribe toggles once only when a state change is required', () async {
      var subscribed = false;
      respond((r) {
        if (r.uri.path.endsWith('subscribe.php')) {
          subscribed = !subscribed;
          return _ok('<title>Success</title>');
        }
        return _ok('<a id="subscribe">${subscribed ? '取消訂閱' : '訂閱'}</a>');
      });
      expect(await ISchoolPlusConnector.courseSubscribe('B001', true), isTrue);
      expect(subscribed, isTrue);
      expect(await ISchoolPlusConnector.courseSubscribe('B001', true), isTrue);
      expect(adapter.requests.where((r) => r.uri.path.endsWith('subscribe.php')), hasLength(1));
      expect(await ISchoolPlusConnector.courseSubscribe('B001', false), isTrue);
      expect(subscribed, isFalse);
    });
  });

  group('ScoreConnector', () {
    test('login follows OAuth redirects and checks final host', () async {
      respond(
        (r) => switch (r.uri.path) {
          '/ssoIndex.do' => _ok(_sso('https://aps-course.ntut.edu.tw/StuQuery/LoginOAuth.jsp')),
          '/oauth2Server.do' => _redirect('https://aps-course.ntut.edu.tw/StuQuery/LoginOAuth.jsp'),
          _ => _ok('Score portal'),
        },
      );
      expect(await ScoreConnector.login(), ScoreConnectorStatus.loginSuccess);
      expect(adapter.requests.map((r) => r.method), ['GET', 'POST', 'GET']);
    });
    test('getScoreRankList parses course scores and both rankings', () async {
      final scoreRows =
          '<table>${_row(List.filled(8, 'Heading'), tag: 'th')}'
          '${_row(['AB001', '', '測試課程', 'Test Course', '', '', '3.0', '90'], tag: 'th')}'
          '${_row(['subtotal'])}${_row(['88'])}${_row(['85'])}${_row(['3'])}${_row(['3'])}${_row(['footer'])}</table>';
      final scores = '<form><input type="submit" value="115 學年度 第 1 學期"></form>$scoreRows';
      final ranks = _table([
        ['115 學年度 1', 'Class', '2', '30', '6.67%', '3', '30', '10%'],
        ['', 'Group', '0', '0', '0', '0', '0', '0'],
        ['', '4', '100', '4%', '5', '100', '5%'],
      ]);
      respond((r) => _ok(r.uri.path.endsWith('QryScore.jsp') ? scores : ranks));
      final result = await ScoreConnector.getScoreRankList();
      expect(result.single.courseScoreList.single.score, '90');
      expect(result.single.courseScoreList.single.credit, 3);
      expect(result.single.now.course.rank, 2);
      expect(result.single.now.department.rank, 4);
      expect(result.single.history.course.rank, 3);
    });
    test('getScoreRankList reports evaluation gate instead of empty success', () async {
      body('Course Evaluation Questionnaire');
      await expectLater(ScoreConnector.getScoreRankList(), throwsFormatException);
    });
  });
}
