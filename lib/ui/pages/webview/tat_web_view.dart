import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_debug.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_webview_proxy.dart';
import 'package:flutter_app/src/connector/ischool_plus_access_guard.dart';
import 'package:flutter_app/src/connector/ntut_connector.dart';
import 'package:flutter_app/ui/pages/webview/web_view_button_bar.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class TATWebView extends StatefulWidget {
  const TATWebView({super.key, required this.initialUrl, this.title});

  final Uri initialUrl;
  final String? title;

  @override
  State<TATWebView> createState() => _TATWebViewState();
}

class _TATWebViewState extends State<TATWebView> {
  final cookieManager = CookieManager.instance();
  final cookieJar = DioConnector.instance.cookiesManager;
  InAppWebViewController? _controller;
  late final Future<_InitialWebViewContent> _initialContentFuture;
  bool _vpnProxyEnabled = false;

  final progress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _initialContentFuture = _prepareInitialContent();
  }

  @override
  void dispose() {
    if (_vpnProxyEnabled) {
      unawaited(_clearWebViewProxy());
    }
    progress.dispose();
    super.dispose();
  }

  Future<_InitialWebViewContent> _prepareInitialContent() async {
    await setInitialCookies();

    // shouldOverrideUrlLoading is not called for the initial WebView load, so
    // direct iStudy URLs need one preflight. SSO/portal entry URLs are allowed
    // normally; if they later redirect to iStudy, the navigation callback
    // below handles that actual destination.
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
    await cookieManager.deleteAllCookies();

    final portalUrl = Uri.parse(NTUTConnector.host);

    await _setCookiesForUri(portalUrl);

    if (widget.initialUrl.host != portalUrl.host) {
      await _setCookiesForUri(widget.initialUrl);
    }
  }

  Future<void> _setCookiesForUri(Uri uri) async {
    final cookies = await cookieJar.loadForRequest(uri);
    final webUri = WebUri(uri.toString());

    for (final cookie in cookies) {
      await cookieManager.setCookie(
        url: webUri,
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path ?? '/',
        expiresDate: cookie.expires?.millisecondsSinceEpoch,
        maxAge: cookie.maxAge,
        isSecure: cookie.secure,
        isHttpOnly: cookie.httpOnly,
      );
    }
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;
  }

  void _onProgressChanged(int webViewProgress) {
    progress.value = webViewProgress / 100.0;
  }

  Future<NavigationActionPolicy?> _onShouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    if (!navigationAction.isForMainFrame) return NavigationActionPolicy.ALLOW;

    final rawUrl = navigationAction.request.url?.rawValue;
    if (rawUrl == null) return NavigationActionPolicy.ALLOW;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !IStudyAccessGuard.isIStudyUri(uri)) {
      return NavigationActionPolicy.ALLOW;
    }

    final route = await IStudyAccessGuard.route();
    GlobalProtectDebug.log('WebView redirect reached iStudy; route=${route.name}');
    switch (route) {
      case IStudyAccessRoute.direct:
        return NavigationActionPolicy.ALLOW;
      case IStudyAccessRoute.blocked:
        await controller.loadData(data: IStudyAccessGuard.blockedHtml);
        return NavigationActionPolicy.CANCEL;
      case IStudyAccessRoute.vpn:
        if (_vpnProxyEnabled) return NavigationActionPolicy.ALLOW;
        try {
          GlobalProtectDebug.log('enabling GP proxy before retrying iStudy redirect');
          await _enableWebViewProxy();
          // The navigation that revealed the iStudy redirect was created before
          // the proxy override existed. Cancel it and retry the exact request
          // after ProxyController confirms the override is active.
          GlobalProtectDebug.log('GP proxy active; retrying iStudy navigation');
          await controller.loadUrl(urlRequest: navigationAction.request);
        } catch (error, stackTrace) {
          GlobalProtectDebug.error('redirect WebView GP setup', error, stackTrace);
          await controller.loadData(data: IStudyAccessGuard.vpnFailedHtml(error));
        }
        return NavigationActionPolicy.CANCEL;
    }
  }

  Future<void> _enableWebViewProxy() async {
    if (_vpnProxyEnabled) return;
    if (!Platform.isAndroid) {
      throw UnsupportedError('The experimental iStudy WebView VPN bridge currently supports Android only.');
    }

    GlobalProtectDebug.log('checking Android WebView ProxyOverride support');
    final supported = await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE);
    if (!supported) {
      throw UnsupportedError('Android WebView ProxyOverride is not supported on this device.');
    }

    final port = await GlobalProtectWebViewProxyBridge.instance.ensureStarted();
    GlobalProtectDebug.log('GP bridge ready on loopback port=$port');
    final reverseBypassSupported = await WebViewFeature.isFeatureSupported(
      WebViewFeature.PROXY_OVERRIDE_REVERSE_BYPASS,
    );
    GlobalProtectDebug.log('applying WebView ProxyOverride reverseBypass=$reverseBypassSupported');
    await ProxyController.instance().setProxyOverride(
      settings: ProxySettings(
        proxyRules: <ProxyRule>[
          ProxyRule(
            schemeFilter: ProxySchemeFilter.MATCH_ALL_SCHEMES,
            url: 'http://127.0.0.1:$port',
          ),
        ],
        // Newer WebView versions support an allow-list style proxy. Prefer it
        // so only the actual iStudy destination uses the userspace tunnel.
        // Older WebViews temporarily proxy all HTTP(S) traffic in this page.
        bypassRules: reverseBypassSupported
            ? const <String>[IStudyAccessGuard.iStudyHost]
            : const <String>['127.0.0.1', 'localhost'],
        reverseBypassEnabled: reverseBypassSupported,
      ),
    );
    _vpnProxyEnabled = true;
    GlobalProtectDebug.log('WebView ProxyOverride active');
  }

  Future<void> _clearWebViewProxy() async {
    _vpnProxyEnabled = false;
    if (!Platform.isAndroid) return;
    try {
      final supported = await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE);
      if (supported) await ProxyController.instance().clearProxyOverride();
    } catch (_) {
      // Best-effort cleanup; the page is already being disposed.
    } finally {
      await GlobalProtectWebViewProxyBridge.instance.close();
    }
  }

  Future<ServerTrustAuthResponse?> _onReceivedTrustAuthReqCallBack(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  ) async => ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);

  Widget _buildTATWebViewCore(_InitialWebViewContent content) => _TATWebViewCore(
    initialUrl: content.initialUrl,
    initialData: content.initialData,
    onWebViewCreated: _onWebViewCreated,
    onProgressChanged: (_, progress) => _onProgressChanged(progress),
    onReceivedTrustAuthReqCallBack: _onReceivedTrustAuthReqCallBack,
    shouldOverrideUrlLoading: _onShouldOverrideUrlLoading,
  );

  Widget _buildButtonBar() => WebViewButtonBar(
    onBackPressed: () => _controller?.goBack(),
    onForwardPressed: () => _controller?.goForward(),
    onRefreshPressed: () => _controller?.reload(),
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
            child: FutureBuilder<_InitialWebViewContent>(
              future: _initialContentFuture,
              builder: (context, snapshot) {
                final content = snapshot.data;
                if (content == null) return const Center(child: CircularProgressIndicator());
                return _buildTATWebViewCore(content);
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

class _TATWebViewCore extends StatelessWidget {
  const _TATWebViewCore({
    this.initialUrl,
    this.initialData,
    this.onWebViewCreated,
    this.onProgressChanged,
    this.onReceivedTrustAuthReqCallBack,
    this.shouldOverrideUrlLoading,
  });

  final Uri? initialUrl;
  final String? initialData;
  final void Function(InAppWebViewController controller)? onWebViewCreated;
  final void Function(InAppWebViewController controller, int progress)? onProgressChanged;
  final Future<ServerTrustAuthResponse?> Function(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  )?
  onReceivedTrustAuthReqCallBack;
  final Future<NavigationActionPolicy?> Function(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  )?
  shouldOverrideUrlLoading;

  @override
  Widget build(BuildContext context) => InAppWebView(
    initialUrlRequest: initialUrl == null ? null : URLRequest(url: WebUri(initialUrl.toString())),
    initialData: initialData == null ? null : InAppWebViewInitialData(data: initialData!),
    initialSettings: InAppWebViewSettings(useShouldOverrideUrlLoading: true),
    onWebViewCreated: onWebViewCreated,
    onProgressChanged: onProgressChanged,
    onReceivedServerTrustAuthRequest: onReceivedTrustAuthReqCallBack,
    shouldOverrideUrlLoading: shouldOverrideUrlLoading,
    onLoadStart: (controller, url) {
      debugPrint('[WebView] onLoadStart: $url');
    },
    onLoadStop: (controller, url) async {
      debugPrint('[WebView] onLoadStop: $url');

      if (url != null) {
        final cookies =
            await CookieManager.instance().getCookies(url: url);

        debugPrint(
          '[WebView] cookies: '
          '${cookies.map((c) => '${c.name}@${c.domain}${c.path}').toList()}',
        );
      }

      final title = await controller.getTitle();
      debugPrint('[WebView] title: $title');

      final bodyText = await controller.evaluateJavascript(
        source: '''
          document.body?.innerText?.substring(0, 500) ?? ''
        ''',
      );

      debugPrint('[WebView] body: $bodyText');
    },
  );
}
