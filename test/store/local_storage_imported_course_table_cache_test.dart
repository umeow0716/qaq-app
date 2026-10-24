import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
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
}
