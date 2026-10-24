import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:qaq_app/src/connector/core/network_request_pool.dart';
import 'package:qaq_app/src/connector/network.dart';

class NPortalTaskRef {
  const NPortalTaskRef({required this.id, required this.subject});

  final String id;
  final String subject;
}

class NPortalTaskConnector {
  static const String _host = 'https://nportal.ntut.edu.tw/';
  static const String _taskListUrl = '${_host}task5List.do';
  static const String _taskListNextUrl = '${_host}taskListNext.do';
  static const String _taskShowUrl = '${_host}task5Show.do';
  static const String _taskEditUrl = '${_host}task5Edit.do';
  static const String _taskSaveUrl = '${_host}taskSave.do?';
  static const String _taskDeleteUrl = '${_host}taskDel.do';
  static const String _deadlineDate = '2031-12-31';
  static const String _createDeadlineTime = '23:59';
  static const String _editDeadlineTime = '11:59';
  static const String _createDeadline = '$_deadlineDate $_createDeadlineTime';
  static const String _editDeadline = '$_deadlineDate $_editDeadlineTime';
  static const String _completedStatus = '100';
  static const int _maxListPages = 50;

  static Future<List<NPortalTaskRef>> findTasksBySubject(String subject) async {
    final normalizedSubject = subject.trim();
    if (normalizedSubject.isEmpty) return const <NPortalTaskRef>[];

    // Cloud snapshots are authoritative only when they are private completed
    // tasks. Unfinished/processing tasks are deliberately ignored: they may be
    // abandoned staging writes from an interrupted copy-on-write commit, and
    // are never needed to recover the last complete generation.
    return _findTasksBySubjectState(normalizedSubject, _completedStatus);
  }

  static Future<List<NPortalTaskRef>> _findTasksBySubjectState(
    String subject,
    String state,
  ) async {
    final result = <NPortalTaskRef>[];
    final seenPageFingerprints = <String>{};
    final firstPage = await NetworkRequestPool.shared.execute<String>(
      (timeout) async {
        final response = await dio.get<String>(
          _taskListUrl,
          queryParameters: <String, String>{
            'type': '3',
            'state': state,
            'name': 'sendDate',
            'mode': 'desc',
            'key': '0',
            'page': '1',
            'creator': '',
            'sortShow': 'sendDate:desc',
          },
          options: _portalOptions(timeout: timeout),
        );
        return response.data;
      },
      shouldRetry: (value) => value == null || value.trim().isEmpty,
    );
    if (firstPage == null) {
      throw StateError('Unable to load nPortal task list for state $state');
    }
    final mobileMatches = _parseMobileTaskGroups(firstPage, subject, state);
    if (mobileMatches != null) {
      final deduped = _dedupeTaskRefs(mobileMatches);
      return deduped;
    }

    final firstMatches = _parseFirstPage(firstPage, subject);
    result.addAll(firstMatches);

    // Probe two pages serially first. nPortal has been observed to repeat the
    // final non-empty page for out-of-range page numbers; this detects that
    // cheaply instead of speculatively firing a full parallel batch.
    var nextPage = 2;
    for (var probe = 0; probe < 2 && nextPage <= _maxListPages; probe++, nextPage++) {
      final pageData = await NetworkRequestPool.shared.execute<List<dynamic>>(
        (timeout) => _fetchTaskListPage(nextPage, state, timeout),
      );
      if (pageData == null) {
        throw StateError('Unable to load nPortal task list page $nextPage for state $state');
      }
      if (!_consumeTaskListPage(pageData, subject, result, seenPageFingerprints)) {
        final deduped = _dedupeTaskRefs(result);
        return deduped;
      }
    }

    // Once pagination is proven to advance, fetch the remaining pages in
    // shared-pool batches. This uses the same 8-connection / 5s timeout /
    // 1-retry / 200ms retry-delay policy as score and imported-course loading.
    while (nextPage <= _maxListPages) {
      final batchSize = NetworkRequestPool.shared.maxConnections;
      final batchEnd = (nextPage + batchSize - 1) > _maxListPages
          ? _maxListPages
          : nextPage + batchSize - 1;
      final pages = <int>[for (var page = nextPage; page <= batchEnd; page++) page];
      final batch = await NetworkRequestPool.shared.run<List<dynamic>>(
        pages.map((page) => (timeout) => _fetchTaskListPage(page, state, timeout)),
      );

      var stop = false;
      for (var index = 0; index < batch.length; index++) {
        final pageData = batch[index];
        if (pageData == null) {
          throw StateError('Unable to load nPortal task list page ${pages[index]} for state $state');
        }
        if (!_consumeTaskListPage(pageData, subject, result, seenPageFingerprints)) {
          stop = true;
          break;
        }
      }
      if (stop) break;
      nextPage = batchEnd + 1;
    }

    final deduped = _dedupeTaskRefs(result);
    return deduped;
  }

  static Future<List<dynamic>?> _fetchTaskListPage(
    int page,
    String state,
    Duration timeout,
  ) async {
    final response = await dio.get<dynamic>(
      _taskListNextUrl,
      queryParameters: <String, String>{
        'type': '3',
        'state': state,
        'name': 'sendDate',
        'mode': 'desc',
        'key': '0',
        'creator': '',
        'page': '$page',
      },
      options: _portalOptions(responseType: ResponseType.json, timeout: timeout),
    );
    final data = response.data;
    final list = data is List ? List<dynamic>.from(data) : null;
    return list;
  }

  static bool _consumeTaskListPage(
    List<dynamic> pageData,
    String subject,
    List<NPortalTaskRef> result,
    Set<String> seenPageFingerprints,
  ) {
    if (pageData.isEmpty) {
      return false;
    }

    final fingerprint = pageData.map((item) {
      if (item is! Map) return item.toString();
      return '${item['id'] ?? ''}|${item['subject'] ?? ''}';
    }).join('\\u0001');
    if (!seenPageFingerprints.add(fingerprint)) {
      return false;
    }

    for (final item in pageData) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString().trim();
      final itemSubject = (item['subject'] ?? '').toString().trim();
      if (id.isNotEmpty && itemSubject == subject) {
        result.add(NPortalTaskRef(id: id, subject: itemSubject));
      }
    }
    return true;
  }

  static List<NPortalTaskRef> _dedupeTaskRefs(Iterable<NPortalTaskRef> tasks) {
    final seen = <String>{};
    return tasks.where((task) => seen.add(task.id)).toList(growable: false);
  }

  static Future<String?> getTaskContent(String id, {Duration? timeout}) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return null;

    final response = await dio.get<String>(
      _taskShowUrl,
      queryParameters: <String, String>{'id': normalizedId},
      options: _portalOptions(timeout: timeout),
    );
    final source = response.data ?? '';
    final mobileContent = _parseMobileTaskContent(source);
    if (mobileContent.found) {
      final content = mobileContent.content?.trim() ?? '';
      return content.isEmpty ? null : content;
    }

    final document = html.parse(source);
    final frame = document.querySelector('.content-frame');
    if (frame == null) {
      throw StateError('nPortal task content frame is unavailable');
    }
    final content = frame.text.trim();
    return content.isEmpty ? null : content;
  }

  static Future<String?> getDefaultTargetDn() async {
    final response = await dio.get<String>(
      _taskEditUrl,
      queryParameters: const <String, String>{'id': ''},
      options: _portalOptions(),
    );
    final document = html.parse(response.data ?? '');
    final targetDn = document.querySelector('input[name="targetDn"]')?.attributes['value']?.trim();
    return (targetDn == null || targetDn.isEmpty) ? null : targetDn;
  }

  static Future<bool> createTask({
    required String subject,
    required String content,
    required String targetDn,
  }) async {
    final response = await dio.post<String>(
      _taskSaveUrl,
      data: <String, String>{
        'taskSubject': subject,
        'taskType': '3',
        'taskPriority': '3',
        'date': _deadlineDate,
        'time': _createDeadlineTime,
        'taskModify': '1',
        'targetDn': targetDn,
        'taskContent': content,
        'delImages': '',
        'id': '',
        'taskDeadline': _createDeadline,
        'taskStatus': '0',
      },
      options: _portalOptions(),
    );
    final success = _saveSucceeded(response.data);
    return success;
  }

  static Future<bool> updateTask({
    required String id,
    required String subject,
    required String content,
  }) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return false;

    final response = await dio.post<String>(
      _taskSaveUrl,
      data: <String, String>{
        'taskSubject': subject,
        'taskType': '3',
        'taskPriority': '3',
        'date': _deadlineDate,
        'time': _editDeadlineTime,
        'taskStatus': _completedStatus,
        'taskContent': content,
        'delImages': '',
        'id': normalizedId,
        'taskDeadline': _editDeadline,
      },
      options: _portalOptions(),
    );
    final editSuccess = _saveSucceeded(response.data);
    if (!editSuccess) return false;

    // nPortal's full edit flow has been observed to reset a completed task back
    // to unfinished even when taskStatus=100 is included in the edit payload.
    // Its own frontend exposes a dedicated status mutation that posts only id +
    // taskStatus, so enforce the final state through that path after every edit.
    final statusSuccess = await setTaskCompleted(normalizedId);
    return statusSuccess;
  }

  static Future<bool> setTaskCompleted(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return false;

    final response = await dio.post<String>(
      _taskSaveUrl,
      data: <String, String>{
        'id': normalizedId,
        'taskStatus': _completedStatus,
      },
      options: _portalOptions(),
    );
    final success = _saveSucceeded(response.data, allowEmpty: true);
    return success;
  }

  static Future<void> deleteTask(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return;
    final response = await dio.post<String>(
      _taskDeleteUrl,
      data: <String, String>{'id': normalizedId},
      options: _portalOptions(),
    );
    final success = _saveSucceeded(response.data, allowEmpty: true);
    if (!success) throw StateError('nPortal rejected task deletion for $normalizedId');
  }

  static List<NPortalTaskRef>? _parseMobileTaskGroups(
    String source,
    String subject,
    String state,
  ) {
    final value = source.trim();
    if (!value.startsWith('[')) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(value);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;

    var groupedShape = false;
    final result = <NPortalTaskRef>[];
    for (final group in decoded) {
      if (group is! Map) continue;
      final taskList = group['taskList'];
      if (taskList is! List) continue;
      groupedShape = true;

      // Mobile nPortal returns all category groups even when type=3 is sent.
      // Enforce the cloud-sync ownership rule client-side as well.
      final typeId = (group['typeId'] ?? '').toString().trim();
      if (typeId != '3') continue;

      for (final item in taskList) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString().trim();
        final itemSubject = (item['subject'] ?? '').toString().trim();
        final itemStatus = (item['status'] ?? '').toString().trim();
        if (id.isNotEmpty && itemSubject == subject && itemStatus == state) {
          result.add(NPortalTaskRef(id: id, subject: itemSubject));
        }
      }
    }
    return groupedShape ? result : null;
  }

  static ({bool found, String? content}) _parseMobileTaskContent(String source) {
    final value = source.trim();
    if (!value.startsWith('{')) return (found: false, content: null);

    dynamic decoded;
    try {
      decoded = jsonDecode(value);
    } catch (_) {
      return (found: false, content: null);
    }
    if (decoded is! Map || !decoded.containsKey('content')) {
      return (found: false, content: null);
    }
    final rawContent = decoded['content'];
    return (found: true, content: rawContent?.toString());
  }

  static List<NPortalTaskRef> _parseFirstPage(String source, String subject) {
    final document = html.parse(source);
    final result = <NPortalTaskRef>[];
    final idPattern = RegExp(r'''taskShow\(["'](\d+)["']\)''');

    final anchors = document.querySelectorAll('a[onclick]');
    var taskShowAnchors = 0;
    for (final anchor in anchors) {
      final match = idPattern.firstMatch(anchor.attributes['onclick'] ?? '');
      if (match == null) continue;
      taskShowAnchors++;
      final itemSubject = anchor.children.isNotEmpty ? anchor.children.first.text.trim() : anchor.text.trim();
      if (itemSubject != subject) continue;
      final id = match.group(1)?.trim() ?? '';
      if (id.isNotEmpty) result.add(NPortalTaskRef(id: id, subject: itemSubject));
    }
    return result;
  }

  static bool _saveSucceeded(String? body, {bool allowEmpty = false}) {
    final value = body?.trim() ?? '';
    if (value.isEmpty) return allowEmpty;

    try {
      final decoded = jsonDecode(value);
      if (decoded is Map && decoded['success'] is bool) {
        return decoded['success'] == true;
      }
    } catch (_) {
      // Browser-mode nPortal may return plain text such as "儲存成功。".
    }

    if (value.toLowerCase().contains('<html')) return false;
    // Browser-mode task5 treats non-numeric text as success; numeric text is
    // the recipient-limit error. Mobile-mode JSON is handled above.
    return num.tryParse(value) == null;
  }

  static Options _portalOptions({ResponseType? responseType, Duration? timeout}) => Options(
    responseType: responseType,
    connectTimeout: timeout,
    receiveTimeout: timeout,
    sendTimeout: timeout,
    contentType: Headers.formUrlEncodedContentType,
    headers: const <String, String>{'referer': '${_host}taskMain.do?'},
  );
}
