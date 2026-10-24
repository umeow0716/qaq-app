import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
  static const Duration _abandonedStagingMinAge = Duration(minutes: 30);
  static const List<Duration> _retryDelays = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  Future<void> _queue = Future<void>.value();
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

    // A startup hint is not proof of a still-valid portal session.
    if (sessionAlreadyAuthenticated) {
      if (!await NTUTConnector.checkSession() && !await _ensurePortalSession()) return false;
    } else if (!await _ensurePortalSession()) {
      return false;
    }
    if (!_isCurrentAccount(account)) return false;

    final cloud = await _loadVerifiedCloudSnapshot();
    if (cloud == null || !_isCurrentAccount(account)) return false;
    final revision = storage.getCourseTableCloudSyncLocalRevision();
    final dirty = storage.getCourseTableCloudSyncDirty();
    final local = _localPeople();
    final base = storage.getCourseTableCloudSyncBasePeople();

    if (cloud.isCorrupt) {
      // Do not turn a corrupt cloud into an empty tombstone. Only a stable,
      // readable corrupt generation with a real local/last-known-good recovery
      // source may be repaired automatically.
      final recovery = local.isNotEmpty ? local : (!dirty ? base : null);
      if (recovery == null || recovery.isEmpty) {
        Log.e('Cloud snapshot is corrupt; no nonempty recovery source, preserving both sides');
        return false;
      }
      return _publishVerifiedSnapshot(account, revision, cloud, recovery);
    }

    if (cloud.people == null) {
      if (!dirty) return true;
      // A disappearing cloud is not proof that a formerly synchronized
      // collection was deliberately deleted. Never publish an empty snapshot
      // if we have any history of remote data.
      if (base != null && base.isNotEmpty) return false;
      return _publishVerifiedSnapshot(account, revision, cloud, local);
    }

    if (!dirty) {
      // Older app versions had no verified-base marker. Never erase existing
      // unverified local imports merely because this is the first successful
      // remote read (including a remotely published empty tombstone).
      if (!canPullRemoteWithoutDiscardingLocal(base: base, local: local, remote: cloud.people!)) {
        Log.e('Unverified local course tables differ from cloud; preserving local data for explicit reconciliation');
        return false;
      }
      return storage.applyVerifiedCourseTableCloudSnapshot(
        _withoutOwnAccount(cloud.people!),
        account: account,
        expectedRevision: revision,
      );
    }

    final merged = mergeSnapshots(base: base, local: local, remote: cloud.people!);
    if (merged == null) {
      Log.e('Course table sync conflict: same person was changed independently; cloud write deferred');
      return false;
    }
    if (_samePeople(merged, cloud.people!)) {
      return storage.applyVerifiedCourseTableCloudSnapshot(
        merged, account: account, expectedRevision: revision, completeLocalUpload: true,
      );
    }
    return _publishVerifiedSnapshot(account, revision, cloud, merged);
  }

  Future<bool> _publishVerifiedSnapshot(
    String account,
    int revision,
    _VerifiedCloudSnapshot cloud,
    List<CourseTableSharePerson> people,
  ) async {
    final storage = LocalStorage.instance;
    if (!_isCurrentAccount(account) || storage.getCourseTableCloudSyncLocalRevision() != revision) return false;
    // Authentication can expire between the initial read and this write.
    if (!await NTUTConnector.checkSession()) return false;
    final nextGeneration = _nextGenerationAfter(cloud.signature);
    await _commitSnapshotCopyOnWrite(
      cloud, encodeSnapshotUrls(people, generation: nextGeneration), account: account,
    );
    // A user mutation may have started during the upload. The cloud now holds
    // an older snapshot, so leave dirty set and retry instead of hiding it.
    if (!_isCurrentAccount(account) || storage.getCourseTableCloudSyncLocalRevision() != revision) return false;
    return storage.applyVerifiedCourseTableCloudSnapshot(
      people, account: account, expectedRevision: revision, completeLocalUpload: true,
    );
  }

  static String _nextGenerationAfter(String signature) {
    // Microsecond clocks alone are not globally unique across devices.
    final jitter = Random.secure().nextInt(1024);
    var next = DateTime.now().microsecondsSinceEpoch + jitter;
    final generations = RegExp(r'[?#&]g=([0-9a-z]+)');
    for (final match in generations.allMatches(signature)) {
      final value = int.tryParse(match.group(1)!, radix: 36);
      if (value != null && value >= next) next = value + 1 + jitter;
    }
    return next.toRadixString(36);
  }

  /// First pull after migration must not silently delete local-only entries.
  static bool canPullRemoteWithoutDiscardingLocal({
    required List<CourseTableSharePerson>? base,
    required List<CourseTableSharePerson> local,
    required List<CourseTableSharePerson> remote,
  }) =>
      _samePeople(local, remote) ||
      (base == null ? local.isEmpty : _samePeople(local, base));

  /// Three-way, per-person reconciliation. Only local changes relative to a
  /// previously verified base may delete remote people. Simultaneous changes
  /// to the same person require user conflict resolution (fail closed).
  /// Without a base, local *additions* are safe, but colliding edits are not.
  static List<CourseTableSharePerson>? mergeSnapshots({
    required List<CourseTableSharePerson>? base,
    required List<CourseTableSharePerson> local,
    required List<CourseTableSharePerson> remote,
  }) {
    final old = {for (final p in base ?? const <CourseTableSharePerson>[]) p.studentId.trim(): p};
    final mine = {for (final p in local) p.studentId.trim(): p};
    final theirs = {for (final p in remote) p.studentId.trim(): p};
    final ids = <String>{...old.keys, ...mine.keys, ...theirs.keys}..remove('');
    final result = <CourseTableSharePerson>[];
    for (final id in ids) {
      final before = old[id];
      final current = mine[id];
      final latest = theirs[id];
      final localChanged = base == null ? current != null : !_samePerson(before, current);
      final remoteChanged = base == null ? latest != null : !_samePerson(before, latest);
      if (localChanged && remoteChanged && !_samePerson(current, latest)) return null;
      final chosen = localChanged ? current : latest;
      if (chosen != null) result.add(chosen);
    }
    result.sort((a, b) => a.studentId.compareTo(b.studentId));
    return result;
  }

  static bool _samePerson(CourseTableSharePerson? a, CourseTableSharePerson? b) =>
      a == null ? b == null : b != null && _canonicalPerson(a) == _canonicalPerson(b);

  static String _canonicalPerson(CourseTableSharePerson person) {
    final payload = person.toJson();
    final semesters = person.semesters.keys.toList()..sort();
    payload['semesters'] = {
      for (final semester in semesters)
        semester: (person.semesters[semester]!.map((course) {
          final courseJson = course.toJson();
          (courseJson['syllabusCodes'] as List<String>).sort();
          return courseJson;
        }).toList()
          ..sort((a, b) => '${a['snum']}:${a['currCode']}'.compareTo('${b['snum']}:${b['currCode']}'))),
    };
    return jsonEncode(payload);
  }

  static bool _samePeople(List<CourseTableSharePerson> a, List<CourseTableSharePerson> b) =>
      _mergePeopleCanonical(a) == _mergePeopleCanonical(b);

  static String _mergePeopleCanonical(Iterable<CourseTableSharePerson> people) {
    final sorted = people.toList()..sort((a, b) => a.studentId.compareTo(b.studentId));
    return sorted.map(_canonicalPerson).join('\u0000');
  }

  /// Empty discovery must be confirmed independently. Malformed task contents
  /// must be stable on two reads before automatic repair is even considered.
  Future<_VerifiedCloudSnapshot?> _loadVerifiedCloudSnapshot() async {
    final first = await _findCloudTasks();
    if (first.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final second = await _findCloudTasks();
      if (second.isNotEmpty) return _inspectCloudTasks(second);
      return const _VerifiedCloudSnapshot(tasks: [], people: null, signature: 'empty');
    }
    return _inspectCloudTasks(first);
  }

  Future<_VerifiedCloudSnapshot?> _inspectCloudTasks(List<NPortalTaskRef> tasks) async {
    final reads = await _readTasks(tasks);
    if (reads == null || reads.any((read) => read.content == null)) return null;
    final confirmed = await _findCloudTasks();
    if (!_sameTaskIds(tasks, confirmed)) return null;
    final signature = _taskReadSignature(reads);
    if (signature == null) return null;
    final contents = reads.map((read) => read.content!.trim()).toList(growable: false);
    final candidateUrls = contents.where(_looksLikeSnapshotUrl).toList(growable: false);
    try {
      if (candidateUrls.isEmpty) throw const FormatException('No readable QAQ snapshot');
      return _VerifiedCloudSnapshot(tasks: tasks, people: decodeSnapshotUrls(candidateUrls), signature: signature);
    } catch (error, stackTrace) {
      Log.eWithStack('Undecodable nPortal snapshot: $error', stackTrace);
      // An in-progress multi-part commit is not corruption. Wait for the
      // generation to complete or age out before attempting repair.
      if (_hasRecentIncompleteGeneration(candidateUrls)) return null;
      // An unrelated manual task with the same title is not enough evidence
      // to authorize initialization. Prefer preserving the cloud in doubt.
      if (contents.any((content) =>
          content.isNotEmpty && !content.startsWith('qaq://course-table/share?'))) {
        return null;
      }
      // Re-read every entry and require identical content before considering
      // destructive repair of an apparently corrupt cloud.
      final reread = await _readTasks(confirmed);
      if (reread == null || _taskReadSignature(reread) != signature) return null;
      return _VerifiedCloudSnapshot(tasks: tasks, isCorrupt: true, signature: signature);
    }
  }

  static bool _hasRecentIncompleteGeneration(List<String> urls) {
    final byGeneration = <String, Set<int>>{};
    final totals = <String, int>{};
    final exampleByGeneration = <String, String>{};
    for (final value in urls) {
      try {
        final uri = Uri.parse(value);
        final fragment = Uri.splitQueryString(uri.fragment);
        final generation = fragment['g'];
        final part = int.tryParse(fragment['p'] ?? '');
        final total = int.tryParse(fragment['t'] ?? '');
        if (generation == null || part == null || total == null || part < 1 || part > total) continue;
        byGeneration.putIfAbsent(generation, () => <int>{}).add(part);
        exampleByGeneration[generation] = value;
        totals[generation] = total;
      } catch (_) {
        // Malformed metadata is considered by the stable-corruption check.
      }
    }
    for (final entry in byGeneration.entries) {
      if (entry.value.length < (totals[entry.key] ?? 0)) {
        if (!_isAbandonedStagingSnapshot(exampleByGeneration[entry.key]!)) return true;
      }
    }
    return false;
  }

  static String? _taskReadSignature(List<_CloudTaskRead> reads) {
    if (reads.any((read) => read.content == null)) return null;
    final sorted = reads.toList()..sort((a, b) => a.task.id.compareTo(b.task.id));
    return sorted.map((read) => '${read.task.id.length}:${read.task.id}:${read.content!.length}:${read.content!}').join('|');
  }

  static bool _sameTaskIds(List<NPortalTaskRef> left, List<NPortalTaskRef> right) {
    final a = left.map((task) => task.id).toSet();
    final b = right.map((task) => task.id).toSet();
    return a.length == b.length && a.containsAll(b);
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

  /// Commits a complete new generation before touching any existing task.
  ///
  /// A network failure during create/rediscovery/completion therefore leaves
  /// the previous complete generation intact. Old tasks are cleanup-only and
  /// are deleted after the new generation has been verified readable.
  Future<void> _commitSnapshotCopyOnWrite(
    _VerifiedCloudSnapshot before,
    List<String> contents, {
    required String account,
  }) async {
    final existingTasks = before.tasks;
    if (contents.isEmpty) throw StateError('Course table cloud snapshot cannot be empty');

    var targetDn = LocalStorage.instance.getUserInfo().userDn.trim();
    if (targetDn.isEmpty) targetDn = (await NPortalTaskConnector.getDefaultTargetDn()) ?? '';
    if (targetDn.isEmpty) throw StateError('nPortal userDn is unavailable');

    final knownTaskIds = existingTasks.map((task) => task.id).toSet();

    // Stage every chunk as unfinished. Do not reuse/edit/delete old task IDs:
    // they are the rollback copy if the network disappears halfway through.
    for (final content in contents) {
      if (!_isCurrentAccount(account)) throw StateError('Account changed during cloud staging');
      final created = await NPortalTaskConnector.createTask(subject: taskTitle, content: content, targetDn: targetDn);
      if (!created) throw StateError('nPortal rejected course table sync task creation');
    }

    final staged = await _rediscoverStagedTasks(knownTaskIds, contents);

    // Compare contents as well as IDs: another device can update an existing
    // task or complete a new generation while ours was being staged.
    final latest = await _loadVerifiedCloudSnapshot();
    if (!_isCurrentAccount(account) || latest == null || latest.signature != before.signature) {
      throw StateError('nPortal cloud changed during staging; refusing stale commit');
    }

    // Confirm that the session did not expire before promotion.
    if (!await NTUTConnector.checkSession()) throw StateError('nPortal session expired before cloud commit');

    // Complete only the newly staged IDs. If any mutation fails, the old
    // generation is still untouched and dirty remains set for a later retry.
    for (final read in staged) {
      if (!_isCurrentAccount(account)) throw StateError('Account changed during cloud commit');
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

    // Content reads alone do not prove another device can discover this
    // generation, because readers intentionally query state=100 only. Wait
    // until every newly committed ID is visible through the completed-task
    // finder before removing the rollback generation.
    await _waitUntilCompletedTasksAreDiscoverable(staged.map((read) => read.task.id).toSet());

    // Commit succeeded. Old-task cleanup must never make a successful new
    // snapshot look failed: stale generations are harmless because decoding
    // selects the newest complete generation, and a future successful push will
    // try cleanup again.
    final observed = await _findCloudTasks();
    final allowedIds = <String>{...knownTaskIds, ...staged.map((read) => read.task.id)};
    if (observed.any((task) => !allowedIds.contains(task.id))) {
      // A concurrent writer appeared. Do not destroy its rollback data.
      Log.e('Concurrent nPortal writer detected; old-generation cleanup deferred');
      return;
    }
    final oldReads = await _readTasks(existingTasks);
    if (oldReads == null ||
        (before.tasks.isNotEmpty && _taskReadSignature(oldReads) != before.signature)) {
      Log.e('Old snapshot changed during cleanup; preserving old tasks');
      return;
    }
    for (final read in oldReads) {
      if (!_isCurrentAccount(account)) return;
      // Never delete an unrelated/manual entry with the same title.
      if (!_looksLikeSnapshotUrl(read.content?.trim() ?? '')) continue;
      try {
        await NPortalTaskConnector.deleteTask(read.task.id);
      } catch (error, stackTrace) {
        Log.eWithStack('Deferred cleanup of old course table sync task ${read.task.id}: $error', stackTrace);
      }
    }

    // A crash/network loss can leave old state=0 staging tasks behind. They are
    // never authoritative, but repeated retries would otherwise accumulate
    // them forever. Only remove same-title QAQ staging fragments that are old
    // enough to be abandoned; this avoids deleting another device's active
    // copy-on-write generation. Unknown/manual tasks are left alone.
    await _cleanupAbandonedStagingTasks(staged.map((read) => read.task.id).toSet());
  }

  Future<void> _waitUntilCompletedTasksAreDiscoverable(Set<String> expectedTaskIds) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      final completed = await _findCloudTasks();
      final completedIds = completed.map((task) => task.id).toSet();
      if (expectedTaskIds.every(completedIds.contains)) return;
    }
    throw StateError('New nPortal sync generation is not visible as completed tasks');
  }

  Future<void> _cleanupAbandonedStagingTasks(Set<String> protectedTaskIds) async {
    try {
      final tasks = await NPortalTaskConnector.findStagedTasksBySubject(taskTitle);
      if (tasks.isEmpty) return;

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
      for (final read in reads.whereType<_CloudTaskRead>()) {
        if (protectedTaskIds.contains(read.task.id)) continue;
        final content = read.content?.trim() ?? '';
        if (!_looksLikeSnapshotUrl(content) || !_isAbandonedStagingSnapshot(content)) continue;
        try {
          await NPortalTaskConnector.deleteTask(read.task.id);
        } catch (error, stackTrace) {
          Log.eWithStack('Deferred cleanup of staged course table sync task ${read.task.id}: $error', stackTrace);
        }
      }
    } catch (error, stackTrace) {
      // Cleanup is best-effort and must never turn a verified commit into a
      // failed sync. A later successful push will retry it.
      Log.eWithStack('Deferred cleanup of staged course table sync tasks: $error', stackTrace);
    }
  }

  Future<List<_CloudTaskRead>> _rediscoverStagedTasks(Set<String> knownTaskIds, List<String> expectedContents) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 250 * attempt));

      final discovered = await NPortalTaskConnector.findStagedTasksBySubject(taskTitle);
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

  static bool _isAbandonedStagingSnapshot(String content) {
    try {
      final uri = Uri.parse(content);
      final generation = Uri.splitQueryString(uri.fragment)['g'];
      if (generation == null) return false;
      final createdMicros = int.tryParse(generation, radix: 36);
      if (createdMicros == null) return false;
      final ageMicros = DateTime.now().microsecondsSinceEpoch - createdMicros;
      return ageMicros >= _abandonedStagingMinAge.inMicroseconds;
    } catch (_) {
      return false;
    }
  }

  static bool _looksLikeSnapshotUrl(String content) {
    if (content.isEmpty) return false;
    final uri = Uri.tryParse(content);
    if (uri == null || uri.scheme != 'qaq' || uri.host != 'course-table' || uri.path != '/share') return false;
    try {
      if (uri.queryParameters['data']?.isNotEmpty != true) return false;
      // Older cloud snapshots did not carry fragment generation metadata.
      if (uri.fragment.isEmpty) return true;
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
      if (uri.scheme != CourseTableShareCodec.scheme ||
          uri.host != CourseTableShareCodec.host ||
          uri.path != CourseTableShareCodec.path) {
        throw const FormatException('Unexpected URL in course table cloud snapshot');
      }
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
      if (group.parts.containsKey(part) && group.parts[part] != trimmed) {
        throw const FormatException('Conflicting duplicate course table cloud fragment');
      }
      group.parts[part] = trimmed;
    }

    final completeGroups = groups.values.where((group) => group.isComplete).toList()
      ..sort((a, b) => b.generationValue.compareTo(a.generationValue));
    for (final group in completeGroups) {
      try {
        return _decodeCompleteSnapshot(List<String>.generate(group.total, (index) => group.parts[index + 1]!));
      } on FormatException {
        // A newer partial/corrupt commit must not hide a valid rollback copy.
      } catch (_) {
        // The older complete generation remains recoverable.
      }
    }

    if (legacy.isNotEmpty) return _decodeCompleteSnapshot(legacy);
    throw const FormatException('No complete course table cloud snapshot');
  }

  static List<CourseTableSharePerson> _decodeCompleteSnapshot(Iterable<String> urls) {
    final decoded = <CourseTableSharePerson>[];
    final parts = urls.toList(growable: false);
    for (final value in parts) {
      final payload = CourseTableShareCodec.decodeUrl(value.trim());
      final people = CourseTableSharePerson.fromPayload(payload);
      if (people.isEmpty) {
        if (parts.length != 1 || decoded.isNotEmpty) {
          throw const FormatException('Empty fragment mixed with course records');
        }
        return const <CourseTableSharePerson>[];
      }
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

/// Only constructed after successful remote discovery and content validation.
/// `people == null` means verified absence, not an empty snapshot tombstone.
class _VerifiedCloudSnapshot {
  const _VerifiedCloudSnapshot({required this.tasks, required this.signature, this.people, this.isCorrupt = false});

  final List<NPortalTaskRef> tasks;
  final List<CourseTableSharePerson>? people;
  final bool isCorrupt;
  final String signature;
}
