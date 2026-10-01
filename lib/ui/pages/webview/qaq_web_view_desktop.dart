import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qaq_app/src/connector/core/dio_connector.dart';
import 'package:qaq_app/src/connector/web_view_cookie_store.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_debug.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy_controller.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_runtime.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/ui/pages/webview/web_view_button_bar.dart';
import 'package:webview_all/webview_all.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_all_linux/webview_all_linux.dart' as linux_webview;
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
  bool _vpnProxyEnabled = false;

  final progress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _initialLoadFuture = _prepareControllerAndLoadInitialContent();
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

  Future<void> _prepareControllerAndLoadInitialContent() async {
    final content = await _prepareInitialContent();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(_createNavigationDelegate());
    await _configureLinuxFileTransfer(controller);
    _controller = controller;
    final initialUrl = content.initialUrl;
    if (initialUrl != null) {
      await controller.loadRequest(initialUrl);
      return;
    }

    await controller.loadHtmlString(content.initialData ?? '');
  }

  Future<_InitialWebViewContent> _prepareInitialContent() async {
    await setInitialCookies();

    // Only direct iStudy URLs need a desktop proxy preflight before their first
    // load. Non-iStudy pages such as debug Google Forms must not inherit the
    // process-wide WebView proxy; if they later redirect to iStudy,
    // _onNavigationRequest enables the bridge and retries that navigation.
    if (!IStudyAccessGuard.isIStudyUri(widget.initialUrl)) {
      return _InitialWebViewContent.url(widget.initialUrl);
    }

    final preflightRoute = await _prepareDesktopVpnProxyBeforeWebViewEnvironment();
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

  Future<IStudyAccessRoute?> _prepareDesktopVpnProxyBeforeWebViewEnvironment() async {
    if (!Platform.isWindows && !Platform.isLinux) return null;

    final route = await IStudyAccessGuard.route();
    GlobalProtectDebug.log('${Platform.operatingSystem} WebView preflight iStudy route=${route.name}');
    if (route == IStudyAccessRoute.vpn) {
      // Desktop WebViews should receive their process-wide proxy before the
      // first controller request. Windows installs WebView2 arguments; Linux
      // applies WebKitGTK network proxy settings through webview_all.
      await _enableWebViewProxy();
    }
    return route;
  }

  Future<void> setInitialCookies() async {
    await WebViewCookieStore.clearAll();

    final portalUrl = Uri.parse(NTUTConnector.host);

    await _setCookiesForUri(portalUrl);

    if (widget.initialUrl.host != portalUrl.host) {
      await _setCookiesForUri(widget.initialUrl);
    }
  }

  Future<void> _setCookiesForUri(Uri uri) async {
    final cookies = await cookieJar.loadForRequest(uri);
    for (final cookie in cookies) {
      await WebViewCookieStore.setCookie(url: uri, cookie: cookie);
    }
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

    try {
      final downloadsDirectory = await _linuxDownloadsDirectory();
      final filename = _linuxDownloadFilename(request, sourceUri);
      final destination = await _nextAvailableDownloadFile(downloadsDirectory, filename);
      final referer = await _requiredController.currentUrl();
      final cookieHeader = await WebViewCookieStore.cookieHeaderFor(sourceUri);
      final userAgent = DioConnector.instance.headers[HttpHeaders.userAgentHeader];
      final headers = <String, dynamic>{
        if (userAgent != null && userAgent.isNotEmpty) HttpHeaders.userAgentHeader: userAgent,
        if (referer != null && referer.isNotEmpty) HttpHeaders.refererHeader: referer,
        if (cookieHeader != null && cookieHeader.isNotEmpty) HttpHeaders.cookieHeader: cookieHeader,
      };

      GlobalProtectDebug.log('Linux WebView download saving ${sourceUri.host} to ${destination.path}');
      await DioConnector.instance.download(
        sourceUri.toString(),
        (_) => destination.path,
        progressCallback: (received, total) {
          if (total > 0 && received == total) {
            GlobalProtectDebug.log('Linux WebView download received $received bytes');
          }
        },
        cancelToken: CancelToken(),
        header: headers,
      );
      GlobalProtectDebug.log('Linux WebView download saved ${destination.path}');
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('Linux WebView download', error, stackTrace);
    }
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
      return _sanitizeLinuxFilename(suggested);
    }

    final lastSegment = sourceUri.pathSegments.isEmpty ? '' : sourceUri.pathSegments.last;
    final decoded = lastSegment.isEmpty ? 'download' : Uri.decodeComponent(lastSegment);
    return _sanitizeLinuxFilename(decoded);
  }

  String _sanitizeLinuxFilename(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x20 || codeUnit == 0x2f || codeUnit == 0x5c) {
        buffer.write('_');
      } else {
        buffer.writeCharCode(codeUnit);
      }
    }

    final sanitized = buffer
        .toString()
        .trim()
        .replaceAll(RegExp(r'^[. ]+'), '')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return sanitized.isEmpty ? 'download' : sanitized;
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
        return NavigationDecision.navigate;
      case IStudyAccessRoute.blocked:
        await _requiredController.loadHtmlString(IStudyAccessGuard.blockedHtml);
        return NavigationDecision.prevent;
      case IStudyAccessRoute.vpn:
        if (_vpnProxyEnabled) return NavigationDecision.navigate;
        try {
          GlobalProtectDebug.log('enabling GP proxy before retrying iStudy redirect');
          await _enableWebViewProxy();
          // The desktop WebView API exposes the redirect URL but not the complete native
          // request object. iStudy SSO redirects are expected to be GET requests,
          // so retry the same URL after ProxyOverride is active.
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

    final port = await GlobalProtectWebViewProxyBridge.instance.ensureStarted();
    if (!GlobalProtectWebViewRuntime.isCurrent(runtimeGeneration)) {
      throw StateError('WebView GlobalProtect runtime was reset before ProxyOverride setup.');
    }
    GlobalProtectDebug.log('GP bridge ready on loopback port=$port');
    final reverseBypassSupported = await GlobalProtectWebViewProxyController.setProxyOverride(
      port: port,
      host: IStudyAccessGuard.iStudyHost,
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title ?? '')),
    body: SafeArea(
      child: Column(
        children: [
          _buildProgressBar(),
          Expanded(
            child: FutureBuilder<void>(
              future: _initialLoadFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  Error.throwWithStackTrace(snapshot.error!, snapshot.stackTrace ?? StackTrace.current);
                }
                return WebViewWidget(controller: _requiredController);
              },
            ),
          ),
          _buildButtonBar(),
        ],
      ),
    ),
  );
}

class _InitialWebViewContent {
  const _InitialWebViewContent._({this.initialUrl, this.initialData});

  factory _InitialWebViewContent.url(Uri url) => _InitialWebViewContent._(initialUrl: url);
  factory _InitialWebViewContent.html(String html) => _InitialWebViewContent._(initialData: html);

  final Uri? initialUrl;
  final String? initialData;
}
