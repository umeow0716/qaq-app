import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_app/src/connector/adapters/early_interceptor_adapter.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_connector.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_http_client.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final username = Platform.environment['GP_USERNAME'];
  final password = Platform.environment['GP_PASSWORD'];
  final gateway = Platform.environment['GP_GATEWAY'];
  final target = Platform.environment['GP_TARGET'] ?? 'https://istudy.ntut.edu.tw/';
  final missingCredentials = username == null || username.isEmpty || password == null || password.isEmpty;

  test(
    'uses SessionManager and Dio to GET iStudy through GlobalProtect',
    () async {
      final connector = GlobalProtectConnector();
      final manager = GlobalProtectSessionManager(
        connect: () async {
          stdout.writeln('[SESSION] connecting GlobalProtect...');
          final connection = await connector.connectWithPassword(
            username: username!,
            password: password!,
            gatewayHost: gateway?.isEmpty == true ? null : gateway,
          );
          stdout.writeln('[SESSION] connected ${connection.config.ipAddress} via ${connection.gateway.host}');
          return connection;
        },
      );

      GlobalProtectHttpClient? gpHttp;
      Dio? dio;
      try {
        final connection = await manager.ensureConnected().timeout(const Duration(seconds: 30));
        expect(manager.state, GlobalProtectSessionState.connected);
        expect(connection.config.ipAddress, isNotNull);
        expect(connection.config.ipAddress, isNotEmpty);

        gpHttp = GlobalProtectHttpClient.fromConnection(
          connection,
          tcpConnectTimeout: const Duration(seconds: 10),
          tlsHandshakeTimeout: const Duration(seconds: 15),
        );

        dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status >= 200 && status < 600,
          ),
        )..httpClientAdapter = EarlyInterceptorAdapter(
            httpClient: gpHttp.client,
            closeHttpClient: false,
            headerDecorators: DioConnector.headerDecorators,
          );

        stdout.writeln('[DIO] GET $target');
        final response = await dio
            .get<String>(
              target,
              options: Options(
                followRedirects: false,
                responseType: ResponseType.plain,
              ),
            )
            .timeout(const Duration(seconds: 45));

        final body = response.data ?? '';
        stdout.writeln('[DIO] status=${response.statusCode}');
        stdout.writeln('[DIO] location=${response.headers.value(HttpHeaders.locationHeader) ?? '-'}');
        stdout.writeln('[DIO] content-type=${response.headers.value(HttpHeaders.contentTypeHeader) ?? '-'}');
        stdout.writeln('[DIO] responseBytes=${utf8.encode(body).length}');
        stdout.writeln('[SESSION] state=${manager.state.name}');

        expect(response.statusCode, isNotNull);
        expect(response.statusCode, greaterThanOrEqualTo(200));
        expect(response.statusCode, lessThan(600));
        expect(manager.state, GlobalProtectSessionState.connected);
      } finally {
        dio?.close(force: true);
        if (gpHttp != null) await gpHttp.close(force: true);
        await manager.dispose();
        connector.close();
      }
    },
    skip: missingCredentials
        ? 'Set GP_USERNAME and GP_PASSWORD in the process environment to run the live Dio VPN test.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
