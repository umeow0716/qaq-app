import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/src/connector/global_protect/global_protect_connector.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_http_client.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_models.dart';
import 'package:flutter_app/src/connector/global_protect/virtual_tcp_socket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final username = Platform.environment['GP_USERNAME'];
  final password = Platform.environment['GP_PASSWORD'];
  final gateway = Platform.environment['GP_GATEWAY'];
  final target = Platform.environment['GP_TARGET'] ?? 'https://istudy.ntut.edu.tw/';
  final missingCredentials = username == null || username.isEmpty || password == null || password.isEmpty;

  test(
    'logs in to NTUT GlobalProtect and reaches iStudy through the tunnel',
    () async {
      final connector = GlobalProtectConnector();
      GlobalProtectConnection? connection;
      GlobalProtectHttpClient? http;
      try {
        stdout.writeln('[GP] authenticating portal/gateway...');
        connection = await connector.connectWithPassword(
          username: username!,
          password: password!,
          gatewayHost: gateway?.isEmpty == true ? null : gateway,
          tunnelTrace: (message) => stdout.writeln('[GPST] $message'),
        ).timeout(const Duration(seconds: 30));

        expect(connection.session.authCookie, isNotEmpty);
        expect(connection.config.ipAddress, isNotNull);
        expect(connection.config.ipAddress, isNotEmpty);
        expect(connection.config.tunnelPath, isNotEmpty);

        stdout.writeln('[GP] gateway: ${connection.gateway.host}');
        stdout.writeln('[GP] tunnel IPv4: ${connection.config.ipAddress}');
        stdout.writeln('[GP] MTU: ${connection.config.mtu ?? 'unknown'}');
        stdout.writeln('[GP] DNS: ${connection.config.dnsServers.join(', ')}');
        stdout.writeln('[GP] START_TUNNEL received; data tunnel is open.');

        final uri = Uri.parse(target);
        stdout.writeln('[DNS] resolving ${uri.host} using host DNS...');
        final resolved = await InternetAddress.lookup(
          uri.host,
          type: InternetAddressType.IPv4,
        ).timeout(const Duration(seconds: 8));
        if (resolved.isEmpty) throw SocketException('No IPv4 address found for ${uri.host}');
        final remote = resolved.first;
        stdout.writeln('[DNS] ${uri.host} -> ${remote.address}');

        http = GlobalProtectHttpClient.fromConnection(
          connection,
          resolver: (_) async => remote,
          socketDialer: (address, port) async {
            stdout.writeln('[TCP] SYN ${connection!.config.ipAddress} -> ${address.address}:$port');
            final socket = await VirtualTcpSocket.connectIp(
              tunnel: connection.tunnel,
              localAddress: connection.config.ipAddress!,
              remoteAddress: address.address,
              remotePort: port,
              timeout: const Duration(seconds: 10),
              maxSegmentPayload: _payloadForMtu(connection.config.mtu),
              trace: (message) => stdout.writeln('[TCP] $message'),
            );
            stdout.writeln('[TCP] connected ${address.address}:$port');
            return socket;
          },
          tcpConnectTimeout: const Duration(seconds: 10),
          tlsHandshakeTimeout: const Duration(seconds: 15),
          maxSegmentPayload: _payloadForMtu(connection.config.mtu),
        );

        stdout.writeln('[TLS/HTTP] opening $uri');
        final request = await http.client.getUrl(uri).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('getUrl() timed out while resolving, connecting, or negotiating TLS.'),
        );
        stdout.writeln('[TLS] handshake complete; sending HTTP request');
        request.followRedirects = false;
        final response = await request.close().timeout(const Duration(seconds: 20));
        stdout.writeln('[HTTP] response headers: ${response.statusCode}');
        final body = await utf8.decodeStream(response).timeout(const Duration(seconds: 20));

        stdout.writeln('[HTTP] Tunnel ${response.statusCode}: $uri');
        stdout.writeln('[HTTP] Response bytes: ${utf8.encode(body).length}');

        expect(response.statusCode, greaterThanOrEqualTo(200));
        expect(response.statusCode, lessThan(600));
      } finally {
        if (http != null) await http.close(force: true);
        await connection?.tunnel.close();
        connector.close();
      }
    },
    skip: missingCredentials
        ? 'Set GP_USERNAME and GP_PASSWORD in the process environment to run the live VPN test.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

int _payloadForMtu(int? mtu) {
  if (mtu == null || mtu <= 40) return 1200;
  final payload = mtu - 40;
  return payload < 1200 ? payload : 1200;
}
