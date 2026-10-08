import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_app_session.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_proxy.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_routing.dart';
import 'package:qaq_app/src/connector/network.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (_) async => null,
  );
  final account = Platform.environment['GP_USERNAME'];
  final password = Platform.environment['GP_PASSWORD'];
  test(
    'native desktop HTTPS reaches iStudy through the shared GP CONNECT proxy',
    () async {
      HttpOverrides.global = null;
      final session = GlobalProtectAppSession.instance;
      session.configureCredentials(account: () => account!, password: () => password!);
      final client = createDio(useGlobalProtect: false);
      try {
        client.httpClientAdapter.close(force: true);
        client.httpClientAdapter = await session.ensureDioAdapter(
          proxyPort: () =>
              GlobalProtectProxyBridge.instance.ensureStarted(vpnHosts: GlobalProtectRouting.webViewProxyHosts),
        );
        final response = await client.get<String>('https://istudy.ntut.edu.tw/');
        expect(response.statusCode, 200);
        expect(response.data, isNotEmpty);
        expect(response.realUri.host, 'istudy.ntut.edu.tw');
        stdout.writeln('[HTTP] native HTTPS via GP CONNECT: 200');
      } finally {
        client.close(force: true);
        await session.disconnect();
        await GlobalProtectProxyBridge.instance.close();
      }
    },
    skip: (!Platform.isWindows && !Platform.isLinux) || account == null || password == null
        ? 'Requires desktop native libraries and GP_USERNAME/GP_PASSWORD.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
