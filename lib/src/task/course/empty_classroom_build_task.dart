import 'dart:async';

import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/core/network_request_pool.dart';
import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/coursetable/empty_classroom_cache.dart';
import 'package:qaq_app/src/store/local_storage.dart';

typedef EmptyClassroomBuildProgress = void Function(int completed, int total);

class EmptyClassroomBuildTask {
  const EmptyClassroomBuildTask._();

  static Future<EmptyClassroomCacheJson?> build({
    required SemesterJson semester,
    required bool forceRebuild,
    EmptyClassroomBuildProgress? onProgress,
  }) async {
    final storage = LocalStorage.instance;
    const language = 'zh';
    var cache = storage.getEmptyClassroomCache(semester, language);

    if (cache != null && cache.complete && !forceRebuild) {
      onProgress?.call(cache.rooms.length, cache.rooms.length);
      return cache;
    }

    if (cache == null || forceRebuild || cache.rooms.isEmpty) {
      final rooms = await CourseConnector.getClassroomList(semester, timeout: NetworkRequestPool.shared.timeout);
      if (rooms == null || rooms.isEmpty) {
        if (forceRebuild && cache != null) {
          throw StateError('Unable to refresh classroom master list');
        }
        return cache;
      }

      // For an explicit refresh, do not discard the old cache until the new
      // master room list has been fetched successfully.
      cache = EmptyClassroomCacheJson(
        year: semester.year,
        semester: semester.semester,
        language: language,
        complete: false,
        updatedAt: DateTime.now(),
        rooms: rooms,
      );
      await storage.setEmptyClassroomCache(cache);
    }

    final pendingIndexes = <int>[];
    for (var index = 0; index < cache.rooms.length; index++) {
      if (!cache.rooms[index].built) pendingIndexes.add(index);
    }

    final total = cache.rooms.length;
    var completed = cache.builtCount;
    onProgress?.call(completed, total);
    if (pendingIndexes.isEmpty) {
      cache.complete = cache.rooms.isNotEmpty && cache.rooms.every((room) => room.built);
      cache.updatedAt = DateTime.now();
      await storage.setEmptyClassroomCache(cache);
      return cache;
    }

    Future<void> persistQueue = Future<void>.value();
    var completionsSincePersist = 0;

    void queuePersist() {
      persistQueue = persistQueue.then((_) => storage.saveEmptyClassroomCache()).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        Log.eWithStack('Empty classroom cache persist failed: $error', stackTrace);
      });
    }

    await NetworkRequestPool.shared.run<EmptyClassroomRoomJson>(
      pendingIndexes.map(
        (index) =>
            (timeout) => CourseConnector.getEmptyClassroomSchedule(cache!.rooms[index], timeout: timeout),
      ),
      shouldRetry: (room) => room == null || !room.built,
      onComplete: (jobIndex, result) {
        final roomIndex = pendingIndexes[jobIndex];
        if (result != null && result.built) {
          cache!.rooms[roomIndex] = result;
        }
        completed++;
        completionsSincePersist++;
        onProgress?.call(completed, total);

        // Persist once per connection wave. If the app is interrupted, at
        // most one wave is repeated on the next visit instead of rebuilding
        // the entire semester.
        if (completionsSincePersist >= NetworkRequestPool.shared.maxConnections) {
          completionsSincePersist = 0;
          cache!.updatedAt = DateTime.now();
          queuePersist();
        }
      },
    );

    await persistQueue;
    cache.complete = cache.rooms.isNotEmpty && cache.rooms.every((room) => room.built);
    cache.updatedAt = DateTime.now();
    await storage.setEmptyClassroomCache(cache);
    return cache;
  }
}
