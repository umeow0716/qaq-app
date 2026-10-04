import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy.dart';

void main() {
  group('GlobalProtect WebView proxy routing', () {
    const vpnHost = 'istudy.ntut.edu.tw';

    test('routes only the exact iStudy host through GlobalProtect', () {
      expect(
        GlobalProtectWebViewProxyBridge.shouldRouteThroughGlobalProtect(
          host: 'istudy.ntut.edu.tw',
          vpnHost: vpnHost,
        ),
        isTrue,
      );
      expect(
        GlobalProtectWebViewProxyBridge.shouldRouteThroughGlobalProtect(
          host: 'ISTUDY.NTUT.EDU.TW.',
          vpnHost: vpnHost,
        ),
        isTrue,
      );
    });

    test(
      'can bind the loopback listener before VPN routing is enabled',
      () async {
        final bridge = GlobalProtectWebViewProxyBridge.instance;
        addTearDown(bridge.close);

        final port = await bridge.ensureListening(vpnHost: vpnHost);

        expect(port, greaterThan(0));
        expect(bridge.isRunning, isTrue);
        expect(bridge.vpnRoutingEnabled, isFalse);
      },
    );

    test('keeps every non-iStudy destination direct', () {
      for (final host in <String>[
        'nportal.ntut.edu.tw',
        'www.google.com',
        'cdn.example.com',
        'foo.istudy.ntut.edu.tw',
        'evil-istudy.ntut.edu.tw',
        'istudy.ntut.edu.tw.example.com',
      ]) {
        expect(
          GlobalProtectWebViewProxyBridge.shouldRouteThroughGlobalProtect(
            host: host,
            vpnHost: vpnHost,
          ),
          isFalse,
          reason: host,
        );
      }
    });
  });
}
