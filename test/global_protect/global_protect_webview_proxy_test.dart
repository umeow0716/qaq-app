import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy.dart';

void main() {
  group('GlobalProtect WebView proxy routing', () {
    const vpnHosts = <String>['istudy.ntut.edu.tw', 'istudycloud.ntut.edu.tw'];

    test('routes configured iStudy hosts through GlobalProtect', () {
      expect(
        GlobalProtectWebViewProxyBridge.shouldRouteThroughGlobalProtect(host: 'istudy.ntut.edu.tw', vpnHosts: vpnHosts),
        isTrue,
      );
      expect(
        GlobalProtectWebViewProxyBridge.shouldRouteThroughGlobalProtect(
          host: 'ISTUDY.NTUT.EDU.TW.',
          vpnHosts: vpnHosts,
        ),
        isTrue,
      );
      expect(
        GlobalProtectWebViewProxyBridge.shouldRouteThroughGlobalProtect(
          host: 'istudycloud.ntut.edu.tw',
          vpnHosts: vpnHosts,
        ),
        isTrue,
      );
    });

    test('can bind the loopback listener before VPN routing is enabled', () async {
      final bridge = GlobalProtectWebViewProxyBridge.instance;
      addTearDown(bridge.close);

      final port = await bridge.ensureListening(vpnHosts: vpnHosts);

      expect(port, greaterThan(0));
      expect(bridge.isRunning, isTrue);
      expect(bridge.vpnRoutingEnabled, isFalse);
    });

    test('serves a Windows PAC that proxies both iStudy service hosts', () async {
      final bridge = GlobalProtectWebViewProxyBridge.instance;
      addTearDown(bridge.close);

      final port = await bridge.ensureListening(vpnHosts: vpnHosts);
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.write(
        'GET http://127.0.0.1:$port${GlobalProtectWebViewProxyBridge.windowsPacPath} HTTP/1.1\r\n'
        'Host: 127.0.0.1:$port\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await socket.flush();
      final response = await utf8.decoder.bind(socket).join();

      expect(response, contains('HTTP/1.1 200 OK'));
      expect(response, contains('"istudy.ntut.edu.tw"'));
      expect(response, contains('"istudycloud.ntut.edu.tw"'));
      expect(response, contains('PROXY 127.0.0.1:$port'));
      expect(response, contains('return "DIRECT"'));
    });

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
          GlobalProtectWebViewProxyBridge.shouldRouteThroughGlobalProtect(host: host, vpnHosts: vpnHosts),
          isFalse,
          reason: host,
        );
      }
    });
  });
}
