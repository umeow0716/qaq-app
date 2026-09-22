import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qaq_app/src/connector/core/dio_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_download_relay.dart';
import 'package:qaq_app/src/connector/web_view_cookie_store.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_debug.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy_controller.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_runtime.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/connector/web_view_file_transfer.dart';
import 'package:qaq_app/ui/pages/webview/qaq_android_navigation_delegate.dart';
import 'package:qaq_app/ui/pages/webview/web_view_button_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class QAQWebView extends StatefulWidget {
  const QAQWebView({super.key, required this.initialUrl, this.title});

  final Uri initialUrl;
  final String? title;

  @override
  State<QAQWebView> createState() => _QAQWebViewState();
}

class _QAQWebViewState extends State<QAQWebView> {
  final cookieJar = DioConnector.instance.cookiesManager;
  late final WebViewController _controller;
  late final Future<void> _initialLoadFuture;
  bool _vpnProxyEnabled = false;

  final progress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(_createNavigationDelegate());
    _initialLoadFuture = _prepareAndLoadInitialContent();
  }

  @override
  void dispose() {
    if (_vpnProxyEnabled) {
      unawaited(_clearWebViewProxy());
    }
    progress.dispose();
    super.dispose();
  }

  Future<void> _prepareAndLoadInitialContent() async {
    await _configurePlatformFilePicker();
    final content = await _prepareInitialContent();
    final initialUrl = content.initialUrl;
    if (initialUrl != null) {
      await _controller.loadRequest(initialUrl);
      return;
    }

    await _controller.loadHtmlString(content.initialData ?? '');
  }

  Future<_InitialWebViewContent> _prepareInitialContent() async {
    await setInitialCookies();

    // Direct iStudy URLs still need a routing preflight before their first load.
    // SSO/portal redirects are handled by _onNavigationRequest.
    if (!IStudyAccessGuard.isIStudyUri(widget.initialUrl)) {
      return _InitialWebViewContent.url(widget.initialUrl);
    }

    final route = await IStudyAccessGuard.route();
    GlobalProtectDebug.log('direct iStudy initial URL route=${route.name}');
    switch (route) {
      case IStudyAccessRoute.direct:
        return _InitialWebViewContent.url(widget.initialUrl);
      case IStudyAccessRoute.blocked:
        return _InitialWebViewContent.html(IStudyAccessGuard.blockedHtml);
      case IStudyAccessRoute.vpn:
        try {
          await _enableWebViewProxy();
          return _InitialWebViewContent.url(widget.initialUrl);
        } catch (error, stackTrace) {
          GlobalProtectDebug.error('initial WebView GP setup', error, stackTrace);
          return _InitialWebViewContent.html(IStudyAccessGuard.vpnFailedHtml(error));
        }
    }
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

  NavigationDelegate _createNavigationDelegate() {
    if (Platform.isAndroid) {
      return NavigationDelegate.fromPlatform(
        QAQAndroidNavigationDelegate(
          onDownloadStart: (url, userAgent, contentDisposition, mimeType, contentLength) {
            unawaited(
              _handleDownload(
                url: url,
                userAgent: userAgent,
                contentDisposition: contentDisposition,
                mimeType: mimeType,
                contentLength: contentLength,
              ),
            );
          },
        ),
        onProgress: _onProgressChanged,
        onNavigationRequest: _onNavigationRequest,
        onPageStarted: _onPageStarted,
        onPageFinished: (url) => unawaited(_onPageFinished(url)),
      );
    }

    return NavigationDelegate(
      onProgress: _onProgressChanged,
      onNavigationRequest: _onNavigationRequest,
      onPageStarted: _onPageStarted,
      onPageFinished: (url) => unawaited(_onPageFinished(url)),
    );
  }

  Future<void> _configurePlatformFilePicker() async {
    if (!Platform.isAndroid) return;
    final platformController = _controller.platform;
    if (platformController is! AndroidWebViewController) return;

    await platformController.setOnShowFileSelector(
      (params) => WebViewFileTransfer.pickSystemFiles(
        acceptTypes: params.acceptTypes,
        mode: params.mode.name,
        capture: params.isCaptureEnabled,
        filenameHint: params.filenameHint,
      ),
    );
  }

  Future<void> _handleDownload({
    required String url,
    required String userAgent,
    required String contentDisposition,
    required String mimeType,
    required int contentLength,
  }) async {
    if (!Platform.isAndroid) return;
    final sourceUri = Uri.tryParse(url);
    if (sourceUri == null || (sourceUri.scheme != 'http' && sourceUri.scheme != 'https')) {
      GlobalProtectDebug.log('ignoring unsupported WebView download URL: $url');
      return;
    }

    try {
      final cookieHeader = await WebViewCookieStore.cookieHeaderFor(sourceUri);
      final referer = await _controller.currentUrl();
      var requestUri = sourceUri;
      var keepAlive = false;

      if (IStudyAccessGuard.isIStudyUri(sourceUri)) {
        final route = await IStudyAccessGuard.route();
        GlobalProtectDebug.log('iStudy download route=${route.name}');
        switch (route) {
          case IStudyAccessRoute.direct:
            break;
          case IStudyAccessRoute.blocked:
            GlobalProtectDebug.log('iStudy download blocked by access settings');
            return;
          case IStudyAccessRoute.vpn:
            requestUri = await GlobalProtectDownloadRelay.instance.createDownloadUri(
              target: sourceUri,
              allowedHost: IStudyAccessGuard.iStudyHost,
              cookieHeader: cookieHeader,
              userAgent: userAgent,
              referer: referer,
            );
            keepAlive = true;
        }
      }

      final downloadId = await WebViewFileTransfer.enqueueSystemDownload(
        requestUrl: requestUri,
        sourceUrl: sourceUri,
        contentDisposition: contentDisposition,
        mimeType: mimeType,
        userAgent: userAgent,
        cookie: keepAlive ? null : cookieHeader,
        referer: referer,
        keepAlive: keepAlive,
      );
      GlobalProtectDebug.log(
        'WebView download enqueued id=$downloadId bytes=$contentLength '
        'relay=$keepAlive source=${sourceUri.host}',
      );
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('WebView download', error, stackTrace);
    }
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
        await _controller.loadHtmlString(IStudyAccessGuard.blockedHtml);
        return NavigationDecision.prevent;
      case IStudyAccessRoute.vpn:
        if (_vpnProxyEnabled) return NavigationDecision.navigate;
        try {
          GlobalProtectDebug.log('enabling GP proxy before retrying iStudy redirect');
          await _enableWebViewProxy();
          // webview_flutter exposes the redirect URL but not the complete native
          // request object. iStudy SSO redirects are expected to be GET requests,
          // so retry the same URL after ProxyOverride is active.
          GlobalProtectDebug.log('GP proxy active; retrying iStudy navigation');
          await _controller.loadRequest(uri);
        } catch (error, stackTrace) {
          GlobalProtectDebug.error('redirect WebView GP setup', error, stackTrace);
          await _controller.loadHtmlString(IStudyAccessGuard.vpnFailedHtml(error));
        }
        return NavigationDecision.prevent;
    }
  }

  Future<void> _enableWebViewProxy() async {
    if (_vpnProxyEnabled && GlobalProtectWebViewProxyBridge.instance.isRunning) return;
    final runtimeGeneration = GlobalProtectWebViewRuntime.generation;
    if (!Platform.isAndroid) {
      throw UnsupportedError('The experimental iStudy WebView VPN bridge currently supports Android only.');
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

    final title = await _controller.getTitle();
    debugPrint('[WebView] title: $title');

    final bodyText = await _controller.runJavaScriptReturningResult(
      "document.body?.innerText?.substring(0, 500) ?? ''",
    );
    debugPrint('[WebView] body: $bodyText');
  }

  Widget _buildButtonBar() => WebViewButtonBar(
    onBackPressed: () => _controller.goBack(),
    onForwardPressed: () => _controller.goForward(),
    onRefreshPressed: () => _controller.reload(),
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
                return WebViewWidget(controller: _controller);
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
