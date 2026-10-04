import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qaq_app/src/connector/adapters/early_interceptor_adapter.dart';
import 'package:qaq_app/src/connector/core/dio_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_app_session.dart';
import 'package:qaq_app/src/connector/web_view_cookie_store.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_debug.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy_controller.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_runtime.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/file/webview_download_filename.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/ui/pages/webview/web_view_button_bar.dart';
import 'package:webview_all/webview_all.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_all_linux/webview_all_linux.dart' as linux_webview;
// ignore: depend_on_referenced_packages
import 'package:webview_all_windows/webview_all_windows.dart' as windows_webview;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class QAQWebViewDesktop extends StatefulWidget {
  const QAQWebViewDesktop({super.key, required this.initialUrl, this.title});

  final Uri initialUrl;
  final String? title;

  @override
  State<QAQWebViewDesktop> createState() => _QAQWebViewDesktopState();
}

class _QAQWebViewDesktopState extends State<QAQWebViewDesktop> {
  final cookieJar = DioConnector.instance.cookiesManager;
  WebViewController? _controller;
  late final Future<void> _initialLoadFuture;
  static const _linuxNativeWebViewMountDelay = Duration(milliseconds: 220);
  static const _linuxNativeWebViewDetachDelay = Duration(milliseconds: 32);

  bool _vpnProxyEnabled = false;
  bool _windowsProxyEnvironmentPrepared = false;
  bool _showNativeWebView = !Platform.isLinux;
  bool _allowNextLinuxPop = false;
  bool _linuxNativeWebViewDetachedForPop = false;
  var _downloadOverlaySequence = 0;

  final progress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _initialLoadFuture = _prepareControllerAndLoadInitialContent();
    if (Platform.isLinux) {
      unawaited(_showLinuxNativeWebViewAfterRouteTransition());
    }
  }

  @override
  void dispose() {
    if (_vpnProxyEnabled) {
      unawaited(_clearWebViewProxy());
    }
    progress.dispose();
    super.dispose();
  }

  WebViewController get _requiredController {
    final controller = _controller;
    if (controller == null) {
      throw StateError('WebViewController was used before desktop WebView preparation completed.');
    }
    return controller;
  }

  Future<void> _showLinuxNativeWebViewAfterRouteTransition() async {
    await Future<void>.delayed(_linuxNativeWebViewMountDelay);
    if (!mounted || _linuxNativeWebViewDetachedForPop) return;

    setState(() {
      _showNativeWebView = true;
    });
  }

  Future<bool> _handleRouteWillPop() async {
    if (!Platform.isLinux) return true;
    if (_allowNextLinuxPop) return true;

    unawaited(_popAfterDetachingLinuxNativeWebView());
    return false;
  }

  Future<void> _popAfterDetachingLinuxNativeWebView() async {
    if (!mounted) return;

    _allowNextLinuxPop = true;
    if (!_linuxNativeWebViewDetachedForPop) {
      _linuxNativeWebViewDetachedForPop = true;
      if (_showNativeWebView) {
        setState(() {
          _showNativeWebView = false;
        });
        await Future<void>.delayed(_linuxNativeWebViewDetachDelay);
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> _prepareControllerAndLoadInitialContent() async {
    // WebView2 environment options are process-scoped and immutable after the
    // first Windows controller is created. Install the destination-aware
    // loopback proxy before that first controller exists; VPN routing itself
    // remains disabled until IStudyAccessGuard selects the VPN route.
    await _prepareWindowsWebViewProxyEnvironment();

    final content = await _prepareInitialContent();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(_createNavigationDelegate());
    await _configureLinuxFileTransfer(controller);
    await _configureWindowsFileTransfer(controller);
    await _configureWindowsWebResourceDebug(controller);
    _controller = controller;
    await setInitialCookies();

    final initialUrl = content.initialUrl;
    if (initialUrl != null) {
      final initialHeaders = await _initialRequestHeadersForUri(initialUrl);
      await controller.loadRequest(initialUrl, headers: initialHeaders);
      return;
    }

    await controller.loadHtmlString(content.initialData ?? '');
  }

  Future<_InitialWebViewContent> _prepareInitialContent() async {
    if (!IStudyAccessGuard.isIStudyUri(widget.initialUrl)) {
      return _InitialWebViewContent.url(widget.initialUrl);
    }

    // Linux can still install its WebKitGTK proxy dynamically, so keep the
    // existing direct-iStudy preflight there. Windows has already fixed its
    // WebView2 environment above and only toggles bridge routing here.
    final preflightRoute = await _prepareLinuxVpnProxyBeforeWebViewEnvironment();
    final route = preflightRoute ?? await IStudyAccessGuard.route();
    GlobalProtectDebug.log('direct iStudy initial URL route=${route.name}');
    switch (route) {
      case IStudyAccessRoute.direct:
        return _InitialWebViewContent.url(widget.initialUrl);
      case IStudyAccessRoute.blocked:
        return _InitialWebViewContent.html(IStudyAccessGuard.blockedHtml);
      case IStudyAccessRoute.vpn:
        // Desktop WebView proxy support is intentionally not hidden behind a
        // fallback page yet. Let failures surface from the real runtime path.
        await _enableWebViewProxy();
        return _InitialWebViewContent.url(widget.initialUrl);
    }
  }

  Future<void> _prepareWindowsWebViewProxyEnvironment() async {
    if (!Platform.isWindows || _windowsProxyEnvironmentPrepared) return;

    final runtimeGeneration = GlobalProtectWebViewRuntime.generation;
    final port = await GlobalProtectWebViewProxyBridge.instance.ensureListening(
      vpnHosts: IStudyAccessGuard.proxyHosts,
    );
    if (!GlobalProtectWebViewRuntime.isCurrent(runtimeGeneration)) {
      throw StateError('WebView GlobalProtect runtime was reset before Windows WebView2 setup.');
    }

    await GlobalProtectWebViewProxyController.setProxyOverride(
      port: port,
      hosts: IStudyAccessGuard.proxyHosts,
    );
    if (!GlobalProtectWebViewRuntime.isCurrent(runtimeGeneration)) {
      await GlobalProtectWebViewRuntime.reset();
      throw StateError('WebView GlobalProtect runtime was reset during Windows WebView2 setup.');
    }

    _windowsProxyEnvironmentPrepared = true;
    GlobalProtectDebug.log(
      'Windows WebView2 proxy environment prepared on loopback port=$port; VPN routing disabled',
    );
  }

  Future<IStudyAccessRoute?> _prepareLinuxVpnProxyBeforeWebViewEnvironment() async {
    if (!Platform.isLinux) return null;

    final route = await IStudyAccessGuard.route();
    GlobalProtectDebug.log('Linux WebView preflight iStudy route=${route.name}');
    if (route == IStudyAccessRoute.vpn) {
      await _enableWebViewProxy();
    }
    return route;
  }

  Future<void> setInitialCookies() async {
    await WebViewCookieStore.clearAll();

    final portalUrl = Uri.parse(NTUTConnector.host);

    await _setCookiesForUri(portalUrl);

    if (_canCopyCookiesForUri(widget.initialUrl) && widget.initialUrl.host != portalUrl.host) {
      await _setCookiesForUri(widget.initialUrl);
    }
  }

  bool _canCopyCookiesForUri(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  Future<Map<String, String>> _initialRequestHeadersForUri(Uri uri) async {
    if (!Platform.isWindows || !_canCopyCookiesForUri(uri)) {
      return const <String, String>{};
    }

    final headers = <String, String>{};

    if (uri.host == Uri.parse(NTUTConnector.host).host) {
      final cookies = await cookieJar.loadForRequest(uri);
      if (cookies.isNotEmpty) {
        headers[HttpHeaders.cookieHeader] = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
        GlobalProtectDebug.log(
          '[WebViewCookieSync] Windows initial request Cookie header for ${uri.host}${uri.path}: '
          '${cookies.map((cookie) => cookie.name).join(',')}',
        );
      } else {
        GlobalProtectDebug.log('[WebViewCookieSync] Windows initial request has no Dio cookies for ${uri.host}${uri.path}');
      }
    }

    if (headers.isNotEmpty) {
      GlobalProtectDebug.log('[WebViewCookieSync] Windows initial request headers=${headers.keys.join(',')}');
    }
    return headers;
  }

  Future<void> _setCookiesForUri(Uri uri) async {
    final cookies = await cookieJar.loadForRequest(uri);
    for (final cookie in cookies) {
      await WebViewCookieStore.setCookie(url: uri, cookie: cookie);
    }

    if (kDebugMode && Platform.isWindows) {
      final sourceNames = cookies.map((cookie) => cookie.name).toSet();
      final webViewLabels = await WebViewCookieStore.debugLabels(uri);
      final webViewNames = webViewLabels.map((label) => label.split('@').first).toSet();
      final missingNames = sourceNames.difference(webViewNames).toList()..sort();

      debugPrint(
        '[WebViewCookieSync] copied ${uri.host}: '
        'dio=${sourceNames.toList()..sort()} '
        'webview=$webViewLabels '
        'missing=$missingNames',
      );
    }
  }

  Future<void> _configureWindowsWebResourceDebug(WebViewController controller) async {
    if (!kDebugMode || !Platform.isWindows) return;

    if (controller.webResourceCaptureSupport != WebResourceCaptureSupport.supported) {
      debugPrint('[WebViewNet] raw WebView2 request/response capture is unavailable');
      return;
    }

    await controller.setOnRawWebResourceRequest((request) {
      if (!_shouldTraceWebResource(request.uri)) return;
      _logRawWebResourceRequest('REQUEST', request);
    });

    await controller.setOnRawWebResourceResponse((request, response) {
      if (!_shouldTraceWebResource(request.uri) && !_shouldTraceWebResource(response.uri)) {
        return;
      }

      // WebView2 reports the request paired with WebResourceResponseReceived
      // after network-stack headers have been committed. This is the useful
      // snapshot for checking whether Cookie actually left the WebView.
      _logRawWebResourceRequest('COMMITTED', request);
      _logRawWebResourceResponse(response);
    });

    await controller.setWebResourceCaptureEnabled(true);
    debugPrint('[WebViewNet] raw WebView2 request/response capture enabled');
  }

  bool _shouldTraceWebResource(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;

    final host = uri.host.toLowerCase();
    return host == 'ntut.edu.tw' || host.endsWith('.ntut.edu.tw');
  }

  void _logRawWebResourceRequest(String stage, RawWebResourceRequest request) {
    final cookieHeader = _headerValue(request.headers, HttpHeaders.cookieHeader);
    final cookieNames = _requestCookieNames(cookieHeader);
    final referer = _safeHeaderUri(_headerValue(request.headers, HttpHeaders.refererHeader));
    final hasAuthorization = _headerValue(request.headers, HttpHeaders.authorizationHeader) != null;

    debugPrint(
      '[WebViewNet][$stage/${request.headerState.name}] '
      '${request.method ?? '<unknown>'} ${_safeWebResourceUri(request.uri)} '
      'cookies=$cookieNames '
      'referer=${referer ?? '<none>'} '
      'authorization=${hasAuthorization ? '<present>' : '<none>'}',
    );
  }

  void _logRawWebResourceResponse(RawWebResourceResponse response) {
    final setCookieHeader = _headerValue(response.headers, HttpHeaders.setCookieHeader);
    final setCookieNames = _responseCookieNames(setCookieHeader);
    final location = _safeHeaderUri(_headerValue(response.headers, HttpHeaders.locationHeader));
    final contentType = _headerValue(response.headers, HttpHeaders.contentTypeHeader);

    debugPrint(
      '[WebViewNet][RESPONSE] ${response.statusCode} '
      '${_safeWebResourceUri(response.uri)} '
      'location=${location ?? '<none>'} '
      'set-cookie=$setCookieNames '
      'content-type=${contentType ?? '<none>'}',
    );
  }

  String _safeWebResourceUri(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '<unknown>';

    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  String? _safeHeaderUri(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '<present>';
    return _safeWebResourceUri(uri);
  }

  String? _headerValue(Map<String, String> headers, String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
    }
    return null;
  }

  List<String> _requestCookieNames(String? header) {
    if (header == null || header.isEmpty) return const <String>[];

    final names = <String>{};
    for (final part in header.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      names.add(part.substring(0, separator).trim());
    }
    return names.toList()..sort();
  }

  List<String> _responseCookieNames(String? header) {
    if (header == null || header.isEmpty) return const <String>[];

    final names = <String>{};
    final cookieStart = RegExp(r'(?:^|[\r\n,]\s*)([^=;,\s]+)=');
    for (final match in cookieStart.allMatches(header)) {
      final name = match.group(1);
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return names.toList()..sort();
  }

  void _onProgressChanged(int webViewProgress) {
    progress.value = webViewProgress / 100.0;
  }

  NavigationDelegate _createNavigationDelegate() => NavigationDelegate(
    onProgress: _onProgressChanged,
    onNavigationRequest: _onNavigationRequest,
    onPageStarted: _onPageStarted,
    onPageFinished: (url) => unawaited(_onPageFinished(url)),
  );


  Future<void> _configureWindowsFileTransfer(WebViewController controller) async {
    if (!Platform.isWindows) return;

    final platformController = controller.platform;
    if (platformController is! windows_webview.WindowsWebViewController) {
      GlobalProtectDebug.log(
        'Windows WebView file transfer unavailable: ${platformController.runtimeType}',
      );
      return;
    }

    await platformController.setDownloadsEnabled(true);
    platformController.setOnDownloadStart((request) {
      unawaited(_trackWindowsDownload(request));
    });
    GlobalProtectDebug.log(
      'Windows WebView download callback attached; native WebView2 download progress will be mirrored in-page',
    );
  }

  Future<void> _trackWindowsDownload(
    windows_webview.WindowsDownloadStartRequest request,
  ) async {
    final resultFilePath = request.resultFilePath?.trim();
    if (resultFilePath == null || resultFilePath.isEmpty) {
      GlobalProtectDebug.log(
        'Windows WebView download started without a result file path: ${request.url}',
      );
      return;
    }

    final destination = File(resultFilePath);
    final overlayId = ++_downloadOverlaySequence;
    final reportedTotal = request.totalBytesToReceive;
    final total = reportedTotal != null && reportedTotal > 0 ? reportedTotal : -1;
    final displayFilename = sanitizeWebViewDownloadFilename(path.basename(resultFilePath));
    await _showDownloadOverlayItem(
      id: overlayId,
      filename: displayFilename,
      filePath: resultFilePath,
    );

    GlobalProtectDebug.log(
      'Windows WebView download tracking ${request.url} -> $resultFilePath total=$total',
    );

    var lastReceived = -1;
    var stableUnknownSizePolls = 0;
    try {
      while (mounted) {
        var exists = false;
        int? received;
        try {
          exists = await destination.exists();
          if (exists) received = await destination.length();
        } on FileSystemException {
          // WebView2 may briefly hold the destination without allowing a
          // concurrent stat/read. Keep the native download running and retry.
        }

        if (received != null && received != lastReceived) {
          lastReceived = received;
          stableUnknownSizePolls = 0;
          _updateDownloadOverlayProgress(
            id: overlayId,
            received: received,
            total: total,
          );
        } else if (received != null && received > 0 && total < 0) {
          stableUnknownSizePolls++;
        }

        if (received != null && total > 0 && received >= total) {
          break;
        }
        // WebView2 reports an unknown total when Content-Length is unavailable.
        // Its current public Dart callback only exposes download start, so use a
        // conservative five-second stable-file window as the completion fallback.
        if (exists && received != null && received > 0 && total < 0 && stableUnknownSizePolls >= 20) {
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      if (!mounted) return;
      final completedDestination = await _normalizeWindowsDownloadFilename(destination);
      await _finishDownloadOverlayItem(
        id: overlayId,
        status: _DownloadOverlayStatus.completed,
        filename: path.basename(completedDestination.path),
        filePath: completedDestination.path,
      );
      GlobalProtectDebug.log('Windows WebView download completed ${completedDestination.path}');
    } catch (error, stackTrace) {
      if (mounted) {
        await _finishDownloadOverlayItem(
          id: overlayId,
          status: _DownloadOverlayStatus.failed,
          message: error.toString(),
        );
      }
      GlobalProtectDebug.error('Windows WebView download progress', error, stackTrace);
    }
  }

  Future<File> _normalizeWindowsDownloadFilename(File destination) async {
    if (!await destination.exists()) return destination;

    final originalName = path.basename(destination.path);
    final safeName = sanitizeWebViewDownloadFilename(originalName);
    if (safeName == originalName) return destination;

    final safeDestination = await _nextAvailableDownloadFile(destination.parent, safeName);
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await destination.rename(safeDestination.path);
      } on FileSystemException catch (error, stackTrace) {
        if (attempt == 7) {
          GlobalProtectDebug.error('Windows WebView download filename normalization', error, stackTrace);
          return destination;
        }
        await Future<void>.delayed(const Duration(milliseconds: 125));
      }
    }
    return destination;
  }

  Future<void> _configureLinuxFileTransfer(WebViewController controller) async {
    if (!Platform.isLinux) return;

    final platformController = controller.platform;
    if (platformController is! linux_webview.LinuxWebViewController) {
      GlobalProtectDebug.log(
        'Linux WebView file transfer unavailable: ${platformController.runtimeType}',
      );
      return;
    }

    await platformController.setDownloadsEnabled(true);
    // Let WebKitGTK handle <input type=file> with its native GTK file chooser.
    // Ubuntu 24.04/GNOME can crash when the custom Dart file selector callback
    // is bridged through WebKitGTK; the native chooser keeps upload testing in
    // the app WebView without crossing into that unstable callback path.
    platformController.setOnDownloadStart((request) {
      unawaited(_handleLinuxDownload(request));
    });
    GlobalProtectDebug.log('Linux WebView download callback attached; upload uses native file chooser');
  }

  Future<void> _handleLinuxDownload(
    linux_webview.LinuxDownloadStartRequest request,
  ) async {
    final sourceUri = Uri.tryParse(request.url);
    if (sourceUri == null || (sourceUri.scheme != 'http' && sourceUri.scheme != 'https')) {
      GlobalProtectDebug.log('ignoring unsupported Linux WebView download URL: ${request.url}');
      return;
    }

    int? overlayId;

    try {
      final downloadsDirectory = await _linuxDownloadsDirectory();
      final filename = _linuxDownloadFilename(request, sourceUri);
      final destination = await _nextAvailableDownloadFile(downloadsDirectory, filename);
      overlayId = ++_downloadOverlaySequence;
      await _showDownloadOverlayItem(
        id: overlayId,
        filename: path.basename(destination.path),
        filePath: destination.path,
      );

      final referer = await _requiredController.currentUrl();
      final cookieHeader = await WebViewCookieStore.cookieHeaderFor(sourceUri);
      final userAgent = DioConnector.instance.headers[HttpHeaders.userAgentHeader];
      final headers = <String, dynamic>{
        if (userAgent != null && userAgent.isNotEmpty) HttpHeaders.userAgentHeader: userAgent,
        if (referer != null && referer.isNotEmpty) HttpHeaders.refererHeader: referer,
        if (cookieHeader != null && cookieHeader.isNotEmpty) HttpHeaders.cookieHeader: cookieHeader,
      };

      var lastOverlayPercent = -1;
      var showedUnknownOverlayProgress = false;

      GlobalProtectDebug.log('Linux WebView download saving ${sourceUri.host} to ${destination.path}');
      await _downloadLinuxWebViewFile(
        sourceUri: sourceUri,
        destination: destination,
        headers: headers,
        onProgress: (received, total) {
          final currentOverlayId = overlayId;
          if (currentOverlayId == null) return;
          if (total > 0) {
            final percent = ((received / total) * 100).clamp(0, 100).floor();
            if (percent == lastOverlayPercent && percent < 100) return;
            lastOverlayPercent = percent;
          } else {
            if (showedUnknownOverlayProgress) return;
            showedUnknownOverlayProgress = true;
          }
          _updateDownloadOverlayProgress(
            id: currentOverlayId,
            received: received,
            total: total,
          );
        },
      );
      await _finishDownloadOverlayItem(
        id: overlayId,
        status: _DownloadOverlayStatus.completed,
      );
      GlobalProtectDebug.log('Linux WebView download saved ${destination.path}');
    } catch (error, stackTrace) {
      final currentOverlayId = overlayId;
      if (currentOverlayId != null) {
        await _finishDownloadOverlayItem(
          id: currentOverlayId,
          status: _DownloadOverlayStatus.failed,
          message: error.toString(),
        );
      }
      GlobalProtectDebug.error('Linux WebView download', error, stackTrace);
    }
  }

  Future<void> _downloadLinuxWebViewFile({
    required Uri sourceUri,
    required File destination,
    required Map<String, dynamic> headers,
    required void Function(int received, int total) onProgress,
  }) async {
    final dio = Dio(DioConnector.dioOptions)
      ..httpClientAdapter = EarlyInterceptorAdapter(
        headerDecorators: DioConnector.headerDecorators,
        httpClientProvider: (options) async {
          if (!IStudyAccessGuard.isIStudyUri(options.uri)) return null;

          final route = await IStudyAccessGuard.route();
          GlobalProtectDebug.log('Linux WebView download iStudy route=${route.name}');
          switch (route) {
            case IStudyAccessRoute.direct:
              return null;
            case IStudyAccessRoute.blocked:
              throw const IStudyAccessBlockedException();
            case IStudyAccessRoute.vpn:
              GlobalProtectDebug.log('Linux WebView download requesting GP-backed HttpClient');
              return (await GlobalProtectAppSession.instance.ensureHttpClient()).client;
          }
        },
      );

    try {
      await dio.downloadUri(
        sourceUri,
        destination.path,
        options: Options(
          receiveTimeout: Duration.zero,
          headers: headers,
        ),
        onReceiveProgress: (received, total) {
          onProgress(received, total);
          if (total > 0 && received == total) {
            GlobalProtectDebug.log('Linux WebView download received $received bytes');
          }
        },
        cancelToken: CancelToken(),
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _showDownloadOverlayItem({
    required int id,
    required String filename,
    required String filePath,
  }) async {
    await _runDownloadOverlayScript(
      _downloadOverlayBootstrapScript() +
          _downloadOverlayCallScript(
            method: 'show',
            payload: {
              'id': id,
              'filename': filename,
              'path': filePath,
              'percent': 0,
              'status': 'downloading',
              'statusText': R.current.prepareDownload,
            },
          ),
    );
  }

  void _updateDownloadOverlayProgress({
    required int id,
    required int received,
    required int total,
  }) {
    final percent = total > 0 ? ((received / total) * 100).clamp(0, 100).floor() : null;
    unawaited(
      _runDownloadOverlayScript(
        _downloadOverlayCallScript(
          method: 'update',
          payload: {
            'id': id,
            'percent': percent,
            'status': 'downloading',
            'statusText': percent == null ? R.current.downloading : '${R.current.downloading} $percent%',
            'received': received,
            'total': total,
          },
        ),
      ),
    );
  }

  Future<void> _finishDownloadOverlayItem({
    required int id,
    required _DownloadOverlayStatus status,
    String? message,
    String? filename,
    String? filePath,
  }) async {
    await _runDownloadOverlayScript(
      _downloadOverlayCallScript(
        method: 'finish',
        payload: {
          'id': id,
          'percent': status == _DownloadOverlayStatus.completed ? 100 : null,
          'status': status.name,
          'statusText': switch (status) {
            _DownloadOverlayStatus.completed => R.current.downloadComplete,
            _DownloadOverlayStatus.failed => R.current.downloadError,
          },
          'message': ?message,
          'filename': ?filename,
          'path': ?filePath,
        },
      ),
    );
  }

  Future<void> _runDownloadOverlayScript(String script) async {
    try {
      await _requiredController.runJavaScript(script);
    } catch (error, stackTrace) {
      // The page may be navigating or may have already been disposed. Download
      // should continue even if the visual overlay cannot be updated.
      GlobalProtectDebug.error('Desktop WebView download overlay', error, stackTrace);
    }
  }

  String _downloadOverlayCallScript({
    required String method,
    required Map<String, Object?> payload,
  }) {
    final encodedPayload = jsonEncode(payload);
    return 'window.__qaqDownloadPanel?.$method($encodedPayload);';
  }

  String _downloadOverlayBootstrapScript() {
    final labels = jsonEncode({
      'downloading': R.current.downloading,
      'prepareDownload': R.current.prepareDownload,
      'downloadComplete': R.current.downloadComplete,
      'downloadError': R.current.downloadError,
      'closeDownloadNotification': R.current.closeDownloadNotification,
    });
    return '''
(function () {
  if (window.__qaqDownloadPanel) return;
  const labels = $labels;
''' + r'''

  const rootId = 'qaq-download-panel-root';
  const styleId = 'qaq-download-panel-style';

  if (!document.getElementById(styleId)) {
    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
      #${rootId} {
        position: fixed;
        right: 18px;
        bottom: 18px;
        width: min(380px, calc(100vw - 36px));
        display: flex;
        flex-direction: column;
        gap: 12px;
        z-index: 2147483647;
        pointer-events: none;
        font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      #${rootId} .qaq-download-card {
        pointer-events: auto;
        overflow: hidden;
        border-radius: 18px;
        border: 1px solid rgba(148, 163, 184, 0.28);
        background: linear-gradient(145deg, rgba(15, 23, 42, 0.94), rgba(30, 41, 59, 0.92));
        color: #f8fafc;
        box-shadow: 0 18px 45px rgba(2, 6, 23, 0.38), 0 0 0 1px rgba(255, 255, 255, 0.04) inset;
        backdrop-filter: blur(18px);
        animation: qaqDownloadSlideIn 180ms ease-out;
      }
      #${rootId} .qaq-download-card-inner { padding: 14px 14px 13px; }
      #${rootId} .qaq-download-head { display: flex; align-items: center; gap: 10px; }
      #${rootId} .qaq-download-dot {
        width: 10px;
        height: 10px;
        border-radius: 999px;
        background: #60a5fa;
        box-shadow: 0 0 18px rgba(96, 165, 250, 0.72);
        flex: none;
      }
      #${rootId} .qaq-download-card[data-status="completed"] .qaq-download-dot { background: #34d399; box-shadow: 0 0 18px rgba(52, 211, 153, 0.72); }
      #${rootId} .qaq-download-card[data-status="failed"] .qaq-download-dot { background: #fb7185; box-shadow: 0 0 18px rgba(251, 113, 133, 0.72); }
      #${rootId} .qaq-download-title { min-width: 0; flex: 1; font-size: 13px; font-weight: 700; letter-spacing: 0.02em; }
      #${rootId} .qaq-download-status { color: #cbd5e1; font-size: 12px; font-weight: 600; }
      #${rootId} .qaq-download-close {
        flex: none;
        border: 0;
        width: 26px;
        height: 26px;
        border-radius: 999px;
        color: #cbd5e1;
        background: rgba(148, 163, 184, 0.14);
        cursor: pointer;
        font-size: 18px;
        line-height: 26px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
      }
      #${rootId} .qaq-download-close:hover { color: #ffffff; background: rgba(148, 163, 184, 0.24); }
      #${rootId} .qaq-download-file { margin-top: 10px; font-size: 14px; font-weight: 700; color: #ffffff; word-break: break-all; }
      #${rootId} .qaq-download-path {
        margin-top: 5px;
        color: #cbd5e1;
        font-size: 11px;
        line-height: 1.35;
        word-break: break-all;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
      }
      #${rootId} .qaq-download-message { margin-top: 7px; color: #fecdd3; font-size: 11px; line-height: 1.35; word-break: break-word; }
      #${rootId} .qaq-download-progress-row { margin-top: 12px; display: flex; align-items: center; gap: 10px; }
      #${rootId} .qaq-download-track {
        position: relative;
        overflow: hidden;
        flex: 1;
        height: 8px;
        border-radius: 999px;
        background: rgba(148, 163, 184, 0.20);
      }
      #${rootId} .qaq-download-bar {
        height: 100%;
        width: 0%;
        border-radius: inherit;
        background: linear-gradient(90deg, #38bdf8, #22c55e);
        transition: width 180ms ease;
      }
      #${rootId} .qaq-download-card[data-status="failed"] .qaq-download-bar { background: linear-gradient(90deg, #fb7185, #ef4444); }
      #${rootId} .qaq-download-card[data-status="completed"] .qaq-download-bar { background: linear-gradient(90deg, #34d399, #22c55e); }
      #${rootId} .qaq-download-percent { width: 46px; text-align: right; color: #e2e8f0; font-size: 12px; font-weight: 800; }
      @keyframes qaqDownloadSlideIn { from { transform: translate3d(16px, 8px, 0); opacity: 0; } to { transform: translate3d(0, 0, 0); opacity: 1; } }
    `;
    document.head.appendChild(style);
  }

  let root = document.getElementById(rootId);
  if (!root) {
    root = document.createElement('div');
    root.id = rootId;
    document.documentElement.appendChild(root);
  }

  const text = (value) => value == null ? '' : String(value);
  const boundedPercent = (value) => {
    const numberValue = Number(value);
    if (!Number.isFinite(numberValue)) return null;
    return Math.max(0, Math.min(100, Math.round(numberValue)));
  };

  function ensureCard(data) {
    const id = text(data.id);
    let card = Array.from(root.children).find((child) => child.dataset.qaqDownloadId === id);
    if (card) return card;

    card = document.createElement('section');
    card.className = 'qaq-download-card';
    card.dataset.qaqDownloadId = id;
    card.dataset.status = 'downloading';
    card.innerHTML = `
      <div class="qaq-download-card-inner">
        <div class="qaq-download-head">
          <span class="qaq-download-dot"></span>
          <div class="qaq-download-title">${labels.downloading}</div>
          <div class="qaq-download-status">${labels.prepareDownload}</div>
          <button class="qaq-download-close" type="button" aria-label="${labels.closeDownloadNotification}">×</button>
        </div>
        <div class="qaq-download-file"></div>
        <div class="qaq-download-path"></div>
        <div class="qaq-download-message" hidden></div>
        <div class="qaq-download-progress-row">
          <div class="qaq-download-track"><div class="qaq-download-bar"></div></div>
          <div class="qaq-download-percent">0%</div>
        </div>
      </div>
    `;
    card.querySelector('.qaq-download-close').addEventListener('click', () => card.remove());
    root.appendChild(card);
    return card;
  }

  function paint(card, data) {
    const percent = boundedPercent(data.percent);
    const status = text(data.status) || 'downloading';
    const statusText = text(data.statusText) || (status === 'completed' ? labels.downloadComplete : labels.downloading);
    card.dataset.status = status;
    card.querySelector('.qaq-download-title').textContent = status === 'completed' ? labels.downloadComplete : status === 'failed' ? labels.downloadError : labels.downloading;
    card.querySelector('.qaq-download-status').textContent = statusText;
    if (data.filename != null) card.querySelector('.qaq-download-file').textContent = text(data.filename);
    if (data.path != null) card.querySelector('.qaq-download-path').textContent = text(data.path);

    const message = card.querySelector('.qaq-download-message');
    if (data.message) {
      message.hidden = false;
      message.textContent = text(data.message);
    }

    const bar = card.querySelector('.qaq-download-bar');
    const percentLabel = card.querySelector('.qaq-download-percent');
    if (percent == null) {
      bar.style.width = status === 'completed' ? '100%' : '16%';
      percentLabel.textContent = status === 'completed' ? '100%' : '…';
    } else {
      bar.style.width = `${percent}%`;
      percentLabel.textContent = `${percent}%`;
    }
  }

  window.__qaqDownloadPanel = {
    show(data) { paint(ensureCard(data), data); },
    update(data) { paint(ensureCard(data), data); },
    finish(data) { paint(ensureCard(data), data); },
  };
})();
''';
  }

  Future<Directory> _linuxDownloadsDirectory() async {
    final desktopDownloadsDirectory = await getDownloadsDirectory();
    if (desktopDownloadsDirectory != null) {
      await desktopDownloadsDirectory.create(recursive: true);
      return desktopDownloadsDirectory;
    }

    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Unable to resolve HOME for Linux downloads.');
    }
    final fallback = Directory(path.join(home, 'Downloads'));
    await fallback.create(recursive: true);
    return fallback;
  }

  String _linuxDownloadFilename(
    linux_webview.LinuxDownloadStartRequest request,
    Uri sourceUri,
  ) {
    final suggested = request.suggestedFilename?.trim();
    if (suggested != null && suggested.isNotEmpty) {
      return sanitizeWebViewDownloadFilename(suggested);
    }

    final lastSegment = sourceUri.pathSegments.isEmpty ? '' : sourceUri.pathSegments.last;
    return sanitizeWebViewDownloadFilename(lastSegment.isEmpty ? 'download' : lastSegment);
  }

  Future<File> _nextAvailableDownloadFile(Directory directory, String filename) async {
    final baseName = path.basenameWithoutExtension(filename);
    final extension = path.extension(filename);
    var candidate = File(path.join(directory.path, filename));
    if (!await candidate.exists()) return candidate;

    for (var index = 1; index < 1000; index++) {
      candidate = File(path.join(directory.path, '$baseName ($index)$extension'));
      if (!await candidate.exists()) return candidate;
    }

    throw StateError('Unable to find an available filename for $filename.');
  }

  Future<NavigationDecision> _onNavigationRequest(NavigationRequest request) async {
    if (!request.isMainFrame) return NavigationDecision.navigate;

    final uri = Uri.tryParse(request.url);
    if (uri == null || !IStudyAccessGuard.isIStudyUri(uri)) {
      return NavigationDecision.navigate;
    }

    final route = await IStudyAccessGuard.route();
    GlobalProtectDebug.log('WebView redirect reached iStudy; route=${route.name}');
    switch (route) {
      case IStudyAccessRoute.direct:
        if (Platform.isWindows) {
          GlobalProtectWebViewProxyBridge.instance.disableVpnRouting();
          _vpnProxyEnabled = false;
        }
        return NavigationDecision.navigate;
      case IStudyAccessRoute.blocked:
        if (Platform.isWindows) {
          GlobalProtectWebViewProxyBridge.instance.disableVpnRouting();
          _vpnProxyEnabled = false;
        }
        await _requiredController.loadHtmlString(IStudyAccessGuard.blockedHtml);
        return NavigationDecision.prevent;
      case IStudyAccessRoute.vpn:
        if (_vpnProxyEnabled) return NavigationDecision.navigate;
        try {
          if (Platform.isWindows) {
            GlobalProtectDebug.log(
              'enabling Windows GP routing before allowing original iStudy navigation',
            );
            await _enableWebViewProxy();
            // webview_all defers Windows network navigation policy at
            // WebResourceRequested, so the original request (including POST
            // body and request-specific headers) can continue unchanged once
            // the loopback bridge starts routing iStudy through GlobalProtect.
            GlobalProtectDebug.log(
              'Windows GP routing active; allowing original iStudy navigation',
            );
            return NavigationDecision.navigate;
          }

          GlobalProtectDebug.log('enabling GP proxy before retrying iStudy redirect');
          await _enableWebViewProxy();
          // Linux exposes the redirect URL but not a replayable request object.
          // iStudy SSO redirects are expected to be GET requests, so retry the
          // same URL after the WebKitGTK proxy is active.
          GlobalProtectDebug.log('GP proxy active; retrying iStudy navigation');
          await _requiredController.loadRequest(uri);
        } catch (error, stackTrace) {
          GlobalProtectDebug.error('redirect WebView GP setup', error, stackTrace);
          await _requiredController.loadHtmlString(IStudyAccessGuard.vpnFailedHtml(error));
        }
        return NavigationDecision.prevent;
    }
  }

  Future<void> _enableWebViewProxy() async {
    if (_vpnProxyEnabled && GlobalProtectWebViewProxyBridge.instance.isRunning) return;
    final runtimeGeneration = GlobalProtectWebViewRuntime.generation;
    if (!Platform.isWindows && !Platform.isLinux) {
      throw UnsupportedError('The experimental iStudy WebView VPN bridge currently supports desktop WebViews on Windows and Linux only.');
    }

    if (Platform.isWindows) {
      await _prepareWindowsWebViewProxyEnvironment();
      await GlobalProtectWebViewProxyBridge.instance.enableVpnRouting();
      if (!GlobalProtectWebViewRuntime.isCurrent(runtimeGeneration)) {
        await GlobalProtectWebViewRuntime.reset();
        throw StateError('WebView GlobalProtect runtime was reset while enabling Windows VPN routing.');
      }
      _vpnProxyEnabled = true;
      GlobalProtectDebug.log('Windows WebView GP routing active');
      return;
    }

    final port = await GlobalProtectWebViewProxyBridge.instance.ensureStarted(
      vpnHosts: IStudyAccessGuard.proxyHosts,
    );
    if (!GlobalProtectWebViewRuntime.isCurrent(runtimeGeneration)) {
      throw StateError('WebView GlobalProtect runtime was reset before ProxyOverride setup.');
    }
    GlobalProtectDebug.log('GP bridge ready on loopback port=$port');
    final reverseBypassSupported = await GlobalProtectWebViewProxyController.setProxyOverride(
      port: port,
      hosts: IStudyAccessGuard.proxyHosts,
    );
    GlobalProtectDebug.log('WebView ProxyOverride applied reverseBypass=$reverseBypassSupported');
    if (!GlobalProtectWebViewRuntime.isCurrent(runtimeGeneration)) {
      await GlobalProtectWebViewRuntime.reset();
      throw StateError('WebView GlobalProtect runtime was reset during ProxyOverride setup.');
    }
    _vpnProxyEnabled = true;
    GlobalProtectDebug.log('WebView ProxyOverride active');
  }

  Future<void> _clearWebViewProxy() async {
    _vpnProxyEnabled = false;
    await GlobalProtectWebViewRuntime.reset();
  }

  void _onPageStarted(String url) {
    if (kDebugMode) {
      debugPrint('[WebView] onPageStarted: $url');
    }
  }

  Future<void> _onPageFinished(String url) async {
    if (!kDebugMode) return;

    debugPrint('[WebView] onPageFinished: $url');

    final uri = Uri.tryParse(url);
    final cookieLabels = uri == null ? const <String>[] : await WebViewCookieStore.debugLabels(uri);
    debugPrint('[WebView] cookies: $cookieLabels');

    final title = await _requiredController.getTitle();
    debugPrint('[WebView] title: $title');

    final bodyText = await _requiredController.runJavaScriptReturningResult(
      "document.body?.innerText?.substring(0, 500) ?? ''",
    );
    debugPrint('[WebView] body: $bodyText');
  }

  Widget _buildButtonBar() => WebViewButtonBar(
    onBackPressed: () {
      final controller = _controller;
      if (controller != null) unawaited(controller.goBack());
    },
    onForwardPressed: () {
      final controller = _controller;
      if (controller != null) unawaited(controller.goForward());
    },
    onRefreshPressed: () {
      final controller = _controller;
      if (controller != null) unawaited(controller.reload());
    },
  );

  Widget _buildProgressBar() => ValueListenableBuilder<double>(
    valueListenable: progress,
    builder: (_, progress, _) => SizedBox(
      child: progress < 1.0
          ? LinearProgressIndicator(value: progress, color: Colors.greenAccent)
          : const SizedBox.shrink(),
    ),
  );

  Widget _buildWebViewContent(AsyncSnapshot<void> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return _buildLinuxNativeWebViewCover(R.current.preparingBrowser);
    }

    if (snapshot.hasError) {
      Error.throwWithStackTrace(snapshot.error!, snapshot.stackTrace ?? StackTrace.current);
    }

    if (Platform.isLinux && !_showNativeWebView) {
      return _buildLinuxNativeWebViewCover(
        _linuxNativeWebViewDetachedForPop ? R.current.closingBrowser : R.current.openingBrowser,
      );
    }

    return WebViewWidget(controller: _requiredController);
  }

  Widget _buildLinuxNativeWebViewCover(String label) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0F172A),
          Color(0xFF111827),
          Color(0xFF020617),
        ],
      ),
    ),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => WillPopScope(
    onWillPop: _handleRouteWillPop,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '')),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: FutureBuilder<void>(
                future: _initialLoadFuture,
                builder: (context, snapshot) => _buildWebViewContent(snapshot),
              ),
            ),
            _buildButtonBar(),
          ],
        ),
      ),
    ),
  );
}

enum _DownloadOverlayStatus { completed, failed }

class _InitialWebViewContent {
  const _InitialWebViewContent._({this.initialUrl, this.initialData});

  factory _InitialWebViewContent.url(Uri url) => _InitialWebViewContent._(initialUrl: url);
  factory _InitialWebViewContent.html(String html) => _InitialWebViewContent._(initialData: html);

  final Uri? initialUrl;
  final String? initialData;
}
