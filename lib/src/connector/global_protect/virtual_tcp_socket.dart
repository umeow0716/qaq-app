import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'global_protect_packet_transport.dart';
import 'ipv4_tcp_codec.dart';
import 'virtual_byte_socket.dart';
import 'virtual_tcp_loopback_bridge.dart';

typedef VirtualTcpTrace = void Function(String message);

class VirtualTcpSocket implements VirtualByteSocket {
  VirtualTcpSocket._({
    required GlobalProtectPacketTransport tunnel,
    required this.localAddress,
    required this.remoteAddress,
    required this.localPort,
    required this.remotePort,
    required int initialSequence,
    required this.maxSegmentPayload,
    VirtualTcpTrace? trace,
  })  : _tunnel = tunnel,
        _trace = trace,
        _sendSequence = initialSequence;

  final GlobalProtectPacketTransport _tunnel;
  final VirtualTcpTrace? _trace;
  final InternetAddressValue localAddress;
  final InternetAddressValue remoteAddress;
  final int localPort;
  final int remotePort;
  final int maxSegmentPayload;
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _packetSubscription;

  int _sendSequence;
  int _receiveSequence = 0;
  final Map<int, Uint8List> _outOfOrder = <int, Uint8List>{};
  bool _connected = false;
  bool _closed = false;
  Future<void> _writeTail = Future<void>.value();
  Completer<void>? _connectCompleter;

  @override
  Stream<Uint8List> get stream => _incoming.stream;
  bool get isConnected => _connected && !_closed;

  Future<VirtualTcpLoopbackBridge> createLoopbackBridge({
    Duration timeout = const Duration(seconds: 5),
  }) => VirtualTcpLoopbackBridge.attach(this, timeout: timeout);

  static Future<VirtualTcpSocket> connectIp({
    required GlobalProtectPacketTransport tunnel,
    required String localAddress,
    required String remoteAddress,
    required int remotePort,
    int? localPort,
    Duration timeout = const Duration(seconds: 8),
    Random? random,
    int maxSegmentPayload = 1200,
    VirtualTcpTrace? trace,
  }) async {
    if (maxSegmentPayload <= 0 || maxSegmentPayload > 0xffff - 40) {
      throw ArgumentError.value(maxSegmentPayload, 'maxSegmentPayload');
    }
    final rng = random ?? Random.secure();
    final socket = VirtualTcpSocket._(
      tunnel: tunnel,
      localAddress: InternetAddressValue.parseIpv4(localAddress),
      remoteAddress: InternetAddressValue.parseIpv4(remoteAddress),
      localPort: localPort ?? (49152 + rng.nextInt(16384)),
      remotePort: remotePort,
      initialSequence: rng.nextInt(0x7fffffff),
      maxSegmentPayload: maxSegmentPayload,
      trace: trace,
    );
    await socket._connect(timeout);
    return socket;
  }

  Future<void> _connect(Duration timeout) async {
    _connectCompleter = Completer<void>();
    _packetSubscription = _tunnel.packets.listen(
      _handlePacket,
      onError: (Object error, StackTrace stackTrace) {
        if (!(_connectCompleter?.isCompleted ?? true)) {
          _connectCompleter!.completeError(error, stackTrace);
        } else {
          _incoming.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!(_connectCompleter?.isCompleted ?? true)) {
          _connectCompleter!.completeError(StateError('GlobalProtect tunnel closed during TCP connect.'));
        }
        unawaited(close(sendFin: false));
      },
    );

    final synSequence = _sendSequence;
    await _send(flags: TcpFlags.syn, sequence: synSequence);

    try {
      await _connectCompleter!.future.timeout(timeout);
    } on Object {
      await close(sendFin: false);
      rethrow;
    }
  }

  @override
  Future<void> write(Uint8List data) {
    if (data.isEmpty) return Future<void>.value();

    // The loopback TLS bridge can deliver multiple chunks without awaiting the
    // previous write. TCP sequence numbers are shared mutable state, so every
    // outbound application write must be serialized or two concurrent writes
    // can emit segments with the same sequence number. Copy the bytes because
    // the caller may reuse its buffer before the queued write runs.
    final copy = Uint8List.fromList(data);
    final operation = _writeTail.then((_) => _writeSerialized(copy));
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _writeSerialized(Uint8List data) async {
    if (!isConnected) throw StateError('Virtual TCP socket is not connected.');

    var offset = 0;
    while (offset < data.length) {
      final remaining = data.length - offset;
      final chunkLength = remaining > maxSegmentPayload ? maxSegmentPayload : remaining;
      final isLast = offset + chunkLength == data.length;
      final chunk = Uint8List.sublistView(data, offset, offset + chunkLength);
      final sequence = _sendSequence;
      await _send(
        flags: TcpFlags.ack | (isLast ? TcpFlags.psh : 0),
        sequence: sequence,
        acknowledgement: _receiveSequence,
        payload: chunk,
      );
      _sendSequence = _add32(sequence, chunkLength);
      offset += chunkLength;
    }
  }

  void _handlePacket(Uint8List rawPacket) {
    if (_closed) return;
    final packet = Ipv4TcpCodec.decode(rawPacket);
    if (packet == null || !_matches(packet)) return;

    _trace?.call(
      'RX seq=${packet.sequenceNumber} ack=${packet.acknowledgementNumber} '
      'flags=${_flagsText(packet.flags)} len=${packet.payload.length} win=${packet.windowSize}',
    );

    if (packet.rst) {
      final error = SocketException('Remote host reset the virtual TCP connection.');
      if (!(_connectCompleter?.isCompleted ?? true)) {
        _connectCompleter!.completeError(error);
      } else {
        _incoming.addError(error);
      }
      unawaited(close(sendFin: false));
      return;
    }

    if (!_connected) {
      if (!packet.syn || !packet.ack || packet.acknowledgementNumber != _add32(_sendSequence, 1)) return;
      _sendSequence = _add32(_sendSequence, 1);
      _receiveSequence = _add32(packet.sequenceNumber, 1);
      _connected = true;
      unawaited(_send(flags: TcpFlags.ack, sequence: _sendSequence, acknowledgement: _receiveSequence));
      _connectCompleter?.complete();
      return;
    }

    final payloadLength = packet.payload.length;
    if (payloadLength > 0) {
      _handlePayload(packet.sequenceNumber, packet.payload);
    }

    if (packet.fin) {
      final finSequence = _add32(packet.sequenceNumber, payloadLength);
      if (finSequence == _receiveSequence) {
        _receiveSequence = _add32(_receiveSequence, 1);
        unawaited(_send(flags: TcpFlags.ack, sequence: _sendSequence, acknowledgement: _receiveSequence));
      }
      unawaited(close(sendFin: false));
    }
  }

  void _handlePayload(int sequence, Uint8List payload) {
    if (sequence == _receiveSequence) {
      _deliverPayload(payload);
      _drainOutOfOrder();
      return;
    }

    // Duplicate/retransmitted data that is already fully acknowledged.
    if (_sequenceBefore(sequence, _receiveSequence)) {
      unawaited(_send(
        flags: TcpFlags.ack,
        sequence: _sendSequence,
        acknowledgement: _receiveSequence,
      ));
      return;
    }

    // A later segment arrived first. Keep it until the gap is filled and send
    // a duplicate ACK advertising the next byte we still expect. This is
    // enough for TLS handshakes where certificate data is commonly split over
    // several TCP segments.
    _outOfOrder.putIfAbsent(sequence, () => Uint8List.fromList(payload));
    unawaited(_send(
      flags: TcpFlags.ack,
      sequence: _sendSequence,
      acknowledgement: _receiveSequence,
    ));
  }

  void _deliverPayload(Uint8List payload) {
    _receiveSequence = _add32(_receiveSequence, payload.length);
    _incoming.add(payload);
    unawaited(_send(
      flags: TcpFlags.ack,
      sequence: _sendSequence,
      acknowledgement: _receiveSequence,
    ));
  }

  void _drainOutOfOrder() {
    while (true) {
      final next = _outOfOrder.remove(_receiveSequence);
      if (next == null) return;
      _deliverPayload(next);
    }
  }

  static bool _sequenceBefore(int a, int b) =>
      ((a - b) & 0xffffffff) > 0x7fffffff;

  bool _matches(Ipv4TcpPacket packet) =>
      packet.sourceAddress == remoteAddress &&
      packet.destinationAddress == localAddress &&
      packet.sourcePort == remotePort &&
      packet.destinationPort == localPort;

  Uint8List _synOptions() => Uint8List.fromList(<int>[
        2, // MSS option kind
        4, // MSS option length
        (maxSegmentPayload >> 8) & 0xff,
        maxSegmentPayload & 0xff,
      ]);

  Future<void> _send({
    required int flags,
    required int sequence,
    int acknowledgement = 0,
    Uint8List? payload,
  }) async {
    final payloadLength = payload?.length ?? 0;
    _trace?.call(
      'TX seq=$sequence ack=$acknowledgement '
      'flags=${_flagsText(flags)} len=$payloadLength',
    );
    final packet = Ipv4TcpCodec.encode(
      sourceAddress: localAddress,
      destinationAddress: remoteAddress,
      sourcePort: localPort,
      destinationPort: remotePort,
      sequenceNumber: sequence,
      acknowledgementNumber: acknowledgement,
      flags: flags,
      payload: payload,
      tcpOptions: flags & TcpFlags.syn != 0 ? _synOptions() : null,
    );
    await _tunnel.sendIpv4(packet);
  }

  static String _flagsText(int flags) {
    final names = <String>[];
    if (flags & TcpFlags.syn != 0) names.add('SYN');
    if (flags & TcpFlags.ack != 0) names.add('ACK');
    if (flags & TcpFlags.psh != 0) names.add('PSH');
    if (flags & TcpFlags.fin != 0) names.add('FIN');
    if (flags & TcpFlags.rst != 0) names.add('RST');
    return names.isEmpty ? 'NONE' : names.join('|');
  }

  @override
  Future<void> close({bool sendFin = true}) async {
    if (_closed) return;
    _closed = true;

    Object? closeError;
    StackTrace? closeStackTrace;
    try {
      if (sendFin && _connected) {
        await _send(
          flags: TcpFlags.fin | TcpFlags.ack,
          sequence: _sendSequence,
          acknowledgement: _receiveSequence,
        );
        _sendSequence = _add32(_sendSequence, 1);
      }
    } catch (error, stackTrace) {
      // The underlying GP transport may already be gone. Cleanup must still
      // complete so a failed FIN does not leave subscriptions/controllers
      // alive indefinitely.
      closeError = error;
      closeStackTrace = stackTrace;
    } finally {
      await _packetSubscription.cancel();

      // A single-subscription StreamController does not complete close() until
      // its done event can be delivered. If nobody ever listened to `stream`,
      // awaiting that Future would make socket.close() hang forever.
      final hasIncomingListener = _incoming.hasListener;
      final incomingClosed = _incoming.close();
      if (hasIncomingListener) {
        await incomingClosed;
      }
    }

    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace!);
    }
  }

  static int _add32(int value, int increment) => (value + increment) & 0xffffffff;
}
