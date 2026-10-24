import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/share/course_table_share_data.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    await LocalStorage.instance.init(cookieJar: CookieJar());
  });

  test('imported course table cache is persisted separately from favorites', () async {
    final storage = LocalStorage.instance;
    final semester = SemesterJson(year: '115', semester: '1');
    final table = CourseTableJson(
      studentId: '11112222',
      studentName: '王大強',
      courseSemester: semester,
    );

    await storage.cacheImportedCourseTable(table);

    expect(storage.getImportedCourseTableCache('11112222', semester), isNotNull);
    expect(storage.getCourseTable('11112222', semester), isNull);

    await storage.init(cookieJar: CookieJar());

    expect(storage.getImportedCourseTableCache('11112222', semester)?.studentName, '王大強');
    expect(storage.getCourseTable('11112222', semester), isNull);
  });

  test('cloud replacement removes missing people and replaces changed share data', () async {
    final storage = LocalStorage.instance;
    storage.setAccount('99990000');
    final first = CourseTableSharePerson(
      studentId: '11112222',
      name: '王大強',
      semesters: <String, List<CourseTableShareCourse>>{
        '115-1': const <CourseTableShareCourse>[
          CourseTableShareCourse(snum: '361024', currCode: '3314123', syllabusCodes: <String>['11126']),
        ],
      },
    );
    final second = CourseTableSharePerson(
      studentId: '22223333',
      name: '李小明',
      semesters: <String, List<CourseTableShareCourse>>{
        '115-1': const <CourseTableShareCourse>[
          CourseTableShareCourse(snum: '361025', currCode: '3314124', syllabusCodes: <String>['11127']),
        ],
      },
    );
    await storage.importCourseTableSharePeople(<CourseTableSharePerson>[first, second]);
    storage.addCourseTable(
      CourseTableJson(
        studentId: second.studentId,
        studentName: second.name,
        courseSemester: SemesterJson(year: '115', semester: '1'),
      ),
    );
    await storage.saveCourseTableList();

    final changedFirst = CourseTableSharePerson(
      studentId: first.studentId,
      name: '王大強（更新）',
      semesters: first.semesters,
    );
    await storage.replaceImportedCourseTableSharePeople(<CourseTableSharePerson>[changedFirst]);

    expect(storage.getImportedCourseTableSharePeople(), hasLength(1));
    expect(storage.getImportedCourseTableSharePerson(first.studentId)?.name, '王大強（更新）');
    expect(storage.getImportedCourseTableSharePerson(second.studentId), isNull);
    expect(storage.getCourseTable(second.studentId, SemesterJson(year: '115', semester: '1')), isNull);
  });

  test('local imported-share mutations persist cloud dirty while remote replacement does not', () async {
    final storage = LocalStorage.instance;
    storage.setAccount('99990000');
    final first = CourseTableSharePerson(
      studentId: '11112222',
      name: '王大強',
      semesters: <String, List<CourseTableShareCourse>>{
        '115-1': const <CourseTableShareCourse>[
          CourseTableShareCourse(snum: '361024', currCode: '3314123', syllabusCodes: <String>['11126']),
        ],
      },
    );

    expect(storage.getCourseTableCloudSyncDirty(), isFalse);
    await storage.importCourseTableSharePeople(<CourseTableSharePerson>[first]);
    expect(storage.getCourseTableCloudSyncDirty(), isTrue);

    await storage.setCourseTableCloudSyncDirty(false);
    final remoteChanged = CourseTableSharePerson(
      studentId: first.studentId,
      name: '王大強（雲端）',
      semesters: first.semesters,
    );
    await storage.replaceImportedCourseTableSharePeople(<CourseTableSharePerson>[remoteChanged]);
    expect(storage.getCourseTableCloudSyncDirty(), isFalse);
    expect(storage.getImportedCourseTableSharePerson(first.studentId)?.name, '王大強（雲端）');

    await storage.deleteImportedCourseTableSharePerson(first.studentId);
    expect(storage.getCourseTableCloudSyncDirty(), isTrue);
  });

  test('background cloud replacement aborts when a local dirty mutation is pending', () async {
    final storage = LocalStorage.instance;
    storage.setAccount('99990000');
    final local = CourseTableSharePerson(
      studentId: '11112222',
      name: '本機版本',
      semesters: <String, List<CourseTableShareCourse>>{
        '115-1': const <CourseTableShareCourse>[
          CourseTableShareCourse(snum: '361024', currCode: '3314123', syllabusCodes: <String>['11126']),
        ],
      },
    );
    final remote = CourseTableSharePerson(
      studentId: local.studentId,
      name: '遠端舊版本',
      semesters: local.semesters,
    );

    await storage.importCourseTableSharePeople(<CourseTableSharePerson>[local]);
    expect(storage.getCourseTableCloudSyncDirty(), isTrue);

    await storage.replaceImportedCourseTableSharePeople(
      <CourseTableSharePerson>[remote],
      abortIfCloudDirty: true,
    );

    expect(storage.getImportedCourseTableSharePerson(local.studentId)?.name, '本機版本');
    expect(storage.getCourseTableCloudSyncDirty(), isTrue);
  });

}
