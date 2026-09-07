import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_app/src/connector/global_protect/virtual_byte_socket.dart';
import 'package:flutter_app/src/connector/global_protect/virtual_tcp_loopback_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeVirtualByteSocket implements VirtualByteSocket {
  final StreamController<Uint8List> controller = StreamController<Uint8List>();
  final List<Uint8List> writes = <Uint8List>[];
  bool closed = false;

  @override
  Stream<Uint8List> get stream => controller.stream;

  @override
  Future<void> write(Uint8List data) async {
    writes.add(Uint8List.fromList(data));
  }

  @override
  Future<void> close({bool sendFin = true}) async {
    if (closed) return;
    closed = true;
    await controller.close();
  }
}

void main() {
  test('relays bytes in both directions over loopback', () async {
    final virtual = _FakeVirtualByteSocket();
    final bridge = await VirtualTcpLoopbackBridge.attach(virtual);

    bridge.socket.add(<int>[1, 2, 3]);
    await bridge.socket.flush();

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(virtual.writes, hasLength(1));
    expect(virtual.writes.single, orderedEquals(<int>[1, 2, 3]));

    final received = bridge.socket.first;
    virtual.controller.add(Uint8List.fromList(<int>[4, 5, 6]));
    expect(await received, orderedEquals(<int>[4, 5, 6]));

    await bridge.close();
    expect(virtual.closed, isTrue);
  });
}
