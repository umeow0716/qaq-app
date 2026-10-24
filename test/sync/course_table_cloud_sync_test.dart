import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/share/course_table_share_data.dart';
import 'package:qaq_app/src/sync/course_table_cloud_sync.dart';

CourseTableSharePerson _person(String studentId, String name, int courseCount) => CourseTableSharePerson(
  studentId: studentId,
  name: name,
  semesters: <String, List<CourseTableShareCourse>>{
    '115-1': List<CourseTableShareCourse>.generate(
      courseCount,
      (index) => CourseTableShareCourse(
        snum: '${361024 + index}',
        currCode: '${3314123 + index}',
        syllabusCodes: <String>['${11126 + index}'],
      ),
    ),
  },
);

void main() {
  test('cloud snapshot chunks stay within nPortal content limit and merge back', () {
    final urls = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[
        _person('22223333', '李小明', 8),
        _person('11112222', '王大強', 8),
      ],
      generation: 'abc123',
    );

    expect(urls, isNotEmpty);
    expect(urls.every((url) => url.length <= CourseTableCloudSync.maxTaskContentLength), isTrue);

    final people = CourseTableCloudSync.decodeSnapshotUrls(urls);
    expect(people.map((person) => person.studentId), <String>['11112222', '22223333']);
    expect(people.first.name, '王大強');
    expect(people.first.semesters['115-1'], hasLength(8));
  });

  test('cloud snapshot can represent an empty imported-person tombstone', () {
    final urls = CourseTableCloudSync.encodeSnapshotUrls(
      const <CourseTableSharePerson>[],
      generation: 'abc124',
    );
    expect(urls, hasLength(1));
    expect(urls.single.length, lessThanOrEqualTo(CourseTableCloudSync.maxTaskContentLength));
    expect(CourseTableCloudSync.decodeSnapshotUrls(urls), isEmpty);
  });

  test('newest complete generation wins while older rollback generations remain', () {
    final older = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('11112222', '舊版本', 4)],
      generation: '100',
      maxLength: 170,
    );
    final newer = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('22223333', '新版本', 4)],
      generation: '200',
      maxLength: 170,
    );

    final people = CourseTableCloudSync.decodeSnapshotUrls(<String>[...older, ...newer]);

    expect(people.map((person) => person.studentId), <String>['22223333']);
    expect(people.single.name, '新版本');
  });

  test('incomplete newer snapshot is ignored in favor of an older complete generation', () {
    final older = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('11112222', '王大強', 8)],
      generation: '100',
      maxLength: 170,
    );
    final newer = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('22223333', '李小明', 8)],
      generation: '200',
      maxLength: 170,
    );
    expect(newer.length, greaterThan(1));

    final people = CourseTableCloudSync.decodeSnapshotUrls(<String>[...older, newer.first]);
    expect(people.map((person) => person.studentId), <String>['11112222']);
  });

  test('malformed or incomplete-only snapshots are rejected for recovery', () {
    expect(
      () => CourseTableCloudSync.decodeSnapshotUrls(<String>['not-a-qaq-share-url']),
      throwsFormatException,
    );

    final incomplete = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('11112222', '王大強', 8)],
      generation: '300',
      maxLength: 170,
    );
    expect(incomplete.length, greaterThan(1));
    expect(
      () => CourseTableCloudSync.decodeSnapshotUrls(<String>[incomplete.first]),
      throwsFormatException,
    );
  });

}
