import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/model/course/course_main_extra_json.dart';
import 'package:qaq_app/src/model/coursetable/course_classroom_cache.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/store/local_storage.dart';

class CourseClassroomResolutionTask {
  static const cacheMaxAge = Duration(days: 7);
  static final Set<String> _inFlight = <String>{};
  static Future<void> _persistQueue = Future<void>.value();

  static void _trace(String message) {
    final line = '[CLRDBG] $message';
    debugPrint(line);
    Log.d(line);
  }

  static void refreshInBackground(CourseTableJson courseTable) {
    final storage = LocalStorage.instance;
    final pending = <_ClassroomResolutionTarget>[];
    final targets = _collectTargets(courseTable).values.toList();

    _trace(
      'trigger semester=${courseTable.courseSemester.year}-${courseTable.courseSemester.semester} '
      'targets=${targets.length}',
    );

    for (final target in targets) {
      final cached = storage.getCourseClassroomCache(courseTable.courseSemester, target.courseId);
      final shouldRefresh = storage.shouldRefreshCourseClassroomCache(
        courseTable.courseSemester,
        target.main,
        maxAge: cacheMaxAge,
      );
      _trace(
        'target id=${target.courseId} name=${target.main.course.name} '
        'slots=${target.slots.map((slot) => '${slot.day.name}/${slot.section.name}').join(',')} '
        'rooms=${target.main.classroom.map((room) => '${room.name}|${room.href}').join(' || ')} '
        'cache=${cached == null ? 'MISS' : 'v${cached.schemaVersion} ${cached.updatedAt.toIso8601String()} slots=${cached.classroomBySlot}'} '
        'refresh=$shouldRefresh',
      );
      if (!shouldRefresh) continue;

      final cacheKey = CourseClassroomCacheJson.cacheKey(courseTable.courseSemester, target.courseId);
      if (_inFlight.add(cacheKey)) {
        pending.add(target);
      } else {
        _trace('skip in-flight id=${target.courseId}');
      }
    }

    if (pending.isEmpty) {
      _trace('nothing pending');
      return;
    }
    _trace('start pending=${pending.map((target) => target.courseId).join(',')}');

    unawaited(
      _refreshTargets(courseTable, pending)
          .catchError((Object error, StackTrace stackTrace) {
            Log.eWithStack(error.toString(), stackTrace);
          })
          .whenComplete(() {
            for (final target in pending) {
              _inFlight.remove(CourseClassroomCacheJson.cacheKey(courseTable.courseSemester, target.courseId));
            }
          }),
    );
  }

  static Map<String, _ClassroomResolutionTarget> _collectTargets(CourseTableJson courseTable) {
    final targets = <String, _ClassroomResolutionTarget>{};

    for (final day in Day.values) {
      if (day == Day.UnKnown) continue;
      final dayMap = courseTable.courseInfoMap[day];
      if (dayMap == null) continue;

      for (final entry in dayMap.entries) {
        final section = entry.key;
        if (section == SectionNumber.T_UnKnown) continue;

        final main = entry.value.main;
        final courseId = main.course.id.trim();
        if (courseId.isEmpty || main.classroom.length < 2) continue;

        final target = targets.putIfAbsent(courseId, () => _ClassroomResolutionTarget(courseId: courseId, main: main));
        target.slots.add(_ClassroomSlot(day, section));
      }
    }

    return targets;
  }

  static Future<void> _refreshTargets(CourseTableJson courseTable, List<_ClassroomResolutionTarget> targets) async {
    final usageRequests = <String, Future<Map<Day, Map<SectionNumber, Set<String>>>?>>{};
    final storage = LocalStorage.instance;
    var changed = false;

    for (final target in targets) {
      try {
        final cache = await _resolveTarget(courseTable, target, usageRequests);
        if (cache == null) continue;

        storage.setCourseClassroomCache(courseTable.courseSemester, target.courseId, cache);
        changed = true;
      } catch (e, stack) {
        // One malformed classroom/course must not abort resolution for the
        // remaining timetable. Do not touch this target's existing cache.
        Log.eWithStack('[CourseClassroomResolutionTask] ${target.courseId}: $e', stack);
      }
    }

    if (changed) {
      await _saveCacheSerialized(storage);
    }
  }

  static Future<CourseClassroomCacheJson?> _resolveTarget(
    CourseTableJson courseTable,
    _ClassroomResolutionTarget target,
    Map<String, Future<Map<Day, Map<SectionNumber, Set<String>>>?>> usageRequests,
  ) async {
    final resolved = <String, String>{};
    final ambiguousSlots = <String>{};
    final targetIdentifiers = _courseIdentifiers(target.main);
    _trace(
      'resolve id=${target.courseId} courseHref=${target.main.course.href} '
      'identifiers=$targetIdentifiers',
    );
    if (targetIdentifiers.isEmpty) {
      _trace('abort id=${target.courseId}: no identifiers');
      return null;
    }

    for (final classroom in target.main.classroom) {
      final href = classroom.href.trim();
      _trace('room id=${target.courseId} name=${classroom.name} href=$href');
      if (href.isEmpty) {
        _trace('abort id=${target.courseId}: missing classroom href for ${classroom.name}');
        // Without every candidate classroom-use URL we cannot authoritatively
        // decide which candidate owns a period. Keep the previous cache (or
        // the original multi-room fallback on a cache miss).
        return null;
      }

      _trace('fetch classroom=${classroom.name} url=$href');
      final usage = await usageRequests.putIfAbsent(href, () => CourseConnector.getClassroomUsage(href));
      if (usage == null) {
        _trace('abort id=${target.courseId}: usage=null room=${classroom.name} url=$href');
        // Network/parse failures must not replace a usable stale cache.
        return null;
      }

      for (final slot in target.slots) {
        final courseIdentifiers = usage[slot.day]?[slot.section];
        final matched = courseIdentifiers?.any(targetIdentifiers.contains) == true;
        _trace(
          'compare id=${target.courseId} room=${classroom.name} '
          'slot=${slot.day.name}/${slot.section.name} '
          'target=$targetIdentifiers cell=${courseIdentifiers ?? const <String>{}} match=$matched',
        );
        if (!matched) continue;

        final slotKey = CourseClassroomCacheJson.slotKey(slot.day, slot.section);
        final previous = resolved[slotKey];
        if (previous == null) {
          resolved[slotKey] = classroom.name;
        } else if (previous != classroom.name) {
          // One period should resolve to one room. If candidate classroom pages
          // contradict each other, leave that slot unresolved and fall back to
          // the original multi-room display.
          ambiguousSlots.add(slotKey);
        }
      }
    }

    for (final slotKey in ambiguousSlots) {
      resolved.remove(slotKey);
    }

    // A completely empty resolution is not a successful refresh. Keeping it
    // out of persistent cache prevents identifier/parser bugs from poisoning
    // the course for seven days. Existing stale cache stays usable; on a cache
    // miss the UI continues to fall back to the original multi-room text.
    if (resolved.isEmpty) {
      _trace(
        'no match id=${target.courseId} identifiers=$targetIdentifiers '
        'ambiguous=$ambiguousSlots',
      );
      return null;
    }

    _trace('resolved id=${target.courseId} map=$resolved ambiguous=$ambiguousSlots');
    return CourseClassroomCacheJson(
      year: courseTable.courseSemester.year,
      semester: courseTable.courseSemester.semester,
      courseId: target.courseId,
      updatedAt: DateTime.now(),
      candidateSignature: CourseClassroomCacheJson.classroomSignature(target.main),
      classroomBySlot: resolved,
    );
  }

  static Set<String> _courseIdentifiers(CourseMainInfoJson main) {
    final identifiers = <String>{};

    void add(String? value) {
      if (value == null) return;
      final normalized = CourseConnector.strQ2B(value).replaceAll(RegExp(r'\s'), '').toUpperCase();
      if (normalized.isNotEmpty) identifiers.add(normalized);
    }

    // Select.jsp / ShowSyllabus.jsp normally exposes the six-digit snum here.
    add(main.course.id);

    // New table fetches also retain the Curr.jsp href, whose code parameter is
    // the alphanumeric identifier (for example 2B03024). Old cached tables may
    // not have this href, which is fine because Croom.jsp also exposes snum.
    final href = main.course.href.trim();
    if (href.isNotEmpty) {
      final uri = Uri.tryParse(href);
      add(uri?.queryParameters['code']);
      add(uri?.queryParameters['snum']);
    }

    return identifiers;
  }

  static Future<void> _saveCacheSerialized(LocalStorage storage) {
    final save = _persistQueue.then((_) => storage.saveCourseClassroomCache());
    _persistQueue = save.catchError((Object error, StackTrace stackTrace) {
      Log.eWithStack(error.toString(), stackTrace);
    });
    return save;
  }
}

class _ClassroomResolutionTarget {
  final String courseId;
  final CourseMainInfoJson main;
  final List<_ClassroomSlot> slots = <_ClassroomSlot>[];

  _ClassroomResolutionTarget({required this.courseId, required this.main});
}

class _ClassroomSlot {
  final Day day;
  final SectionNumber section;

  _ClassroomSlot(this.day, this.section);
}
