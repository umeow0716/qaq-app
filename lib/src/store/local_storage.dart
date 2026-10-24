import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_app_session.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_download_relay.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_proxy.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_routing.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_runtime.dart';
import 'package:qaq_app/src/connector/istudy_reachability_probe.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/connector/network.dart';
import 'package:qaq_app/src/connector/web_view_cookie_store.dart';
import 'package:qaq_app/src/model/course/course_main_extra_json.dart';
import 'package:qaq_app/src/model/course/course_score_json.dart';
import 'package:qaq_app/src/model/coursetable/course_classroom_cache.dart';
import 'package:qaq_app/src/model/coursetable/empty_classroom_cache.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/model/setting/setting_json.dart';
import 'package:qaq_app/src/model/userdata/user_data_json.dart';
import 'package:qaq_app/src/share/course_table_share_data.dart';
import 'package:qaq_app/src/store/user_session_artifacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/course/course_class_json.dart';

class LocalStorage {
  LocalStorage._();

  factory LocalStorage() => _instance;
  static final _instance = LocalStorage._();

  static LocalStorage get instance => _instance;

  static const courseNotice = "CourseNotice";
  static const appCheckUpdate = "AppCheckUpdate";
  static const _ntutPasswordStorageKey = 'ntut_password_v1';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  late final cacheManager = DefaultCacheManager();

  final _userDataJsonKey = "UserDataJsonKey";
  final _courseTableJsonKey = "CourseTableJsonListKey";
  final _importedCourseTableShareKey = "ImportedCourseTableShareKey";
  final _importedCourseTableCacheKey = "ImportedCourseTableCacheKey";
  final _courseTableCloudSyncDirtyKey = "CourseTableCloudSyncDirtyKey";
  final _courseSemesterJsonKey = "CourseSemesterListJson";
  final _scoreCreditJsonKey = "ScoreCreditJsonKey";
  final _courseCategoryCacheKey = "CourseCategoryCacheKey";
  final _courseExtraInfoCacheKey = "CourseExtraInfoCacheKey";
  final _courseClassroomCacheKey = "CourseClassroomResolutionCacheKey";
  final _emptyClassroomCacheKey = "EmptyClassroomCacheKey";
  final _settingJsonKey = "SettingJsonKey";
  final _firstRun = <String, bool>{};
  final _courseTableList = <CourseTableJson>[];
  final _importedCourseTableCacheList = <CourseTableJson>[];
  final _importedCourseTableSharePeople = <CourseTableSharePerson>[];
  Future<void> _importedShareMutationQueue = Future<void>.value();

  CookieJar? _cookieJar;

  SharedPreferences? _pref;
  UserDataJson _userData = UserDataJson();
  List<SemesterJson> _courseSemesterList = <SemesterJson>[];
  CourseScoreCreditJson _courseScoreList = CourseScoreCreditJson();
  final Map<String, CourseExtraInfoJson> _courseExtraInfoCache = {};
  final Map<String, CourseClassroomCacheJson> _courseClassroomCache = {};
  final List<EmptyClassroomCacheJson> _emptyClassroomCaches = <EmptyClassroomCacheJson>[];
  SettingJson _setting = SettingJson();

  SharedPreferences get _preferences {
    final preferences = _pref;
    if (preferences == null) {
      throw StateError('LocalStorage.init() must complete before storage access');
    }
    return preferences;
  }

  bool getFirstUse(String key, {int? timeOut}) {
    if (timeOut != null) {
      final millsTimeOut = timeOut * 1000;
      final wKey = "firstUse$key";
      final now = DateTime.now().millisecondsSinceEpoch;
      final before = _readInt(wKey);

      if (before != null && before > now) {
        return false;
      }

      _writeInt(wKey, now + millsTimeOut);
    }

    return _firstRun.putIfAbsent(key, () => true);
  }

  void setAlreadyUse(String key) => _firstRun[key] = false;

  Future<void> saveUserData() async {
    final password = _userData.password;
    if (password.isEmpty) {
      await _secureStorage.delete(key: _ntutPasswordStorageKey);
    } else {
      await _secureStorage.write(key: _ntutPasswordStorageKey, value: password);
    }

    // UserDataJson.password is excluded from JSON serialization.
    await _save(_userDataJsonKey, _userData);
  }

  Future<void> _loadUserData() async {
    final readJson = _readString(_userDataJsonKey);
    _userData = (readJson != null) ? UserDataJson.fromJson(json.decode(readJson)) : UserDataJson();

    // Migrate the legacy plaintext password from SharedPreferences exactly once.
    // Only rewrite the JSON after secure storage has accepted the credential, so
    // a secure-storage failure never destroys the only remaining copy.
    final legacyPassword = _userData.password;
    final securePassword = await _secureStorage.read(key: _ntutPasswordStorageKey);

    if (securePassword != null && securePassword.isNotEmpty) {
      _userData.password = securePassword;
    } else if (legacyPassword.isNotEmpty) {
      await _secureStorage.write(key: _ntutPasswordStorageKey, value: legacyPassword);
    } else {
      _userData.password = '';
    }

    if (legacyPassword.isNotEmpty) {
      await _save(_userDataJsonKey, _userData);
    }
  }

  void setAccount(String account) => _userData.account = account;

  String getAccount() => _userData.account;

  void setPassword(String password) => _userData.password = password;

  String getPassword() => _userData.password;

  void setUserInfo(UserInfoJson value) => _userData.info = value;

  UserInfoJson getUserInfo() => _userData.info;

  UserDataJson getUserData() => _userData;

  Future<void> saveCourseTableList() => _save(_courseTableJsonKey, _courseTableList);

  Future<void> clearCourseTableList() {
    _courseTableList.clear();
    return saveCourseTableList();
  }

  void _loadCourseTableList() {
    final readJsonList = _readStringList(_courseTableJsonKey);
    _courseTableList.clear();
    if (readJsonList != null) {
      for (final readJson in readJsonList) {
        _courseTableList.add(CourseTableJson.fromJson(json.decode(readJson)));
      }
    }
  }

  String? getCourseNameByCourseId(String courseId) {
    for (final courseDetail in _courseTableList) {
      final name = courseDetail.getCourseNameByCourseId(courseId);
      if (name != null) {
        return name;
      }
    }

    return null;
  }

  void removeCourseTable(CourseTableJson addCourseTable) {
    _courseTableList.removeWhere(
      (courseTable) =>
          courseTable.courseSemester == addCourseTable.courseSemester &&
          courseTable.studentId == addCourseTable.studentId,
    );
  }

  void addCourseTable(CourseTableJson addCourseTable) {
    removeCourseTable(addCourseTable);
    _courseTableList.add(addCourseTable);
  }

  List<CourseTableJson> getCourseTableList() {
    _courseTableList.sort((a, b) {
      if (a.studentId == b.studentId) {
        return b.courseSemester.toString().compareTo(a.courseSemester.toString());
      }
      return a.studentId.compareTo(b.studentId);
    });
    return _courseTableList;
  }

  CourseTableJson? getCourseTable(String studentId, SemesterJson courseSemester) {
    if (studentId.isEmpty) {
      return null;
    }

    return _courseTableList.firstWhereOrNull(
      (courseTable) => courseTable.courseSemester == courseSemester && courseTable.studentId == studentId,
    );
  }

  CourseTableJson? getImportedCourseTableCache(String studentId, SemesterJson courseSemester) {
    final normalized = studentId.trim();
    if (normalized.isEmpty) return null;

    return _importedCourseTableCacheList.firstWhereOrNull(
      (courseTable) => courseTable.courseSemester == courseSemester && courseTable.studentId.trim() == normalized,
    );
  }

  Future<void> cacheImportedCourseTable(CourseTableJson courseTable) {
    final studentId = courseTable.studentId.trim();
    if (studentId.isEmpty) return Future<void>.value();

    _importedCourseTableCacheList.removeWhere(
      (saved) => saved.courseSemester == courseTable.courseSemester && saved.studentId.trim() == studentId,
    );
    _importedCourseTableCacheList.add(courseTable);
    return saveImportedCourseTableCache();
  }

  Future<void> saveImportedCourseTableCache() => _save(_importedCourseTableCacheKey, _importedCourseTableCacheList);

  void _loadImportedCourseTableCache() {
    final readJsonList = _readStringList(_importedCourseTableCacheKey);
    _importedCourseTableCacheList.clear();
    if (readJsonList == null) return;

    for (final readJson in readJsonList) {
      try {
        _importedCourseTableCacheList.add(CourseTableJson.fromJson(json.decode(readJson)));
      } catch (_) {
        // Ignore malformed imported course table cache entries.
      }
    }
  }

  List<CourseTableSharePerson> getImportedCourseTableSharePeople() =>
      List<CourseTableSharePerson>.unmodifiable(_importedCourseTableSharePeople);

  bool getCourseTableCloudSyncDirty() => _preferences.getBool(_courseTableCloudSyncDirtyKey) ?? false;

  Future<void> setCourseTableCloudSyncDirty(bool value) => _preferences.setBool(_courseTableCloudSyncDirtyKey, value);

  CourseTableSharePerson? getImportedCourseTableSharePerson(String studentId) {
    final normalized = studentId.trim();
    return _importedCourseTableSharePeople.firstWhereOrNull((person) => person.studentId == normalized);
  }

  Future<T> _runImportedShareMutation<T>(Future<T> Function() action) async {
    final previous = _importedShareMutationQueue;
    final release = Completer<void>();
    _importedShareMutationQueue = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  Future<void> importCourseTableSharePeople(
    Iterable<CourseTableSharePerson> people, {
    bool markCloudDirty = true,
  }) async {
    final incoming = people.toList(growable: false);
    final expectedAccount = getAccount().trim();
    if (markCloudDirty && expectedAccount.isNotEmpty) {
      // Persist intent before mutating local data. If the process is killed
      // immediately afterwards, next startup still knows local state may need
      // to be published rather than pulling over it.
      await setCourseTableCloudSyncDirty(true);
    }
    await _runImportedShareMutation<void>(() async {
      if (getAccount().trim() != expectedAccount) return;
      await _importCourseTableSharePeopleUnlocked(incoming);
    });
  }

  Future<void> _importCourseTableSharePeopleUnlocked(Iterable<CourseTableSharePerson> people) async {
    for (final person in people) {
      final studentId = person.studentId.trim();
      if (studentId.isEmpty) continue;
      _importedCourseTableSharePeople.removeWhere((saved) => saved.studentId == studentId);
      _importedCourseTableSharePeople.add(person);
      _courseTableList.removeWhere((table) => table.studentId.trim() == studentId);
      _importedCourseTableCacheList.removeWhere((table) => table.studentId.trim() == studentId);
    }
    await Future.wait(<Future<void>>[
      saveImportedCourseTableSharePeople(),
      saveCourseTableList(),
      saveImportedCourseTableCache(),
    ]);
  }

  Future<void> replaceImportedCourseTableSharePeople(
    Iterable<CourseTableSharePerson> people, {
    bool abortIfCloudDirty = false,
  }) async {
    final incomingPeople = people.toList(growable: false);
    final expectedAccount = getAccount().trim();
    await _runImportedShareMutation<void>(() async {
      if (getAccount().trim() != expectedAccount) return;
      // Background pull may have been queued before a user import/delete. The
      // user mutation marks dirty before entering this queue, so re-check here
      // after acquiring the queue and refuse to overwrite newer local intent.
      if (abortIfCloudDirty && getCourseTableCloudSyncDirty()) return;
      await _replaceImportedCourseTableSharePeopleUnlocked(incomingPeople);
    });
  }

  Future<void> _replaceImportedCourseTableSharePeopleUnlocked(Iterable<CourseTableSharePerson> people) async {
    final account = getAccount().trim();
    final incoming = <String, CourseTableSharePerson>{};
    for (final person in people) {
      final studentId = person.studentId.trim();
      if (studentId.isEmpty || studentId == account) continue;
      incoming[studentId] = person;
    }

    final existingIds = _importedCourseTableSharePeople.map((person) => person.studentId.trim()).toSet();
    for (final studentId in existingIds.difference(incoming.keys.toSet())) {
      await _deleteImportedCourseTableSharePersonUnlocked(studentId);
    }

    final changedIds = <String>{};
    for (final entry in incoming.entries) {
      final saved = getImportedCourseTableSharePerson(entry.key);
      if (saved != null && json.encode(saved.toJson()) == json.encode(entry.value.toJson())) continue;
      changedIds.add(entry.key);
      await _importCourseTableSharePeopleUnlocked(<CourseTableSharePerson>[entry.value]);
    }

    final currentStudentId = _setting.course.info.studentId.trim();
    if (changedIds.contains(currentStudentId)) {
      _setting.course = CourseSettingJson();
      _courseSemesterList.clear();
      await Future.wait(<Future<void>>[saveCourseSetting(), _remove(_courseSemesterJsonKey)]);
    }
  }

  Future<bool> deleteImportedCourseTableSharePerson(String studentId, {bool markCloudDirty = true}) async {
    final normalized = studentId.trim();
    if (normalized.isEmpty || normalized == getAccount().trim()) return false;

    final expectedAccount = getAccount().trim();
    if (markCloudDirty && expectedAccount.isNotEmpty) {
      await setCourseTableCloudSyncDirty(true);
    }
    return _runImportedShareMutation<bool>(() async {
      if (getAccount().trim() != expectedAccount) return false;
      return _deleteImportedCourseTableSharePersonUnlocked(normalized);
    });
  }

  Future<bool> _deleteImportedCourseTableSharePersonUnlocked(String normalized) async {
    final deletedCourseIds = <String>{};
    final imported = getImportedCourseTableSharePerson(normalized);
    if (imported != null) {
      for (final courses in imported.semesters.values) {
        for (final course in courses) {
          final courseId = course.snum.trim();
          if (courseId.isNotEmpty) deletedCourseIds.add(courseId);
        }
      }
    }

    for (final table in _courseTableList.where((table) => table.studentId.trim() == normalized)) {
      deletedCourseIds.addAll(table.getCourseIdList().map((id) => id.trim()).where((id) => id.isNotEmpty));
    }
    for (final table in _importedCourseTableCacheList.where((table) => table.studentId.trim() == normalized)) {
      deletedCourseIds.addAll(table.getCourseIdList().map((id) => id.trim()).where((id) => id.isNotEmpty));
    }

    final currentCourseTable = _setting.course.info;
    final wasCurrent = currentCourseTable.studentId.trim() == normalized;
    if (wasCurrent) {
      deletedCourseIds.addAll(currentCourseTable.getCourseIdList().map((id) => id.trim()).where((id) => id.isNotEmpty));
    }

    _importedCourseTableSharePeople.removeWhere((person) => person.studentId.trim() == normalized);
    _courseTableList.removeWhere((table) => table.studentId.trim() == normalized);
    _importedCourseTableCacheList.removeWhere((table) => table.studentId.trim() == normalized);

    if (wasCurrent) {
      _setting.course = CourseSettingJson();
      _courseSemesterList.clear();
    }

    final remainingCourseIds = _referencedCourseIds();
    final orphanedCourseIds = deletedCourseIds.difference(remainingCourseIds);
    if (orphanedCourseIds.isNotEmpty) {
      _courseExtraInfoCache.removeWhere((courseId, _) => orphanedCourseIds.contains(courseId.trim()));
      _courseClassroomCache.removeWhere((_, cache) => orphanedCourseIds.contains(cache.courseId.trim()));
    }

    final writes = <Future<void>>[
      saveImportedCourseTableSharePeople(),
      saveCourseTableList(),
      saveImportedCourseTableCache(),
      saveCourseExtraInfoCache(),
      saveCourseClassroomCache(),
    ];
    if (wasCurrent) {
      writes.add(saveCourseSetting());
      writes.add(_remove(_courseSemesterJsonKey));
    }
    await Future.wait(writes);
    return wasCurrent;
  }

  Set<String> _referencedCourseIds() {
    final courseIds = <String>{};

    for (final person in _importedCourseTableSharePeople) {
      for (final courses in person.semesters.values) {
        for (final course in courses) {
          final courseId = course.snum.trim();
          if (courseId.isNotEmpty) courseIds.add(courseId);
        }
      }
    }

    for (final table in _courseTableList) {
      courseIds.addAll(table.getCourseIdList().map((id) => id.trim()).where((id) => id.isNotEmpty));
    }
    for (final table in _importedCourseTableCacheList) {
      courseIds.addAll(table.getCourseIdList().map((id) => id.trim()).where((id) => id.isNotEmpty));
    }

    final currentCourseTable = _setting.course.info;
    if (!currentCourseTable.isEmpty) {
      courseIds.addAll(currentCourseTable.getCourseIdList().map((id) => id.trim()).where((id) => id.isNotEmpty));
    }

    return courseIds;
  }

  Future<void> saveImportedCourseTableSharePeople() => _writeStringList(
    _importedCourseTableShareKey,
    _importedCourseTableSharePeople.map((person) => json.encode(person.toJson())).toList(),
  );

  void _loadImportedCourseTableSharePeople() {
    _importedCourseTableSharePeople.clear();
    final saved = _readStringList(_importedCourseTableShareKey);
    if (saved == null) return;
    for (final value in saved) {
      try {
        final decoded = json.decode(value);
        if (decoded is Map<String, dynamic>) {
          final person = CourseTableSharePerson.fromJson(decoded);
          if (person.studentId.isNotEmpty && person.semesters.isNotEmpty) {
            _importedCourseTableSharePeople.add(person);
          }
        }
      } catch (_) {
        // Ignore malformed imported share records.
      }
    }
  }

  Future<void> _saveSetting() => _save(_settingJsonKey, _setting);

  void _loadSetting() {
    final readJson = _readString(_settingJsonKey);
    _setting = (readJson != null) ? SettingJson.fromJson(json.decode(readJson)) : SettingJson();
  }

  Future<void> saveCourseScoreCredit() => _save(_scoreCreditJsonKey, _courseScoreList);

  List<SemesterCourseScoreJson> getSemesterCourseScore() => _courseScoreList.semesterCourseScoreList;

  GraduationInformationJson getGraduationInformation() => _courseScoreList.graduationInformation;

  CourseScoreCreditJson getCourseScoreCredit() => _courseScoreList;

  Future<void> setCourseScoreCredit(CourseScoreCreditJson value) {
    _courseScoreList = value;
    return saveCourseScoreCredit();
  }

  Future<void> setSemesterCourseScore(List<SemesterCourseScoreJson> value) {
    _courseScoreList.graduationInformation = GraduationInformationJson();
    _courseScoreList.semesterCourseScoreList = value;
    return saveCourseScoreCredit();
  }

  void _loadCourseScoreCredit() {
    final readJson = _readString(_scoreCreditJsonKey);
    _courseScoreList = (readJson != null)
        ? CourseScoreCreditJson.fromJson(json.decode(readJson))
        : CourseScoreCreditJson();
  }

  bool _loadCourseExtraInfoCache() {
    _courseExtraInfoCache.clear();
    bool changed = false;

    final readJson = _readString(_courseExtraInfoCacheKey);
    if (readJson != null) {
      final decoded = json.decode(readJson);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is! Map) continue;

          try {
            final extra = CourseExtraInfoJson.fromJson(Map<String, dynamic>.from(value));
            if (!extra.isEmpty) {
              _courseExtraInfoCache[entry.key] = extra;
            }
          } catch (_) {
            // Ignore malformed legacy cache entries.
          }
        }
      }
    }

    // Saved course tables already contain most course metadata. Merge them into
    // the single ExtraInfo cache so Score and Course Detail can reuse it.
    for (final courseTable in _courseTableList) {
      for (final dayMap in courseTable.courseInfoMap.values) {
        for (final courseInfo in dayMap.values) {
          final main = courseInfo.main;
          final courseId = main.course.id;
          if (courseId.isEmpty) continue;

          changed |= _mergeCourseExtraInfoCache(
            courseId,
            CourseExtraInfoJson(
              courseSemester: courseTable.courseSemester,
              course: CourseExtraJson(
                id: courseId,
                name: main.course.name,
                href: main.course.scheduleHref,
                openClass: main.getOpenClassName(),
              ),
            ),
          );

          if (!courseInfo.extra.isEmpty) {
            changed |= _mergeCourseExtraInfoCache(courseId, courseInfo.extra);
          }
        }
      }
    }

    // Migrate the old dedicated category cache into ExtraInfo. The legacy key
    // is deleted after the merged ExtraInfo cache is persisted in init().
    final legacyCategoryJson = _readString(_courseCategoryCacheKey);
    if (legacyCategoryJson != null) {
      final decoded = json.decode(legacyCategoryJson);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is! Map) continue;

          final category = value['category'];
          final openClass = value['openClass'];
          if (category is! String || category.isEmpty) continue;

          changed |= _mergeCourseExtraInfoCache(
            entry.key,
            CourseExtraInfoJson(
              course: CourseExtraJson(
                id: entry.key,
                category: category,
                openClass: openClass is String ? openClass : '',
              ),
            ),
          );
        }
      }
    }

    // Older score cache entries may already have category/open-class metadata.
    // Merge them into ExtraInfo, then hydrate score rows from that same cache.
    for (final semesterScore in _courseScoreList.semesterCourseScoreList) {
      for (final courseInfo in semesterScore.courseScoreList) {
        final courseId = courseInfo.courseId;
        if (courseId.isEmpty) continue;

        if (courseInfo.category.isNotEmpty || courseInfo.openClass.isNotEmpty) {
          changed |= _mergeCourseExtraInfoCache(
            courseId,
            CourseExtraInfoJson(
              courseSemester: semesterScore.semester,
              course: CourseExtraJson(
                id: courseId,
                name: courseInfo.nameZh.isNotEmpty ? courseInfo.nameZh : courseInfo.nameEn,
                category: courseInfo.category,
                openClass: courseInfo.openClass,
              ),
            ),
          );
        }

        final cached = _courseExtraInfoCache[courseId];
        if (cached == null) continue;

        if (courseInfo.category.isEmpty && cached.course.category.isNotEmpty) {
          courseInfo.category = cached.course.category;
        }
        if (courseInfo.openClass.isEmpty && cached.course.openClass.isNotEmpty) {
          courseInfo.openClass = cached.course.openClass;
        }
      }
    }

    return changed;
  }

  CourseExtraInfoJson? getCourseExtraInfoCache(String courseId) {
    if (courseId.isEmpty) return null;
    return _courseExtraInfoCache[courseId];
  }

  bool hasCompleteCourseExtraInfoCache(String courseId) {
    final cached = getCourseExtraInfoCache(courseId);
    return cached != null &&
        cached.course.category.isNotEmpty &&
        !cached.courseSemester.isEmpty &&
        _isAuthoritativeCourseCount(cached.course.selectNumber) &&
        _isAuthoritativeCourseCount(cached.course.withdrawNumber);
  }

  bool _isAuthoritativeCourseCount(String value) => int.tryParse(value.trim()) != null;

  void setCourseExtraInfoCache(String courseId, CourseExtraInfoJson value) {
    _mergeCourseExtraInfoCache(courseId, value);
  }

  bool _mergeCourseExtraInfoCache(String courseId, CourseExtraInfoJson value) {
    if (courseId.isEmpty || value.isEmpty) return false;

    // Always merge through one controlled path, even for a brand-new cache
    // entry. This prevents non-authoritative producers (iStudy, course table,
    // score metadata) from seeding enrollment counts by accident.
    final existing = _courseExtraInfoCache[courseId];
    final cached = existing ?? CourseExtraInfoJson(course: CourseExtraJson(id: courseId));
    final before = json.encode(cached.toJson());

    if (!value.courseSemester.isEmpty) {
      cached.courseSemester = value.courseSemester;
    }

    final target = cached.course;
    final source = value.course;
    if (source.id.isNotEmpty) target.id = source.id;
    if (target.id.isEmpty) target.id = courseId;
    if (source.name.isNotEmpty) target.name = source.name;
    if (source.href.isNotEmpty) target.href = source.href;
    if (source.category.isNotEmpty) target.category = source.category;
    if (source.openClass.isNotEmpty) target.openClass = source.openClass;

    // Enrollment/withdrawal counts are authoritative only when the producer
    // explicitly marks the payload as a fresh CourseExtra/ShowSyllabus
    // snapshot. iStudy classmate lists never carry this timestamp, so their
    // length (or any accidental count fields) can never overwrite these
    // numbers.
    final hasAuthoritativeCounts =
        value.courseExtraUpdatedAt != null &&
        _isAuthoritativeCourseCount(source.selectNumber) &&
        _isAuthoritativeCourseCount(source.withdrawNumber);
    if (hasAuthoritativeCounts) {
      target.selectNumber = source.selectNumber.trim();
      target.withdrawNumber = source.withdrawNumber.trim();
      cached.courseExtraUpdatedAt = value.courseExtraUpdatedAt;
    }

    if (value.classmateUpdatedAt != null) {
      // A timestamp marks the classmate list as an authoritative iStudy
      // snapshot. This also lets an empty class list be cached correctly.
      cached.classmate = value.classmate;
      cached.classmateUpdatedAt = value.classmateUpdatedAt;
    } else if (value.classmate.isNotEmpty) {
      // Preserve compatibility with older ExtraInfo producers that may still
      // provide classmates without freshness metadata.
      cached.classmate = value.classmate;
    }

    final changed = before != json.encode(cached.toJson());
    if (changed && existing == null) {
      _courseExtraInfoCache[courseId] = cached;
    }
    return changed;
  }

  Future<void> saveCourseExtraInfoCache() {
    final encoded = _courseExtraInfoCache.map((key, value) => MapEntry(key, value.toJson()));
    return _writeString(_courseExtraInfoCacheKey, json.encode(encoded));
  }

  void _loadCourseClassroomCache() {
    _courseClassroomCache.clear();
    final readJson = _readString(_courseClassroomCacheKey);
    if (readJson == null) return;

    try {
      final decoded = json.decode(readJson);
      if (decoded is! Map<String, dynamic>) return;

      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        try {
          final cache = CourseClassroomCacheJson.fromJson(Map<String, dynamic>.from(value));
          if (cache.courseId.isNotEmpty && cache.year.isNotEmpty && cache.semester.isNotEmpty) {
            _courseClassroomCache[entry.key] = cache;
          }
        } catch (_) {
          // Ignore malformed classroom-resolution cache entries.
        }
      }
    } catch (_) {
      // Ignore a malformed top-level cache payload.
    }
  }

  CourseClassroomCacheJson? getCourseClassroomCache(SemesterJson semester, String courseId) {
    if (semester.isEmpty || courseId.isEmpty) return null;
    return _courseClassroomCache[CourseClassroomCacheJson.cacheKey(semester, courseId)];
  }

  bool shouldRefreshCourseClassroomCache(SemesterJson semester, CourseMainInfoJson main, {required Duration maxAge}) {
    if (main.course.id.isEmpty || main.classroom.length < 2) return false;

    final cached = getCourseClassroomCache(semester, main.course.id);
    if (cached == null) return true;
    if (cached.schemaVersion != CourseClassroomCacheJson.currentSchemaVersion) return true;
    if (cached.candidateSignature != CourseClassroomCacheJson.classroomSignature(main)) return true;
    return DateTime.now().difference(cached.updatedAt) > maxAge;
  }

  String? getResolvedCourseClassroom(SemesterJson semester, CourseMainInfoJson main, Day day, SectionNumber section) {
    if (main.course.id.isEmpty || main.classroom.length < 2) return null;

    final cached = getCourseClassroomCache(semester, main.course.id);
    if (cached == null) return null;
    if (cached.schemaVersion != CourseClassroomCacheJson.currentSchemaVersion) return null;
    if (cached.candidateSignature != CourseClassroomCacheJson.classroomSignature(main)) return null;

    final classroom = cached.getClassroom(day, section);
    if (classroom == null || classroom.isEmpty) return null;
    final stillCandidate = main.classroom.any((candidate) => candidate.name == classroom);
    return stillCandidate ? classroom : null;
  }

  void setCourseClassroomCache(SemesterJson semester, String courseId, CourseClassroomCacheJson value) {
    if (semester.isEmpty || courseId.isEmpty) return;
    _courseClassroomCache[CourseClassroomCacheJson.cacheKey(semester, courseId)] = value;
  }

  Future<void> saveCourseClassroomCache() {
    final encoded = _courseClassroomCache.map((key, value) => MapEntry(key, value.toJson()));
    return _writeString(_courseClassroomCacheKey, json.encode(encoded));
  }

  void _loadEmptyClassroomCache() {
    _emptyClassroomCaches.clear();
    final readJson = _readString(_emptyClassroomCacheKey);
    if (readJson == null) return;
    try {
      final decoded = json.decode(readJson);
      final values = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
          ? <Object?>[decoded]
          : const <Object?>[];
      for (final value in values) {
        if (value is! Map) continue;
        try {
          final cache = EmptyClassroomCacheJson.fromJson(Map<String, dynamic>.from(value));
          if (cache.year.isEmpty || cache.semester.isEmpty || cache.language.isEmpty) continue;
          _emptyClassroomCaches.add(cache);
        } catch (_) {
          // Ignore malformed entries; they are ordinary cache misses.
        }
      }
    } catch (_) {
      // A malformed top-level payload is a cache miss and can be rebuilt.
    }
  }

  List<EmptyClassroomCacheJson> getEmptyClassroomCaches() =>
      List<EmptyClassroomCacheJson>.unmodifiable(_emptyClassroomCaches);

  EmptyClassroomCacheJson? getEmptyClassroomCache(SemesterJson semester, String language) {
    return _emptyClassroomCaches.firstWhereOrNull((cache) => cache.matches(semester, language));
  }

  Future<void> setEmptyClassroomCache(EmptyClassroomCacheJson cache) {
    _emptyClassroomCaches.removeWhere(
      (saved) => saved.year == cache.year && saved.semester == cache.semester && saved.language == cache.language,
    );
    _emptyClassroomCaches.add(cache);
    return saveEmptyClassroomCache();
  }

  Future<void> retainEmptyClassroomCaches({required Iterable<SemesterJson> semesters, required String language}) {
    final allowed = EmptyClassroomSemesterPolicy.newestTwo(semesters);
    final allowedKeys = allowed.map((semester) => '${semester.year}-${semester.semester}').toSet();
    final newestBySemester = <String, EmptyClassroomCacheJson>{};
    for (final cache in _emptyClassroomCaches) {
      final key = '${cache.year}-${cache.semester}';
      if (cache.schemaVersion != EmptyClassroomCacheJson.currentSchemaVersion ||
          cache.language != language ||
          !allowedKeys.contains(key)) {
        continue;
      }
      final previous = newestBySemester[key];
      if (previous == null || cache.updatedAt.isAfter(previous.updatedAt)) {
        newestBySemester[key] = cache;
      }
    }
    _emptyClassroomCaches
      ..clear()
      ..addAll(
        allowed
            .map((semester) => newestBySemester['${semester.year}-${semester.semester}'])
            .whereType<EmptyClassroomCacheJson>(),
      );
    return saveEmptyClassroomCache();
  }

  Future<void> saveEmptyClassroomCache() {
    if (_emptyClassroomCaches.isEmpty) return _remove(_emptyClassroomCacheKey);
    return _writeString(
      _emptyClassroomCacheKey,
      json.encode(_emptyClassroomCaches.map((cache) => cache.toJson()).toList(growable: false)),
    );
  }

  Future<void> clearEmptyClassroomCache({SemesterJson? semester, String? language}) {
    if (semester == null && language == null) {
      _emptyClassroomCaches.clear();
    } else {
      _emptyClassroomCaches.removeWhere(
        (cache) =>
            (semester == null || (cache.year == semester.year && cache.semester == semester.semester)) &&
            (language == null || cache.language == language),
      );
    }
    return saveEmptyClassroomCache();
  }

  Future<void> saveCourseSetting() => _saveSetting();

  Future<void> clearCourseSetting() {
    _setting.course = CourseSettingJson();
    return saveCourseSetting();
  }

  CourseSettingJson getCourseSetting() => _setting.course;

  Future<void> saveOtherSetting() => _saveSetting();

  void setOtherSetting(OtherSettingJson value) => _setting.other = value;

  OtherSettingJson getOtherSetting() => _setting.other;

  void clearSemesterJsonList() => _courseSemesterList.clear();

  void _loadSemesterJsonList() {
    final readJsonList = _readStringList(_courseSemesterJsonKey);
    _courseSemesterList.clear();

    if (readJsonList != null) {
      for (final readJson in readJsonList) {
        _courseSemesterList.add(SemesterJson.fromJson(json.decode(readJson)));
      }
    }
  }

  void setSemesterJsonList(List<SemesterJson> value) => _courseSemesterList = value;

  SemesterJson? getSemesterJsonItem(int index) =>
      _courseSemesterList.length > index ? _courseSemesterList[index] : null;

  List<SemesterJson> getSemesterList() => _courseSemesterList;

  Future<void> init({CookieJar? cookieJar}) async {
    _pref = await SharedPreferences.getInstance();

    if (cookieJar != null) {
      _cookieJar = cookieJar;
    }

    GlobalProtectAppSession.instance.configureCredentials(account: getAccount, password: getPassword);
    configureNetwork(
      cookies: _cookieJar ??= CookieJar(),
      resolveStudyRoute: () async {
        final route = await IStudyAccessGuard.route();
        if (route == IStudyAccessRoute.blocked) {
          throw IStudyAccessBlockedException(IStudyAccessGuard.blockedMessage);
        }
        return route;
      },
      tunnelAdapter: () => GlobalProtectAppSession.instance.ensureDioAdapter(
        proxyPort: () =>
            GlobalProtectProxyBridge.instance.ensureStarted(vpnHosts: GlobalProtectRouting.webViewProxyHosts),
      ),
    );
    await _loadUserData();
    _loadCourseTableList();
    _loadImportedCourseTableCache();
    _loadImportedCourseTableSharePeople();
    _loadSetting();
    _loadCourseScoreCredit();
    final courseExtraInfoCacheChanged = _loadCourseExtraInfoCache();
    _loadCourseClassroomCache();
    _loadEmptyClassroomCache();
    if (courseExtraInfoCacheChanged) {
      await saveCourseExtraInfoCache();
    }
    // CourseCategoryCacheKey is a legacy cache. ExtraInfo is now the single
    // source of truth for course metadata.
    await _remove(_courseCategoryCacheKey);
    _loadSemesterJsonList();
  }

  Future<void> logout() async {
    // Clear in-memory identity/data first so new requests cannot start using the
    // account while the asynchronous logout cleanup is still running.
    _resetUserScopedMemory();

    Future<void> cleanup(String name, Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        debugPrint('logout cleanup failed [$name]: $error\n$stackTrace');
      }
    }

    // Runtime/session cleanup is best-effort and intentionally exhaustive: one
    // failed subsystem must not prevent the remaining user state from clearing.
    await cleanup('webview-download-relay', GlobalProtectDownloadRelay.instance.close);
    await cleanup('webview-vpn-runtime', GlobalProtectWebViewRuntime.reset);
    await cleanup('global-protect-session', GlobalProtectAppSession.instance.disconnectAndClearCachedSession);
    await cleanup('dio-cookies', cookieJar.deleteAll);
    await cleanup('webview-cookies', WebViewCookieStore.clearAll);
    await cleanup('network-image-cache', cacheManager.emptyCache);
    await cleanup('generated-user-artifacts', UserSessionArtifacts.clear);

    IStudyReachabilityProbe.clearCache();
    await _clearUserScopedCaches();
    await init();
  }

  void _resetUserScopedMemory() {
    _userData = UserDataJson();
    _courseTableList.clear();
    _importedCourseTableCacheList.clear();
    _importedCourseTableSharePeople.clear();
    _courseSemesterList.clear();
    _courseScoreList = CourseScoreCreditJson();
    _courseExtraInfoCache.clear();
    _courseClassroomCache.clear();
    _emptyClassroomCaches.clear();
    _setting.course = CourseSettingJson();
    _firstRun.clear();
  }

  Future<void> _clearUserScopedCaches() async {
    _resetUserScopedMemory();

    await Future.wait<void>([
      _secureStorage.delete(key: _ntutPasswordStorageKey),
      _remove(_userDataJsonKey),
      _remove(_courseTableJsonKey),
      _remove(_importedCourseTableCacheKey),
      _remove(_importedCourseTableShareKey),
      _remove(_courseTableCloudSyncDirtyKey),
      _remove(_courseSemesterJsonKey),
      _remove(_scoreCreditJsonKey),
      _remove(_courseCategoryCacheKey),
      _remove(_courseExtraInfoCacheKey),
      _remove(_courseClassroomCacheKey),
      _remove(_emptyClassroomCacheKey),
      _remove('firstUse$courseNotice'),
      // Keep global/user-choice settings (theme, file path, sort, and
      // SettingJson.other), but persist the cleared course/announcement state.
      _saveSetting(),
    ]);
  }

  Future<void> _save(String key, dynamic saveObj) async {
    try {
      await _saveJsonList(key, saveObj);
    } catch (e) {
      await _saveJson(key, saveObj);
    }
  }

  Future<void> _saveJson(String key, dynamic saveObj) => _writeString(key, json.encode(saveObj));

  Future<void> _saveJsonList(String key, dynamic saveObj) async {
    final jsonList = <String>[];

    for (dynamic obj in saveObj) {
      jsonList.add(json.encode(obj));
    }

    await _writeStringList(key, jsonList);
  }

  Future<void> _writeString(String key, String value) => _preferences.setString(key, value);

  Future<void> _remove(String key) => _preferences.remove(key);

  Future<void> _writeInt(String key, int value) => _preferences.setInt(key, value);

  int? _readInt(String key) => _preferences.getInt(key);

  Future<void> _writeStringList(String key, List<String> value) => _preferences.setStringList(key, value);

  String? _readString(String key) => _preferences.getString(key);

  List<String>? _readStringList(String key) => _preferences.getStringList(key);
}
