import 'package:flutter/material.dart';
import 'package:flutter_app/src/config/ischool_plus_config.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
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

  // A value shows the progress of page loading. Range from 0.0 to 1.0.
  final progress = ValueNotifier(0.0);

  Future<void> setInitialCookies() async {
    final cookies = await cookieJar.loadForRequest(widget.initialUrl);
    final initialUrl = WebUri(widget.initialUrl.toString());

    for (final cookie in cookies) {
      await cookieManager.setCookie(
        url: initialUrl,
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path ?? '/',
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

  Future<ServerTrustAuthResponse?> _onReceivedTrustAuthReqCallBack(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  ) async => ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);

  Future<NavigationActionPolicy> _onShouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    if (navigationAction.isForMainFrame == false) {
      return NavigationActionPolicy.ALLOW;
    }

    final requestUrl = navigationAction.request.url;
    if (requestUrl == null) return NavigationActionPolicy.ALLOW;

    final uri = Uri.tryParse(requestUrl.toString());
    if (uri == null || !ISchoolPlusConfig.shouldRewrite(uri)) {
      return NavigationActionPolicy.ALLOW;
    }

    navigationAction.request.url = WebUri(ISchoolPlusConfig.rewriteToProxy(uri).toString());
    await controller.loadUrl(urlRequest: navigationAction.request);
    return NavigationActionPolicy.CANCEL;
  }

  Widget _buildTATWebViewCore() => _TATWebViewCore(
    initialUrl: widget.initialUrl,
    onWebViewCreated: _onWebViewCreated,
    onProgressChanged: (_, progress) => _onProgressChanged(progress),
    onReceivedTrustAuthReqCallBack: _onReceivedTrustAuthReqCallBack,
    onShouldOverrideUrlLoading: _onShouldOverrideUrlLoading,
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
            child: FutureBuilder(future: setInitialCookies(), builder: (context, snapshot) => _buildTATWebViewCore()),
          ),
          _buildButtonBar(),
        ],
      ),
    ),
  );
}

class _TATWebViewCore extends StatelessWidget {
  const _TATWebViewCore({
    required this.initialUrl,
    this.onWebViewCreated,
    this.onProgressChanged,
    this.onReceivedTrustAuthReqCallBack,
    this.onShouldOverrideUrlLoading,
  });

  final Uri initialUrl;
  final void Function(InAppWebViewController controller)? onWebViewCreated;
  final void Function(InAppWebViewController controller, int progress)? onProgressChanged;
  final Future<ServerTrustAuthResponse?> Function(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  )?
  onReceivedTrustAuthReqCallBack;
  final Future<NavigationActionPolicy> Function(InAppWebViewController controller, NavigationAction navigationAction)?
  onShouldOverrideUrlLoading;

  @override
  Widget build(BuildContext context) => InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(initialUrl.toString())),
    initialSettings: InAppWebViewSettings(useShouldOverrideUrlLoading: true),
    onWebViewCreated: onWebViewCreated,
    onProgressChanged: onProgressChanged,
    onReceivedServerTrustAuthRequest: onReceivedTrustAuthReqCallBack,
    shouldOverrideUrlLoading: onShouldOverrideUrlLoading,
  );
}
