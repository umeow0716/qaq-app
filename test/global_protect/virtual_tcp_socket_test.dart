import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_app/src/connector/global_protect/global_protect_transport.dart';
import 'package:flutter_app/src/connector/global_protect/ipv4_tcp_codec.dart';
import 'package:flutter_app/src/connector/global_protect/virtual_tcp_socket.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements GlobalProtectTransport {
  final StreamController<Uint8List> controller = StreamController<Uint8List>.broadcast();
  final List<Uint8List> sentIpv4 = [];

  @override
  Stream<Uint8List> get packets => controller.stream;

  @override
  Future<void> sendIpv4(Uint8List packet) async {
    sentIpv4.add(packet);
  }

  @override
  Future<void> sendIpv6(Uint8List packet) async {}

  @override
  Future<void> close() => controller.close();
}

class _DelayedTransport implements GlobalProtectTransport {
  final StreamController<Uint8List> controller = StreamController<Uint8List>.broadcast();
  final List<Uint8List> sentIpv4 = [];
  final List<Completer<void>> _pending = [];
  bool delayWrites = false;

  @override
  Stream<Uint8List> get packets => controller.stream;

  int get pendingCount => _pending.length;

  @override
  Future<void> sendIpv4(Uint8List packet) {
    sentIpv4.add(packet);
    if (!delayWrites) return Future<void>.value();
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  void releasePending() {
    if (_pending.isEmpty) {
      delayWrites = true;
      return;
    }
    final completer = _pending.removeAt(0);
    completer.complete();
  }

  @override
  Future<void> sendIpv6(Uint8List packet) async {}

  @override
  Future<void> close() => controller.close();
}

void main() {
  test('completes a TCP three way handshake over the packet transport', () async {
    final transport = _FakeTransport();
    final connectFuture = VirtualTcpSocket.connectIp(
      transport: transport,
      localAddress: '10.0.0.2',
      remoteAddress: '10.0.0.10',
      remotePort: 443,
      localPort: 50000,
      random: Random(1),
    );

    await Future<void>.delayed(Duration.zero);
    expect(transport.sentIpv4, hasLength(1));
    final syn = Ipv4TcpCodec.decode(transport.sentIpv4.single)!;
    expect(syn.syn, isTrue);
    expect(syn.ack, isFalse);

    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50000,
        sequenceNumber: 9000,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.syn | TcpFlags.ack,
      ),
    );

    final socket = await connectFuture;
    await Future<void>.delayed(Duration.zero);
    expect(socket.isConnected, isTrue);
    expect(transport.sentIpv4, hasLength(2));

    final ack = Ipv4TcpCodec.decode(transport.sentIpv4[1])!;
    expect(ack.ack, isTrue);
    expect(ack.syn, isFalse);
    expect(ack.sequenceNumber, syn.sequenceNumber + 1);
    expect(ack.acknowledgementNumber, 9001);

    await socket.close(sendFin: false);
    await transport.close();
  });

  test('delivers matching TCP payload to the virtual stream', () async {
    final transport = _FakeTransport();
    final connectFuture = VirtualTcpSocket.connectIp(
      transport: transport,
      localAddress: '10.0.0.2',
      remoteAddress: '10.0.0.10',
      remotePort: 443,
      localPort: 50001,
      random: Random(2),
    );

    await Future<void>.delayed(Duration.zero);
    final syn = Ipv4TcpCodec.decode(transport.sentIpv4.single)!;
    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50001,
        sequenceNumber: 7000,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.syn | TcpFlags.ack,
      ),
    );
    final socket = await connectFuture;

    final firstPayload = socket.stream.first;
    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50001,
        sequenceNumber: 7001,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.ack | TcpFlags.psh,
        payload: Uint8List.fromList([1, 2, 3]),
      ),
    );

    expect(await firstPayload, [1, 2, 3]);
    await Future<void>.delayed(Duration.zero);
    final ack = Ipv4TcpCodec.decode(transport.sentIpv4.last)!;
    expect(ack.acknowledgementNumber, 7004);

    await socket.close(sendFin: false);
    await transport.close();
  });

  test('reorders out-of-order TCP payload before exposing it to the stream', () async {
    final transport = _FakeTransport();
    final connectFuture = VirtualTcpSocket.connectIp(
      transport: transport,
      localAddress: '10.0.0.2',
      remoteAddress: '10.0.0.10',
      remotePort: 443,
      localPort: 50002,
      random: Random(3),
    );

    await Future<void>.delayed(Duration.zero);
    final syn = Ipv4TcpCodec.decode(transport.sentIpv4.single)!;
    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50002,
        sequenceNumber: 1000,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.syn | TcpFlags.ack,
      ),
    );
    final socket = await connectFuture;

    final received = <int>[];
    final done = Completer<void>();
    final sub = socket.stream.listen((data) {
      received.addAll(data);
      if (received.length == 6 && !done.isCompleted) done.complete();
    });

    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50002,
        sequenceNumber: 1004,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.ack | TcpFlags.psh,
        payload: Uint8List.fromList([4, 5, 6]),
      ),
    );
    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50002,
        sequenceNumber: 1001,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.ack,
        payload: Uint8List.fromList([1, 2, 3]),
      ),
    );

    await done.future.timeout(const Duration(seconds: 2));
    expect(received, [1, 2, 3, 4, 5, 6]);
    await sub.cancel();
    await socket.close(sendFin: false);
    await transport.close();
  });

  test('segments large writes below the configured payload size', () async {
    final transport = _FakeTransport();
    final connectFuture = VirtualTcpSocket.connectIp(
      transport: transport,
      localAddress: '10.0.0.2',
      remoteAddress: '10.0.0.10',
      remotePort: 443,
      localPort: 50003,
      random: Random(4),
      maxSegmentPayload: 4,
    );

    await Future<void>.delayed(Duration.zero);
    final syn = Ipv4TcpCodec.decode(transport.sentIpv4.single)!;
    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50003,
        sequenceNumber: 2000,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.syn | TcpFlags.ack,
      ),
    );
    final socket = await connectFuture;
    await Future<void>.delayed(Duration.zero);
    final before = transport.sentIpv4.length;

    await socket.write(Uint8List.fromList(List<int>.generate(10, (i) => i)));
    final segments = transport.sentIpv4.skip(before).map(Ipv4TcpCodec.decode).whereType<Ipv4TcpPacket>().toList();
    expect(segments.map((p) => p.payload.length).toList(), [4, 4, 2]);
    expect(segments.map((p) => p.payload).expand((p) => p).toList(), List<int>.generate(10, (i) => i));

    await socket.close(sendFin: false);
    await transport.close();
  });

  test('serializes concurrent writes so TCP sequence numbers never overlap', () async {
    final transport = _DelayedTransport();
    final connectFuture = VirtualTcpSocket.connectIp(
      transport: transport,
      localAddress: '10.0.0.2',
      remoteAddress: '10.0.0.10',
      remotePort: 443,
      localPort: 50004,
      random: Random(5),
      maxSegmentPayload: 1200,
    );

    await Future<void>.delayed(Duration.zero);
    final syn = Ipv4TcpCodec.decode(transport.sentIpv4.single)!;
    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50004,
        sequenceNumber: 3000,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.syn | TcpFlags.ack,
      ),
    );
    final socket = await connectFuture;
    await Future<void>.delayed(Duration.zero);
    transport.releasePending();
    await Future<void>.delayed(Duration.zero);
    final before = transport.sentIpv4.length;

    final first = socket.write(Uint8List.fromList([1, 2, 3]));
    final second = socket.write(Uint8List.fromList([4, 5, 6, 7]));

    await Future<void>.delayed(Duration.zero);
    expect(transport.pendingCount, 1, reason: 'Only the first queued TCP write may be in flight.');
    transport.releasePending();
    await first;

    await Future<void>.delayed(Duration.zero);
    expect(transport.pendingCount, 1, reason: 'The second write starts only after the first advances _sendSequence.');
    transport.releasePending();
    await second;

    final segments = transport.sentIpv4
        .skip(before)
        .map(Ipv4TcpCodec.decode)
        .whereType<Ipv4TcpPacket>()
        .where((packet) => packet.payload.isNotEmpty)
        .toList();
    expect(segments, hasLength(2));
    expect(segments[1].sequenceNumber, segments[0].sequenceNumber + segments[0].payload.length);

    await socket.close(sendFin: false);
    await transport.close();
  });

  test('advertises maxSegmentPayload as MSS in SYN', () async {
    final transport = _FakeTransport();
    final connectFuture = VirtualTcpSocket.connectIp(
      transport: transport,
      localAddress: '172.24.1.10',
      remoteAddress: '140.124.13.231',
      remotePort: 443,
      localPort: 50000,
      maxSegmentPayload: 1200,
      random: Random(1),
    );

    await Future<void>.delayed(Duration.zero);
    final syn = Ipv4TcpCodec.decode(transport.sentIpv4.single)!;
    expect(syn.syn, isTrue);
    expect(syn.tcpOptions, <int>[2, 4, 0x04, 0xb0]);

    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('140.124.13.231'),
        destinationAddress: InternetAddressValue.parseIpv4('172.24.1.10'),
        sourcePort: 443,
        destinationPort: 50000,
        sequenceNumber: 9000,
        acknowledgementNumber: (syn.sequenceNumber + 1) & 0xffffffff,
        flags: TcpFlags.syn | TcpFlags.ack,
      ),
    );

    final socket = await connectFuture;
    await socket.close(sendFin: false);
    await transport.close();
  });

  test('waits for missing data before consuming an out-of-order FIN', () async {
    final transport = _FakeTransport();
    final connectFuture = VirtualTcpSocket.connectIp(
      transport: transport,
      localAddress: '10.0.0.2',
      remoteAddress: '10.0.0.10',
      remotePort: 443,
      localPort: 50005,
      random: Random(6),
    );

    await Future<void>.delayed(Duration.zero);
    final syn = Ipv4TcpCodec.decode(transport.sentIpv4.single)!;
    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50005,
        sequenceNumber: 1000,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.syn | TcpFlags.ack,
      ),
    );
    final socket = await connectFuture;

    final received = <int>[];
    final streamDone = Completer<void>();
    final subscription = socket.stream.listen(received.addAll, onDone: streamDone.complete);

    // The tail arrives first and carries FIN. The socket must remain open while
    // bytes 1001..1003 are still missing.
    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50005,
        sequenceNumber: 1004,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.ack | TcpFlags.psh | TcpFlags.fin,
        payload: Uint8List.fromList([4, 5, 6]),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(received, isEmpty);
    expect(streamDone.isCompleted, isFalse);

    transport.controller.add(
      Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.10'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        sourcePort: 443,
        destinationPort: 50005,
        sequenceNumber: 1001,
        acknowledgementNumber: syn.sequenceNumber + 1,
        flags: TcpFlags.ack,
        payload: Uint8List.fromList([1, 2, 3]),
      ),
    );

    await streamDone.future.timeout(const Duration(seconds: 2));
    expect(received, [1, 2, 3, 4, 5, 6]);
    await Future<void>.delayed(Duration.zero);
    final finalAck = Ipv4TcpCodec.decode(transport.sentIpv4.last)!;
    expect(finalAck.acknowledgementNumber, 1008);

    await subscription.cancel();
    await transport.close();
  });
}
