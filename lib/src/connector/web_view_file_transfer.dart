import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_config.dart';

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
    });
    if (id == null) throw StateError('Android DownloadManager did not return a download id.');
    return id;
  }
}
