import 'dart:async';

import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/core/network_request_pool.dart';
import 'package:qaq_app/src/connector/nportal_task_connector.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/share/course_table_share_codec.dart';
import 'package:qaq_app/src/share/course_table_share_data.dart';
import 'package:qaq_app/src/store/local_storage.dart';

class CourseTableCloudSync {
  CourseTableCloudSync._();

  static final CourseTableCloudSync instance = CourseTableCloudSync._();
  static const String taskTitle = 'QAQ 課表跨裝置同步';
  static const int maxTaskContentLength = 255;
  static const int _fragmentReserve = 32;
  static const int _maxCloudParts = 999;
  static const List<Duration> _retryDelays = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  Future<void> _queue = Future<void>.value();
  int _pushGeneration = 0;
  bool _backgroundSyncQueued = false;
  bool _sessionAlreadyAuthenticatedHint = false;
  Timer? _retryTimer;
  int _retryDelayIndex = 0;

  /// Starts cloud reconciliation without blocking app startup.
  ///
  /// Local data is never cleared just because the network/session is
  /// unavailable. Failed attempts are retried with bounded backoff, while the
  /// persisted dirty bit survives process restarts.
  Future<void> syncOnAppOpen({bool sessionAlreadyAuthenticated = false}) async {
    _sessionAlreadyAuthenticatedHint |= sessionAlreadyAuthenticated;
    _scheduleBackgroundSync();
  }

  /// Persists the local-dirty state, then schedules the network work in the
  /// background. Callers only wait for the local SharedPreferences write, not
  /// for nPortal.
  Future<void> pushLocalSnapshot() async {
    final storage = LocalStorage.instance;
    final account = storage.getAccount().trim();
    if (account.isEmpty) return;

    _pushGeneration++;
    await storage.setCourseTableCloudSyncDirty(true);
    _cancelRetry(resetBackoff: false);
    _scheduleBackgroundSync();
  }

  void _scheduleBackgroundSync() {
    if (_backgroundSyncQueued) return;
    _backgroundSyncQueued = true;
    unawaited(_enqueue(_runBackgroundSync));
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object error, StackTrace stackTrace) {
      Log.eWithStack('Course table cloud sync queue failed: $error', stackTrace);
    });
    return _queue;
  }

  Future<void> _runBackgroundSync() async {
    final sessionAlreadyAuthenticated = _sessionAlreadyAuthenticatedHint;
    _sessionAlreadyAuthenticatedHint = false;

    var success = false;
    try {
      success = await _syncOnce(sessionAlreadyAuthenticated: sessionAlreadyAuthenticated);
    } catch (error, stackTrace) {
      // Background sync is deliberately silent to the UI. Keep the local
      // dirty bit and retry later instead of surfacing a dialog or rolling
      // back a local import/delete.
      Log.eWithStack('Course table cloud sync deferred: $error', stackTrace);
    } finally {
      _backgroundSyncQueued = false;
    }

    if (success) {
      _cancelRetry(resetBackoff: true);
      if (LocalStorage.instance.getCourseTableCloudSyncDirty() &&
          LocalStorage.instance.getAccount().trim().isNotEmpty) {
        // A local edit may have happened while a previous snapshot was being
        // uploaded. Run once more immediately so the newest local state wins.
        _scheduleBackgroundSync();
      }
      return;
    }

    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    if (LocalStorage.instance.getAccount().trim().isEmpty) return;

    final index = _retryDelayIndex < _retryDelays.length ? _retryDelayIndex : _retryDelays.length - 1;
    final delay = _retryDelays[index];
    if (_retryDelayIndex < _retryDelays.length - 1) _retryDelayIndex++;

    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _scheduleBackgroundSync();
    });
  }

  void _cancelRetry({required bool resetBackoff}) {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (resetBackoff) _retryDelayIndex = 0;
  }

  Future<bool> _syncOnce({required bool sessionAlreadyAuthenticated}) async {
    final storage = LocalStorage.instance;
    final account = storage.getAccount().trim();
    if (account.isEmpty) return true;

    if (!sessionAlreadyAuthenticated && !await _ensurePortalSession()) return false;
    if (!_isCurrentAccount(account)) return true;

    final tasks = await _findCloudTasks();

    if (storage.getCourseTableCloudSyncDirty()) {
      final localRevision = _pushGeneration;
      await _pushSnapshot(tasks);
      if (_isCurrentAccount(account) && localRevision == _pushGeneration) {
        await storage.setCourseTableCloudSyncDirty(false);
      }
      return true;
    }

    if (tasks.isEmpty) {
      // An empty list is not proof that the cloud has never been initialized;
      // a transient/session response can also look empty. Only an explicit
      // local dirty mutation is allowed to create/replace cloud state.
      return true;
    }

    final reads = await _readTasks(tasks);
    if (reads == null) return false;

    // Empty/malformed same-title tasks are not evidence that the user's local
    // data should be destroyed. Ignore bad fragments and use any remaining
    // complete generation. If no complete generation exists, preserve both
    // sides and wait for an explicit local edit to repair the cloud.
    final contents = reads
        .map((read) => read.content?.trim() ?? '')
        .where((content) => _looksLikeSnapshotUrl(content))
        .toList(growable: false);
    if (contents.isEmpty) {
      Log.e('Course table cloud snapshot has no readable generation; preserving local data');
      return true;
    }

    List<CourseTableSharePerson> remote;
    try {
      remote = decodeSnapshotUrls(contents);
    } catch (error, stackTrace) {
      Log.eWithStack('Invalid course table cloud snapshot; preserving local data: $error', stackTrace);
      return true;
    }

    // A local import/delete may have happened while the background pull was in
    // flight. Never overwrite that newer local state with the just-read cloud
    // snapshot; the queued dirty push will run next.
    if (storage.getCourseTableCloudSyncDirty() || !_isCurrentAccount(account)) return true;

    await storage.replaceImportedCourseTableSharePeople(_withoutOwnAccount(remote), abortIfCloudDirty: true);
    return true;
  }

  Future<List<NPortalTaskRef>> _findCloudTasks() => NPortalTaskConnector.findTasksBySubject(taskTitle);

  Future<List<_CloudTaskRead>?> _readTasks(List<NPortalTaskRef> tasks) async {
    final reads = await NetworkRequestPool.shared.run<_CloudTaskRead>(
      tasks.map(
        (task) =>
            (timeout) async => _CloudTaskRead(
              task: task,
              content: await NPortalTaskConnector.getTaskContent(task.id, timeout: timeout),
            ),
      ),
      shouldRetry: (read) => read == null || read.content == null,
    );
    if (reads.any((read) => read == null)) return null;
    return reads.cast<_CloudTaskRead>();
  }

  Future<void> _pushSnapshot(List<NPortalTaskRef> existingTasks) async {
    final contents = encodeSnapshotUrls(_localPeople());
    await _commitSnapshotCopyOnWrite(existingTasks, contents);
  }

  /// Commits a complete new generation before touching any existing task.
  ///
  /// A network failure during create/rediscovery/completion therefore leaves
  /// the previous complete generation intact. Old tasks are cleanup-only and
  /// are deleted after the new generation has been verified readable.
  Future<void> _commitSnapshotCopyOnWrite(List<NPortalTaskRef> existingTasks, List<String> contents) async {
    if (contents.isEmpty) throw StateError('Course table cloud snapshot cannot be empty');

    var targetDn = LocalStorage.instance.getUserInfo().userDn.trim();
    if (targetDn.isEmpty) targetDn = (await NPortalTaskConnector.getDefaultTargetDn()) ?? '';
    if (targetDn.isEmpty) throw StateError('nPortal userDn is unavailable');

    final knownTaskIds = existingTasks.map((task) => task.id).toSet();

    // Stage every chunk as unfinished. Do not reuse/edit/delete old task IDs:
    // they are the rollback copy if the network disappears halfway through.
    for (final content in contents) {
      final created = await NPortalTaskConnector.createTask(subject: taskTitle, content: content, targetDn: targetDn);
      if (!created) throw StateError('nPortal rejected course table sync task creation');
    }

    final staged = await _rediscoverStagedTasks(knownTaskIds, contents);

    // Complete only the newly staged IDs. If any mutation fails, the old
    // generation is still untouched and dirty remains set for a later retry.
    for (final read in staged) {
      final content = read.content!;
      final updated = await NPortalTaskConnector.updateTask(id: read.task.id, subject: taskTitle, content: content);
      if (!updated) {
        throw StateError('nPortal rejected new course table sync task completion ${read.task.id}');
      }
    }

    // Verify the committed generation by ID/content before deleting rollback
    // copies. This catches session loss or server-side partial writes.
    final verifyReads = await _readTasks(staged.map((read) => read.task).toList(growable: false));
    if (verifyReads == null || verifyReads.length != staged.length) {
      throw StateError('Unable to verify newly committed nPortal sync generation');
    }
    final expectedById = <String, String>{for (final read in staged) read.task.id: read.content!};
    for (final read in verifyReads) {
      if (read.content != expectedById[read.task.id]) {
        throw StateError('nPortal sync verification mismatch for task ${read.task.id}');
      }
    }
    // Also prove the staged fragments form one complete decodable generation.
    decodeSnapshotUrls(verifyReads.map((read) => read.content!).toList(growable: false));

    // Commit succeeded. Old-task cleanup must never make a successful new
    // snapshot look failed: stale generations are harmless because decoding
    // selects the newest complete generation, and a future successful push will
    // try cleanup again.
    for (final task in existingTasks) {
      try {
        await NPortalTaskConnector.deleteTask(task.id);
      } catch (error, stackTrace) {
        Log.eWithStack('Deferred cleanup of old course table sync task ${task.id}: $error', stackTrace);
      }
    }
  }

  Future<List<_CloudTaskRead>> _rediscoverStagedTasks(Set<String> knownTaskIds, List<String> expectedContents) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 250 * attempt));

      final discovered = await _findCloudTasks();
      final candidates = discovered.where((task) => !knownTaskIds.contains(task.id)).toList(growable: false);
      if (candidates.length < expectedContents.length) continue;

      final reads = await _readTasks(candidates);
      if (reads == null) continue;

      final byContent = <String, List<_CloudTaskRead>>{};
      for (final read in reads) {
        final content = read.content;
        if (content == null) continue;
        byContent.putIfAbsent(content, () => <_CloudTaskRead>[]).add(read);
      }

      final ordered = <_CloudTaskRead>[];
      var complete = true;
      for (final content in expectedContents) {
        final matches = byContent[content];
        if (matches == null || matches.isEmpty) {
          complete = false;
          break;
        }
        ordered.add(matches.removeAt(0));
      }
      if (complete) return ordered;
    }

    throw StateError('Unable to rediscover a complete staged nPortal sync generation');
  }

  static bool _looksLikeSnapshotUrl(String content) {
    if (content.isEmpty) return false;
    final uri = Uri.tryParse(content);
    if (uri == null || uri.scheme != 'qaq' || uri.host != 'course-table' || uri.path != '/share') return false;
    try {
      final fragment = Uri.splitQueryString(uri.fragment);
      return fragment['g']?.isNotEmpty == true &&
          int.tryParse(fragment['p'] ?? '') != null &&
          int.tryParse(fragment['t'] ?? '') != null;
    } catch (_) {
      return false;
    }
  }

  static List<String> encodeSnapshotUrls(
    Iterable<CourseTableSharePerson> people, {
    int maxLength = maxTaskContentLength,
    String? generation,
  }) {
    if (maxLength <= _fragmentReserve) throw ArgumentError.value(maxLength, 'maxLength');
    final generationId = generation ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    if (!RegExp(r'^[0-9a-z]+$').hasMatch(generationId)) {
      throw ArgumentError.value(generationId, 'generation');
    }
    final baseMaxLength = maxLength - _fragmentReserve;

    final units = <_CloudCourseUnit>[];
    final sortedPeople = people.where((person) => person.studentId.trim().isNotEmpty).toList()
      ..sort((a, b) => a.studentId.compareTo(b.studentId));
    for (final person in sortedPeople) {
      final semesterKeys = person.semesters.keys.toList()..sort(_compareSemesterKeys);
      for (final semesterKey in semesterKeys) {
        for (final course in person.semesters[semesterKey] ?? const <CourseTableShareCourse>[]) {
          units.add(
            _CloudCourseUnit(
              studentId: person.studentId.trim(),
              name: person.name.trim(),
              semesterKey: semesterKey,
              course: course,
            ),
          );
        }
      }
    }

    final baseUrls = <String>[];
    if (units.isEmpty) {
      final emptyUrl = _encodeUnits(const <_CloudCourseUnit>[]);
      if (emptyUrl.length > baseMaxLength) throw StateError('Empty course table sync URL exceeds nPortal limit');
      baseUrls.add(emptyUrl);
    } else {
      var current = <_CloudCourseUnit>[];
      for (final unit in units) {
        final trial = <_CloudCourseUnit>[...current, unit];
        final trialUrl = _encodeUnits(trial);
        if (trialUrl.length <= baseMaxLength) {
          current = trial;
          continue;
        }

        if (current.isEmpty) {
          throw StateError('One shared course cannot fit within the nPortal 255-character content limit');
        }
        baseUrls.add(_encodeUnits(current));
        current = <_CloudCourseUnit>[unit];
        final singleUrl = _encodeUnits(current);
        if (singleUrl.length > baseMaxLength) {
          throw StateError('One shared course cannot fit within the nPortal 255-character content limit');
        }
      }
      if (current.isNotEmpty) baseUrls.add(_encodeUnits(current));
    }

    if (baseUrls.length > _maxCloudParts) {
      throw StateError('Course table cloud snapshot requires too many nPortal tasks');
    }
    final total = baseUrls.length;
    final result = <String>[];
    for (var index = 0; index < total; index++) {
      final uri = Uri.parse(baseUrls[index]);
      final value = uri.replace(fragment: 'g=$generationId&p=${index + 1}&t=$total').toString();
      if (value.length > maxLength) throw StateError('Course table sync URL exceeds nPortal limit');
      result.add(value);
    }
    return result;
  }

  static List<CourseTableSharePerson> decodeSnapshotUrls(Iterable<String> urls) {
    final groups = <String, _CloudSnapshotGroup>{};
    final legacy = <String>[];

    for (final value in urls) {
      final trimmed = value.trim();
      final uri = Uri.parse(trimmed);
      final fragment = uri.fragment;
      if (fragment.isEmpty) {
        legacy.add(trimmed);
        continue;
      }

      final metadata = Uri.splitQueryString(fragment);
      final generation = metadata['g'];
      final part = int.tryParse(metadata['p'] ?? '');
      final total = int.tryParse(metadata['t'] ?? '');
      final generationValue = generation == null ? null : int.tryParse(generation, radix: 36);
      if (generation == null ||
          generationValue == null ||
          part == null ||
          total == null ||
          part < 1 ||
          total < 1 ||
          part > total ||
          total > _maxCloudParts) {
        throw const FormatException('Invalid course table cloud snapshot metadata');
      }

      final group = groups.putIfAbsent(
        generation,
        () => _CloudSnapshotGroup(generationValue: generationValue, total: total),
      );
      if (group.total != total) throw const FormatException('Inconsistent course table cloud snapshot metadata');
      group.parts[part] = trimmed;
    }

    final completeGroups = groups.values.where((group) => group.isComplete).toList()
      ..sort((a, b) => b.generationValue.compareTo(a.generationValue));
    if (completeGroups.isNotEmpty) {
      final group = completeGroups.first;
      return _decodeCompleteSnapshot(List<String>.generate(group.total, (index) => group.parts[index + 1]!));
    }

    if (legacy.isNotEmpty && groups.isEmpty) return _decodeCompleteSnapshot(legacy);
    throw const FormatException('No complete course table cloud snapshot');
  }

  static List<CourseTableSharePerson> _decodeCompleteSnapshot(Iterable<String> urls) {
    final decoded = <CourseTableSharePerson>[];
    for (final value in urls) {
      final payload = CourseTableShareCodec.decodeUrl(value.trim());
      final people = CourseTableSharePerson.fromPayload(payload);
      if (people.isEmpty) return const <CourseTableSharePerson>[];
      decoded.addAll(people);
    }
    return _mergePeople(decoded);
  }

  static String _encodeUnits(List<_CloudCourseUnit> units) {
    final people = <String, Map<String, dynamic>>{};
    for (final unit in units) {
      final person = people.putIfAbsent(
        unit.studentId,
        () => <String, dynamic>{'studentId': unit.studentId, 'name': unit.name, 'semesters': <String, dynamic>{}},
      );
      if ((person['name'] as String).isEmpty && unit.name.isNotEmpty) person['name'] = unit.name;
      final semesters = person['semesters'] as Map<String, dynamic>;
      final courses = semesters.putIfAbsent(unit.semesterKey, () => <Map<String, dynamic>>[]) as List<dynamic>;
      courses.add(unit.course.toJson());
    }

    return CourseTableShareCodec.encodeUrl(<String, dynamic>{
      'version': CourseTableShareCodec.version,
      'people': people.values.toList(growable: false),
    });
  }

  static List<CourseTableSharePerson> _mergePeople(Iterable<CourseTableSharePerson> people) {
    final merged = <String, _MutableCloudPerson>{};
    for (final person in people) {
      final studentId = person.studentId.trim();
      if (studentId.isEmpty) continue;
      final target = merged.putIfAbsent(studentId, () => _MutableCloudPerson(studentId, person.name.trim()));
      if (target.name.isEmpty && person.name.trim().isNotEmpty) target.name = person.name.trim();

      for (final entry in person.semesters.entries) {
        final courses = target.semesters.putIfAbsent(entry.key, () => <String, CourseTableShareCourse>{});
        for (final course in entry.value) {
          final key = course.snum.trim().isNotEmpty ? 's:${course.snum.trim()}' : 'c:${course.currCode.trim()}';
          final previous = courses[key];
          if (previous == null) {
            courses[key] = course;
            continue;
          }
          final syllabusCodes = <String>{...previous.syllabusCodes, ...course.syllabusCodes}.toList()..sort();
          courses[key] = CourseTableShareCourse(
            snum: previous.snum.isNotEmpty ? previous.snum : course.snum,
            currCode: previous.currCode.isNotEmpty ? previous.currCode : course.currCode,
            syllabusCodes: syllabusCodes,
          );
        }
      }
    }

    final result = merged.values.map((person) {
      final semesters = <String, List<CourseTableShareCourse>>{};
      final keys = person.semesters.keys.toList()..sort(_compareSemesterKeys);
      for (final key in keys) {
        final courses = person.semesters[key]!.values.toList()..sort((a, b) => a.snum.compareTo(b.snum));
        semesters[key] = courses;
      }
      return CourseTableSharePerson(studentId: person.studentId, name: person.name, semesters: semesters);
    }).toList()..sort((a, b) => a.studentId.compareTo(b.studentId));
    return result;
  }

  static int _compareSemesterKeys(String a, String b) {
    final aParts = a.split('-');
    final bParts = b.split('-');
    final aYear = int.tryParse(aParts.first) ?? -1;
    final bYear = int.tryParse(bParts.first) ?? -1;
    final year = bYear.compareTo(aYear);
    if (year != 0) return year;
    final aSemester = aParts.length > 1 ? int.tryParse(aParts[1]) ?? -1 : -1;
    final bSemester = bParts.length > 1 ? int.tryParse(bParts[1]) ?? -1 : -1;
    return bSemester.compareTo(aSemester);
  }

  List<CourseTableSharePerson> _localPeople() =>
      _withoutOwnAccount(LocalStorage.instance.getImportedCourseTableSharePeople());

  bool _isCurrentAccount(String account) => LocalStorage.instance.getAccount().trim() == account;

  List<CourseTableSharePerson> _withoutOwnAccount(Iterable<CourseTableSharePerson> people) {
    final account = LocalStorage.instance.getAccount().trim();
    return people.where((person) => person.studentId.trim().isNotEmpty && person.studentId.trim() != account).toList();
  }

  Future<bool> _ensurePortalSession() async {
    if (await NTUTConnector.checkSession()) return true;

    final storage = LocalStorage.instance;
    final account = storage.getAccount().trim();
    final password = storage.getPassword();
    if (account.isEmpty || password.isEmpty) return false;

    await NTUTConnector.clearSession();
    final result = await NTUTConnector.login(account, password);
    return result.isSuccess;
  }
}

class _CloudTaskRead {
  const _CloudTaskRead({required this.task, required this.content});

  final NPortalTaskRef task;
  final String? content;
}

class _CloudSnapshotGroup {
  _CloudSnapshotGroup({required this.generationValue, required this.total});

  final int generationValue;
  final int total;
  final Map<int, String> parts = <int, String>{};

  bool get isComplete {
    if (parts.length != total) return false;
    for (var part = 1; part <= total; part++) {
      if (!parts.containsKey(part)) return false;
    }
    return true;
  }
}

class _CloudCourseUnit {
  const _CloudCourseUnit({
    required this.studentId,
    required this.name,
    required this.semesterKey,
    required this.course,
  });

  final String studentId;
  final String name;
  final String semesterKey;
  final CourseTableShareCourse course;
}

class _MutableCloudPerson {
  _MutableCloudPerson(this.studentId, this.name);

  final String studentId;
  String name;
  final Map<String, Map<String, CourseTableShareCourse>> semesters = <String, Map<String, CourseTableShareCourse>>{};
}
