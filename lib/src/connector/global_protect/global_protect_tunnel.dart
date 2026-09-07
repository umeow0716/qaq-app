import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'global_protect_packet_transport.dart';
import 'gpst_packet_codec.dart';

typedef GlobalProtectTunnelTrace = void Function(String message);

class GlobalProtectTunnel implements GlobalProtectPacketTransport {
  GlobalProtectTunnel._(this._socket, this._iterator, List<int> initialBytes, this._trace) {
    if (initialBytes.isNotEmpty) {
      _handleBytes(initialBytes);
    }
    unawaited(_readLoop());
  }

  final SecureSocket _socket;
  final GlobalProtectTunnelTrace? _trace;
  final StreamIterator<List<int>> _iterator;
  final GpstPacketCodec _codec = GpstPacketCodec();
  final StreamController<Uint8List> _packets = StreamController<Uint8List>.broadcast();
  bool _closed = false;
  Future<void> _writeTail = Future<void>.value();

  @override
  Stream<Uint8List> get packets => _packets.stream;

  static Future<GlobalProtectTunnel> connect({
    required Uri gateway,
    required String tunnelPath,
    required Map<String, String> query,
    Duration timeout = const Duration(seconds: 10),
    GlobalProtectTunnelTrace? trace,
  }) async {
    final socket = await SecureSocket.connect(
      gateway.host,
      gateway.hasPort ? gateway.port : 443,
      timeout: timeout,
    );
    final iterator = StreamIterator<List<int>>(socket);

    final encodedQuery = query.entries
        .map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    socket.write('GET $tunnelPath?$encodedQuery HTTP/1.1\r\n\r\n');
    await socket.flush();

    const expected = 'START_TUNNEL';
    final prefix = <int>[];
    while (prefix.length < expected.length) {
      if (!await iterator.moveNext()) {
        await socket.close();
        throw const SocketException('GlobalProtect gateway closed before START_TUNNEL.');
      }
      prefix.addAll(iterator.current);
    }

    final responsePrefix = String.fromCharCodes(prefix.take(expected.length));
    if (responsePrefix != expected) {
      await socket.close();
      final text = String.fromCharCodes(prefix.take(256));
      throw StateError('GlobalProtect tunnel rejected: $text');
    }

    return GlobalProtectTunnel._(socket, iterator, prefix.skip(expected.length).toList(), trace);
  }

  @override
  Future<void> sendIpv4(Uint8List packet) => _send(packet, GpstPacketCodec.ipv4EtherType);

  @override
  Future<void> sendIpv6(Uint8List packet) => _send(packet, GpstPacketCodec.ipv6EtherType);

  Future<void> _send(Uint8List packet, int etherType) {
    return _queueFrame(_codec.encode(packet, etherType: etherType));
  }

  Future<void> _queueFrame(Uint8List frame) {
    final operation = _writeTail.then(
      (_) => _writeFrame(frame),
      onError: (_) => _writeFrame(frame),
    );
    _writeTail = operation;
    return operation;
  }

  Future<void> _writeFrame(Uint8List frame) async {
    if (_closed) throw StateError('GlobalProtect tunnel is closed.');
    _socket.add(frame);
    await _socket.flush();
  }

  Future<void> _readLoop() async {
    try {
      while (!_closed && await _iterator.moveNext()) {
        _handleBytes(_iterator.current);
      }
    } catch (error, stackTrace) {
      if (!_closed) _packets.addError(error, stackTrace);
    } finally {
      if (!_closed) {
        _closed = true;
        await _packets.close();
      }
    }
  }

  void _handleBytes(List<int> bytes) {
    final before = _codec.bufferedLength;
    final beforeExpected = _codec.nextFrameLength;
    _trace?.call(
      'RAW chunk=${bytes.length} bufferedBefore=$before'
      '${beforeExpected == null ? '' : ' expectedBefore=$beforeExpected'}',
    );

    final decoded = _codec.add(bytes);
    final after = _codec.bufferedLength;
    final afterExpected = _codec.nextFrameLength;
    _trace?.call(
      'RAW decoded=${decoded.length} bufferedAfter=$after'
      '${afterExpected == null ? '' : ' expectedAfter=$afterExpected'}',
    );

    for (final packet in decoded) {
      if (packet.isKeepalive) {
        unawaited(_queueFrame(_codec.encodeKeepalive()).catchError((Object error, StackTrace stackTrace) {
          if (!_closed) _packets.addError(error, stackTrace);
        }));
      } else {
        _trace?.call(_describePacket(packet));
        _packets.add(packet.payload);
      }
    }
  }

  String _describePacket(GpstPacket packet) {
    final payload = packet.payload;
    if (packet.etherType != GpstPacketCodec.ipv4EtherType || payload.length < 20) {
      return 'GPST eth=0x${packet.etherType.toRadixString(16)} len=${payload.length}';
    }

    final data = ByteData.sublistView(payload);
    final version = payload[0] >> 4;
    final ihl = (payload[0] & 0x0f) * 4;
    final totalLength = payload.length >= 4 ? data.getUint16(2, Endian.big) : -1;
    final flagsAndOffset = payload.length >= 8 ? data.getUint16(6, Endian.big) : 0;
    final fragmentOffset = flagsAndOffset & 0x1fff;
    final moreFragments = flagsAndOffset & 0x2000 != 0;
    final protocol = payload.length > 9 ? payload[9] : -1;
    final source = payload.length >= 16 ? payload.sublist(12, 16).join('.') : '?';
    final destination = payload.length >= 20 ? payload.sublist(16, 20).join('.') : '?';

    var tcp = '';
    if (version == 4 && protocol == 6 && fragmentOffset == 0 && ihl >= 20 && payload.length >= ihl + 20) {
      final sourcePort = data.getUint16(ihl, Endian.big);
      final destinationPort = data.getUint16(ihl + 2, Endian.big);
      final sequence = data.getUint32(ihl + 4, Endian.big);
      final acknowledgement = data.getUint32(ihl + 8, Endian.big);
      final tcpHeaderLength = (payload[ihl + 12] >> 4) * 4;
      final tcpPayloadLength = totalLength >= ihl + tcpHeaderLength
          ? totalLength - ihl - tcpHeaderLength
          : -1;
      tcp = ' tcp=$sourcePort->$destinationPort seq=$sequence ack=$acknowledgement tcpLen=$tcpPayloadLength';
    }

    return 'GPST len=${payload.length} ipTotal=$totalLength proto=$protocol '
        'fragOff=$fragmentOffset mf=$moreFragments $source->$destination$tcp';
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _iterator.cancel();
    await _socket.close();
    await _packets.close();
  }
}
