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
    final urls = CourseTableCloudSync.encodeSnapshotUrls(<CourseTableSharePerson>[
      _person('22223333', '李小明', 8),
      _person('11112222', '王大強', 8),
    ], generation: 'abc123');

    expect(urls, isNotEmpty);
    expect(urls.every((url) => url.length <= CourseTableCloudSync.maxTaskContentLength), isTrue);

    final people = CourseTableCloudSync.decodeSnapshotUrls(urls);
    expect(people.map((person) => person.studentId), <String>['11112222', '22223333']);
    expect(people.first.name, '王大強');
    expect(people.first.semesters['115-1'], hasLength(8));
  });

  test('cloud snapshot can represent an empty imported-person tombstone', () {
    final urls = CourseTableCloudSync.encodeSnapshotUrls(const <CourseTableSharePerson>[], generation: 'abc124');
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
    expect(() => CourseTableCloudSync.decodeSnapshotUrls(<String>['not-a-qaq-share-url']), throwsFormatException);

    final incomplete = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('11112222', '王大強', 8)],
      generation: '300',
      maxLength: 170,
    );
    expect(incomplete.length, greaterThan(1));
    expect(() => CourseTableCloudSync.decodeSnapshotUrls(<String>[incomplete.first]), throwsFormatException);
  });

  test('first sync merges unrelated local imports without deleting cloud people', () {
    final result = CourseTableCloudSync.mergeSnapshots(
      base: null,
      local: <CourseTableSharePerson>[_person('22223333', '本機新增', 2)],
      remote: <CourseTableSharePerson>[_person('11112222', '雲端既有', 2)],
    );
    expect(result?.map((person) => person.studentId), <String>['11112222', '22223333']);
  });

  test('unknown base never treats an absent local person as a deletion', () {
    final result = CourseTableCloudSync.mergeSnapshots(
      base: null, local: const <CourseTableSharePerson>[],
      remote: <CourseTableSharePerson>[_person('11112222', '雲端', 1)],
    );
    expect(result?.single.studentId, '11112222');
  });

  test('a confirmed local delete removes only its original baseline person', () {
    final deleted = _person('11112222', '刪除', 1);
    final added = _person('22223333', '別台新增', 1);
    final result = CourseTableCloudSync.mergeSnapshots(
      base: <CourseTableSharePerson>[deleted], local: const <CourseTableSharePerson>[],
      remote: <CourseTableSharePerson>[deleted, added],
    );
    expect(result?.map((person) => person.studentId), <String>['22223333']);
  });

  test('concurrent edits to same person are blocked instead of last-write-wins', () {
    final before = _person('11112222', '舊', 1);
    final local = _person('11112222', '本地', 1);
    final remote = _person('11112222', '雲端', 1);
    expect(
      CourseTableCloudSync.mergeSnapshots(
        base: <CourseTableSharePerson>[before],
        local: <CourseTableSharePerson>[local], remote: <CourseTableSharePerson>[remote],
      ),
      isNull,
    );
    expect(
      CourseTableCloudSync.mergeSnapshots(
        base: null, local: <CourseTableSharePerson>[local], remote: <CourseTableSharePerson>[remote],
      ),
      isNull,
    );
  });

  test('one-sided edits survive while unmodified remote records are preserved', () {
    final before = _person('11112222', '舊', 1);
    final result = CourseTableCloudSync.mergeSnapshots(
      base: <CourseTableSharePerson>[before],
      local: <CourseTableSharePerson>[_person('11112222', '本地新', 1)],
      remote: <CourseTableSharePerson>[before, _person('22223333', '遠端新增', 1)],
    );
    expect(result?.map((person) => person.name), <String>['本地新', '遠端新增']);
  });

  test('conflicting duplicate fragments do not become a successful snapshot', () {
    final first = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('11112222', '第一版', 1)], generation: '100',
    ).single;
    final second = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('11112222', '衝突版', 1)], generation: '100',
    ).single;
    expect(() => CourseTableCloudSync.decodeSnapshotUrls([first, second]), throwsFormatException);
  });

  test('corrupt newer complete generation falls back to valid older generation', () {
    final old = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('11112222', '保留版', 1)], generation: '100',
    );
    final corrupt = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('22223333', '損壞版', 1)], generation: '200',
    ).single.replaceFirst('data=', 'data=broken');
    final decoded = CourseTableCloudSync.decodeSnapshotUrls([...old, corrupt]);
    expect(decoded.single.name, '保留版');
  });


  test('legacy device does not silently replace unverified local people', () {
    final local = <CourseTableSharePerson>[_person('11112222', '未同步', 1)];
    expect(CourseTableCloudSync.canPullRemoteWithoutDiscardingLocal(
      base: null, local: local, remote: const <CourseTableSharePerson>[],
    ), isFalse);
    expect(CourseTableCloudSync.canPullRemoteWithoutDiscardingLocal(
      base: null, local: local, remote: local,
    ), isTrue);
    expect(CourseTableCloudSync.canPullRemoteWithoutDiscardingLocal(
      base: const <CourseTableSharePerson>[], local: local, remote: const <CourseTableSharePerson>[],
    ), isFalse);
    expect(CourseTableCloudSync.canPullRemoteWithoutDiscardingLocal(
      base: local, local: local, remote: const <CourseTableSharePerson>[],
    ), isTrue);
  });


  test('legacy fragmentless snapshot remains readable during migration', () {
    final old = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('11112222', '舊格式', 1)], generation: '100',
    ).single;
    final legacy = Uri.parse(old).replace(fragment: '').toString();
    final incomplete = CourseTableCloudSync.encodeSnapshotUrls(
      <CourseTableSharePerson>[_person('22223333', '未完成', 8)],
      generation: '200', maxLength: 170,
    );
    expect(incomplete, hasLength(greaterThan(1)));
    final people = CourseTableCloudSync.decodeSnapshotUrls(<String>[legacy, incomplete.first]);
    expect(people.single.name, '舊格式');
  });

}
