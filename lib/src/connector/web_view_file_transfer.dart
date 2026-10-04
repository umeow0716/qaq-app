import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_config.dart';

class AndroidBlobDownloadResult {
  const AndroidBlobDownloadResult({required this.filename, required this.bytes, required this.uri});

  final String filename;
  final int bytes;
  final String uri;
}

class WebViewFileTransfer {
  const WebViewFileTransfer._();

  static const MethodChannel _channel = MethodChannel(AppConfig.methodChannelName);

  static Future<List<String>> pickSystemFiles({
    required List<String> acceptTypes,
    required String mode,
    required bool capture,
    String? filenameHint,
  }) async {
    if (!Platform.isAndroid) return const <String>[];
    final result = await _channel.invokeListMethod<String>('pick_webview_files', <String, Object?>{
      'acceptTypes': acceptTypes,
      'mode': mode,
      'capture': capture,
      'filenameHint': filenameHint,
    });
    return result ?? const <String>[];
  }

  static Future<int> enqueueSystemDownload({
    required Uri requestUrl,
    required Uri sourceUrl,
    required String contentDisposition,
    required String mimeType,
    required String userAgent,
    String? cookie,
    String? referer,
    required bool keepAlive,
    String? filenameHint,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('System WebView downloads are currently implemented on Android only.');
    }

    final id = await _channel.invokeMethod<int>('enqueue_webview_download', <String, Object?>{
      'requestUrl': requestUrl.toString(),
      'sourceUrl': sourceUrl.toString(),
      'contentDisposition': contentDisposition,
      'mimeType': mimeType,
      'userAgent': userAgent,
      'cookie': cookie,
      'referer': referer,
      'keepAlive': keepAlive,
      'filenameHint': filenameHint,
    });
    if (id == null) throw StateError('Android DownloadManager did not return a download id.');
    return id;
  }

  static Future<String> beginBlobDownload({
    required String sourceUrl,
    required String contentDisposition,
    required String mimeType,
    required int totalBytes,
    String? filenameHint,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Blob WebView downloads are currently implemented on Android only.');
    }

    final token = await _channel.invokeMethod<String>('begin_webview_blob_download', <String, Object?>{
      'sourceUrl': sourceUrl,
      'contentDisposition': contentDisposition,
      'mimeType': mimeType,
      'totalBytes': totalBytes,
      'filenameHint': filenameHint,
    });
    if (token == null || token.isEmpty) {
      throw StateError('Android did not create a destination for the blob download.');
    }
    return token;
  }

  static Future<void> appendBlobDownloadChunk({required String token, required Uint8List bytes}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('append_webview_blob_download_chunk', <String, Object?>{
      'token': token,
      'bytes': bytes,
    });
  }

  static Future<AndroidBlobDownloadResult> finishBlobDownload(String token, {required String completionTitle}) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Blob WebView downloads are currently implemented on Android only.');
    }
    final result = await _channel.invokeMapMethod<String, Object?>('finish_webview_blob_download', <String, Object?>{
      'token': token,
      'completionTitle': completionTitle,
    });
    final filename = result?['filename'] as String?;
    final bytes = result?['bytes'] as int?;
    final uri = result?['uri'] as String?;
    if (filename == null || bytes == null || uri == null) {
      throw StateError('Android did not confirm the completed blob download.');
    }
    return AndroidBlobDownloadResult(filename: filename, bytes: bytes, uri: uri);
  }

  static Future<void> abortBlobDownload(String token) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('abort_webview_blob_download', <String, Object?>{'token': token});
  }
}
