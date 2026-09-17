import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_app/src/connector/campus_network_detector.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_app_session.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_webview_runtime.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course/course_score_json.dart';
import 'package:flutter_app/src/model/coursetable/course_table_json.dart';
import 'package:flutter_app/src/model/setting/setting_json.dart';
import 'package:flutter_app/src/model/userdata/user_data_json.dart';
import 'package:flutter_app/src/store/user_session_artifacts.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/course/course_class_json.dart';

class LocalStorage {
  LocalStorage._();

  factory LocalStorage() => _instance;
  static final _instance = LocalStorage._();

  static LocalStorage get instance => _instance;

  static const courseNotice = "CourseNotice";
  static const appCheckUpdate = "AppCheckUpdate";

  final cacheManager = DefaultCacheManager();

  final _userDataJsonKey = "UserDataJsonKey";
  final _courseTableJsonKey = "CourseTableJsonListKey";
  final _courseSemesterJsonKey = "CourseSemesterListJson";
  final _scoreCreditJsonKey = "ScoreCreditJsonKey";
  final _courseCategoryCacheKey = "CourseCategoryCacheKey";
  final _courseExtraInfoCacheKey = "CourseExtraInfoCacheKey";
  final _settingJsonKey = "SettingJsonKey";
  final _firstRun = <String, bool>{};
  final _courseTableList = <CourseTableJson>[];

  final _httpClientInterceptors = <Interceptor>[];
  CookieJar? _cookieJar;

  SharedPreferences? _pref;
  UserDataJson _userData = UserDataJson();
  List<SemesterJson> _courseSemesterList = <SemesterJson>[];
  CourseScoreCreditJson _courseScoreList = CourseScoreCreditJson();
  final Map<String, CourseExtraInfoJson> _courseExtraInfoCache = {};
  SettingJson _setting = SettingJson();

  SharedPreferences get _preferences {
    final preferences = _pref;
    if (preferences == null) {
      throw StateError('LocalStorage.init() must complete before storage access');
    }
    return preferences;
  }

  bool get autoCheckAppUpdate => _setting.other.autoCheckAppUpdate;

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

  void _setFirstUse(String key, bool value) => _firstRun[key] = value;

  Future<void> saveUserData() => _save(_userDataJsonKey, _userData);

  Future<void> clearUserData() {
    _userData = UserDataJson();
    return saveUserData();
  }

  void _loadUserData() {
    final readJson = _readString(_userDataJsonKey);
    _userData = (readJson != null) ? UserDataJson.fromJson(json.decode(readJson)) : UserDataJson();
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

  Future<void> _saveSetting() => _save(_settingJsonKey, _setting);

  void _loadSetting() {
    final readJson = _readString(_settingJsonKey);
    _setting = (readJson != null) ? SettingJson.fromJson(json.decode(readJson)) : SettingJson();
  }

  Future<void> saveCourseScoreCredit() => _save(_scoreCreditJsonKey, _courseScoreList);

  List<SemesterCourseScoreJson> getSemesterCourseScore() => _courseScoreList.semesterCourseScoreList;

  GraduationInformationJson getGraduationInformation() => _courseScoreList.graduationInformation;

  CourseScoreCreditJson getCourseScoreCredit() => _courseScoreList;

  Future<void> _clearCourseScoreCredit() {
    _courseScoreList = CourseScoreCreditJson();
    return saveCourseScoreCredit();
  }

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

  Future<void> saveCourseSetting() => _saveSetting();

  Future<void> clearCourseSetting() {
    _setting.course = CourseSettingJson();
    return saveCourseSetting();
  }

  CourseSettingJson getCourseSetting() => _setting.course;

  Future<void> saveOtherSetting() => _saveSetting();

  void setOtherSetting(OtherSettingJson value) => _setting.other = value;

  OtherSettingJson getOtherSetting() => _setting.other;

  Future<void> _saveAnnouncementSetting() => _saveSetting();

  Future<void> _clearAnnouncementSetting() {
    _setting.announcement = AnnouncementSettingJson();
    return _saveAnnouncementSetting();
  }

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

  String? getVersion() => _readString("version");

  Future<void> setVersion(String version) => _writeString("version", version);

  Future<void> init({List<Interceptor> httpClientInterceptors = const [], CookieJar? cookieJar}) async {
    _pref = await SharedPreferences.getInstance();

    if (httpClientInterceptors.isNotEmpty) {
      _httpClientInterceptors
        ..clear()
        ..addAll(httpClientInterceptors);
    }
    if (cookieJar != null) {
      _cookieJar = cookieJar;
    }

    await DioConnector.instance.init(interceptors: _httpClientInterceptors, cookieJar: _cookieJar);
    _loadUserData();
    _loadCourseTableList();
    _loadSetting();
    _loadCourseScoreCredit();
    final courseExtraInfoCacheChanged = _loadCourseExtraInfoCache();
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
    await cleanup('webview-vpn-runtime', GlobalProtectWebViewRuntime.reset);
    await cleanup(
      'global-protect-session',
      GlobalProtectAppSession.instance.disconnectAndClearCachedSession,
    );
    await cleanup('dio-cookies', DioConnector.instance.deleteCookies);
    await cleanup('webview-cookies', () => CookieManager.instance().deleteAllCookies());
    await cleanup('network-image-cache', cacheManager.emptyCache);
    await cleanup('generated-user-artifacts', UserSessionArtifacts.clear);

    CampusNetworkDetector.clearCache();
    await _clearUserScopedCaches();
    await init();
  }

  void _resetUserScopedMemory() {
    _userData = UserDataJson();
    _courseTableList.clear();
    _courseSemesterList.clear();
    _courseScoreList = CourseScoreCreditJson();
    _courseExtraInfoCache.clear();
    _setting.course = CourseSettingJson();
    _setting.announcement = AnnouncementSettingJson();
    _firstRun.clear();
  }

  Future<void> _clearUserScopedCaches() async {
    _resetUserScopedMemory();

    await Future.wait<void>([
      _remove(_userDataJsonKey),
      _remove(_courseTableJsonKey),
      _remove(_courseSemesterJsonKey),
      _remove(_scoreCreditJsonKey),
      _remove(_courseCategoryCacheKey),
      _remove(_courseExtraInfoCacheKey),
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
