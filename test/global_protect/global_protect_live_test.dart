import 'dart:io';

import 'package:flutter_app/src/connector/global_protect/global_protect_connector.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_http_client.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final username = Platform.environment['GP_USERNAME'];
  final password = Platform.environment['GP_PASSWORD'];
  final gateway = Platform.environment['GP_GATEWAY'];
  final target = Platform.environment['GP_TARGET'] ?? 'https://istudy.ntut.edu.tw/mooc/index.php';
  final missingCredentials = username == null || username.isEmpty || password == null || password.isEmpty;

  test(
    'uses the production ESP-only GlobalProtect transport for a large iStudy response',
    () async {
      final connector = GlobalProtectConnector();
      GlobalProtectConnection? connection;
      GlobalProtectHttpClient? http;
      try {
        connection = await connector
            .connectWithPassword(
              username: username!,
              password: password!,
              gatewayHost: gateway?.isEmpty == true ? null : gateway,
              trace: (message) => stdout.writeln('[GP] $message'),
              transportTrace: (message) => stdout.writeln('[GP-DATA] $message'),
            )
            .timeout(const Duration(seconds: 40));

        expect(connection.session.authCookie, isNotEmpty);
        expect(connection.config.ipAddress, isNotNull);
        expect(connection.config.ipAddress, isNotEmpty);

        stdout.writeln(
          '[GP] connected transport=esp gateway=${connection.gateway.host} '
          'ip=${connection.config.ipAddress}',
        );

        http = GlobalProtectHttpClient.fromConnection(connection);
        final uri = Uri.parse(target);
        final request = await http.client.getUrl(uri).timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final response = await request.close().timeout(const Duration(seconds: 20));

        var bytes = 0;
        var events = 0;
        await for (final chunk in response.timeout(const Duration(seconds: 20))) {
          bytes += chunk.length;
          events += 1;
          if (events == 1 || events % 8 == 0) {
            stdout.writeln('[HTTP] progress events=$events bytes=$bytes');
          }
        }

        stdout.writeln(
          '[HTTP] complete status=${response.statusCode} events=$events bytes=$bytes '
          'transport=esp',
        );

        expect(response.statusCode, greaterThanOrEqualTo(200));
        expect(response.statusCode, lessThan(600));
        expect(bytes, greaterThan(0));
      } finally {
        if (http != null) await http.close(force: true);
        await connection?.transport.close();
        connector.close();
      }
    },
    skip: missingCredentials
        ? 'Set GP_USERNAME and GP_PASSWORD in the process environment to run the live VPN test.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
