import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/core/dio_connector.dart';
import 'package:qaq_app/src/file/webview_download_filename.dart';

const int _progressNotifyByteStep = 128 * 1024;

enum DesktopDownloadStatus { preparing, downloading, completed, failed }

class DesktopDownloadItem {
  DesktopDownloadItem({required this.id, required this.name});

  final int id;
  String name;
  int receivedBytes = 0;
  int totalBytes = -1;
  DesktopDownloadStatus status = DesktopDownloadStatus.preparing;
  String? savedPath;
  String? error;

  double? get progress {
    if (status == DesktopDownloadStatus.completed) return 1;
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }
}

/// Desktop-only material download queue.
///
/// Downloads intentionally reuse [DioConnector]. Its HTTP adapter already
/// routes iStudy/istudycloud requests through IStudyAccessGuard and the
/// GlobalProtect-backed HttpClient when required, so this queue must not create
/// a second raw HttpClient or bypass the existing proxy/VPN decision.
class DesktopDownloadManager extends ChangeNotifier {
  DesktopDownloadManager._();

  static final DesktopDownloadManager instance = DesktopDownloadManager._();

  final List<DesktopDownloadItem> _items = <DesktopDownloadItem>[];
  final Set<String> _reservedPaths = <String>{};
  int _sequence = 0;
  bool _panelVisible = false;

  List<DesktopDownloadItem> get items => List<DesktopDownloadItem>.unmodifiable(_items);
  bool get panelVisible => _panelVisible && _items.isNotEmpty;

  void clearPanel() {
    if (_items.isEmpty && !_panelVisible) return;
    _items.clear();
    _panelVisible = false;
    notifyListeners();
  }

  Future<void> download({required String url, required String suggestedName, String? referer}) async {
    final item = DesktopDownloadItem(
      id: ++_sequence,
      name: sanitizeWebViewDownloadFilename(suggestedName, fallback: 'download'),
    );
    _items.insert(0, item);
    _panelVisible = true;
    notifyListeners();

    String? reservedPath;
    var lastNotifiedBytes = 0;
    final cancelToken = CancelToken();

    try {
      final downloadsDirectory = await _downloadsDirectory();
      await downloadsDirectory.create(recursive: true);

      await DioConnector.instance.download(
        url,
        (headers) {
          final filename = _resolveFilename(headers: headers, url: url, suggestedName: suggestedName);
          final destination = _reserveAvailablePath(downloadsDirectory, filename);
          reservedPath = destination;
          item
            ..name = path.basename(destination)
            ..savedPath = destination
            ..status = DesktopDownloadStatus.downloading;
          notifyListeners();
          return destination;
        },
        progressCallback: (received, total) {
          item
            ..receivedBytes = received
            ..totalBytes = total
            ..status = DesktopDownloadStatus.downloading;

          final finished = total > 0 && received >= total;
          if (finished || received - lastNotifiedBytes >= _progressNotifyByteStep) {
            lastNotifiedBytes = received;
            notifyListeners();
          }
        },
        cancelToken: cancelToken,
        header: <String, dynamic>{'referer': referer ?? url},
      );

      item.status = DesktopDownloadStatus.completed;
      notifyListeners();
    } catch (error, stackTrace) {
      item
        ..status = DesktopDownloadStatus.failed
        ..error = error.toString();
      Log.eWithStack('Desktop material download failed: $error', stackTrace);
      notifyListeners();
    } finally {
      if (reservedPath != null) _reservedPaths.remove(reservedPath);
    }
  }

  Future<Directory> _downloadsDirectory() async {
    final directory = await getDownloadsDirectory();
    if (directory != null) return directory;

    final home = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory(path.join(home, 'Downloads'));
    }

    return getApplicationDocumentsDirectory();
  }

  String _reserveAvailablePath(Directory directory, String filename) {
    final safeName = sanitizeWebViewDownloadFilename(filename, fallback: 'download');
    final extension = path.extension(safeName);
    final stem = extension.isEmpty ? safeName : safeName.substring(0, safeName.length - extension.length);

    for (var index = 0; index < 10000; index++) {
      final candidateName = index == 0 ? safeName : '$stem ($index)$extension';
      final candidate = path.join(directory.path, candidateName);
      if (_reservedPaths.contains(candidate) || File(candidate).existsSync()) continue;
      _reservedPaths.add(candidate);
      return candidate;
    }

    throw StateError('Unable to allocate a download filename for $safeName');
  }

  String _resolveFilename({required Headers headers, required String url, required String suggestedName}) {
    var base = sanitizeWebViewDownloadFilename(suggestedName, fallback: 'download');
    if (path.extension(base).isNotEmpty) return base;

    final disposition = headers.value(HttpHeaders.contentDisposition);
    final dispositionName = _contentDispositionFilename(disposition);
    final dispositionExtension = dispositionName == null ? '' : path.extension(dispositionName);
    if (dispositionExtension.isNotEmpty) {
      return sanitizeWebViewDownloadFilename('$base$dispositionExtension');
    }

    final urlName = Uri.tryParse(url)?.pathSegments.lastOrNull;
    final urlExtension = urlName == null ? '' : path.extension(urlName);
    if (urlExtension.isNotEmpty) {
      return sanitizeWebViewDownloadFilename('$base$urlExtension');
    }

    final contentType = headers.value(HttpHeaders.contentTypeHeader)?.toLowerCase() ?? '';
    if (contentType.contains('pdf')) return '$base.pdf';
    if (contentType.contains('zip')) return '$base.zip';
    return base;
  }

  String? _contentDispositionFilename(String? disposition) {
    if (disposition == null || disposition.isEmpty) return null;

    final extended = RegExp(
      r"filename\*\s*=\s*(?:UTF-8''|utf-8'')?([^;]+)",
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1)?.trim();
    if (extended != null && extended.isNotEmpty) {
      final unquoted = _stripQuotes(extended);
      try {
        return Uri.decodeComponent(unquoted);
      } on FormatException {
        return unquoted;
      }
    }

    final plain = RegExp(
      r"""filename\s*=\s*("[^"]*"|'[^']*'|[^;]+)""",
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1)?.trim();
    return plain == null ? null : _stripQuotes(plain);
  }

  String _stripQuotes(String value) {
    if (value.length < 2) return value;
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
