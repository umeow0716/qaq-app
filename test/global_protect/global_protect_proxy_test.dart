import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_proxy.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_routing.dart';

void main() {
  group('GlobalProtect WebView proxy routing', () {
    const vpnHosts = GlobalProtectRouting.webViewProxyHosts;

    test('routes configured study hosts through GlobalProtect', () {
      expect(
        GlobalProtectProxyBridge.shouldRouteThroughGlobalProtect(host: 'istudy.ntut.edu.tw', vpnHosts: vpnHosts),
        isTrue,
      );
      expect(
        GlobalProtectProxyBridge.shouldRouteThroughGlobalProtect(host: 'ISTUDY.NTUT.EDU.TW.', vpnHosts: vpnHosts),
        isTrue,
      );
      expect(
        GlobalProtectProxyBridge.shouldRouteThroughGlobalProtect(host: 'istudycloud.ntut.edu.tw', vpnHosts: vpnHosts),
        isTrue,
      );
    });

    test('keeps portal authentication direct while tunneling study downloads', () {
      expect(
        GlobalProtectProxyBridge.shouldRouteThroughGlobalProtect(host: 'istudycloud.ntut.edu.tw', vpnHosts: vpnHosts),
        isTrue,
      );
      expect(
        GlobalProtectProxyBridge.shouldRouteThroughGlobalProtect(host: 'nportal.ntut.edu.tw', vpnHosts: vpnHosts),
        isFalse,
      );
    });

    test('can bind the loopback listener before VPN routing is enabled', () async {
      final bridge = GlobalProtectProxyBridge.instance;
      addTearDown(bridge.close);

      final port = await bridge.ensureListening(vpnHosts: vpnHosts);

      expect(port, greaterThan(0));
      expect(bridge.isRunning, isTrue);
      expect(bridge.vpnRoutingEnabled, isFalse);
    });

    test('serves a Windows PAC that proxies study hosts and keeps the portal direct', () async {
      final bridge = GlobalProtectProxyBridge.instance;
      addTearDown(bridge.close);

      final port = await bridge.ensureListening(vpnHosts: vpnHosts);
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.write(
        'GET http://127.0.0.1:$port${GlobalProtectProxyBridge.windowsPacPath} HTTP/1.1\r\n'
        'Host: 127.0.0.1:$port\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await socket.flush();
      final response = await utf8.decoder.bind(socket).join();

      expect(response, contains('HTTP/1.1 200 OK'));
      expect(response, contains('"istudy.ntut.edu.tw"'));
      expect(response, contains('"istudycloud.ntut.edu.tw"'));
      expect(response, isNot(contains('"nportal.ntut.edu.tw"')));
      expect(response, contains('PROXY 127.0.0.1:$port'));
      expect(response, contains('return "DIRECT"'));
    });

    test('keeps destinations outside the shared proxy policy direct', () {
      for (final host in <String>[
        'www.google.com',
        'cdn.example.com',
        'foo.istudy.ntut.edu.tw',
        'evil-istudy.ntut.edu.tw',
        'istudy.ntut.edu.tw.example.com',
      ]) {
        expect(
          GlobalProtectProxyBridge.shouldRouteThroughGlobalProtect(host: host, vpnHosts: vpnHosts),
          isFalse,
          reason: host,
        );
      }
    });
  });
}
