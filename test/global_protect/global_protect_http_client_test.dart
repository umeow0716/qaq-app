import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/src/connector/global_protect/global_protect_http_client.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_packet_transport.dart';
import 'package:flutter_app/src/connector/global_protect/virtual_byte_socket.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedPacketTransport implements GlobalProtectPacketTransport {
  @override
  Stream<Uint8List> get packets => const Stream<Uint8List>.empty();

  @override
  Future<void> sendIpv4(Uint8List packet) => throw UnimplementedError();

  @override
  Future<void> sendIpv6(Uint8List packet) => throw UnimplementedError();
}

class _SocketBackedVirtualByteSocket implements VirtualByteSocket {
  _SocketBackedVirtualByteSocket(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket.map(Uint8List.fromList);

  @override
  Future<void> write(Uint8List data) async {
    _socket.add(data);
    await _socket.flush();
  }

  @override
  Future<void> close({bool sendFin = true}) async {
    await _socket.close();
  }
}

void main() {
  test('HTTPS HttpClient request travels through the virtual socket connection factory', () async {
    final serverContext = SecurityContext()
      ..useCertificateChain('test/global_protect/fixtures/localhost-cert.pem')
      ..usePrivateKey('test/global_protect/fixtures/localhost-key.pem');
    final clientContext = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/global_protect/fixtures/localhost-cert.pem');

    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      serverContext,
    );

    final serverDone = Completer<void>();
    final serverSubscription = server.listen((socket) {
      final requestBuffer = StringBuffer();
      socket.cast<List<int>>().transform(utf8.decoder).listen((chunk) {
        requestBuffer.write(chunk);
        if (!requestBuffer.toString().contains('\r\n\r\n')) return;
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'Content-Length: 2\r\n'
          'Connection: close\r\n'
          '\r\n'
          'OK',
        );
        unawaited(socket.flush().then((_) => socket.close()));
        if (!serverDone.isCompleted) serverDone.complete();
      });
    });

    final gpClient = GlobalProtectHttpClient(
      tunnel: _UnusedPacketTransport(),
      localAddress: '10.0.0.2',
      securityContext: clientContext,
      resolver: (_) async => InternetAddress.loopbackIPv4,
      socketDialer: (_, __) async => _SocketBackedVirtualByteSocket(
        await Socket.connect(InternetAddress.loopbackIPv4, server.port),
      ),
    );

    try {
      final request = await gpClient.client.getUrl(
        Uri.parse('https://localhost:${server.port}/'),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, HttpStatus.ok);
      expect(body, 'OK');
      await serverDone.future.timeout(const Duration(seconds: 5));
    } finally {
      await gpClient.close(force: true);
      await serverSubscription.cancel();
      await server.close();
    }
  });
}
