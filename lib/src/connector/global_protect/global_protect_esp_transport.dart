import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'global_protect_transport.dart';
import 'global_protect_esp_codec.dart';
import 'global_protect_models.dart';

class GlobalProtectEspTransport implements GlobalProtectTransport {
  GlobalProtectEspTransport._({
    required RawDatagramSocket socket,
    required InternetAddress gatewayAddress,
    required int gatewayPort,
    required String tunnelAddress,
    required String probeAddress,
    required GlobalProtectEspCodec codec,
    GlobalProtectTransportTrace? trace,
  })  : _socket = socket,
        _gatewayAddress = gatewayAddress,
        _gatewayPort = gatewayPort,
        _tunnelAddress = InternetAddress(tunnelAddress),
        _probeAddress = InternetAddress(probeAddress),
        _codec = codec,
        _trace = trace {
    _subscription = _socket.listen(_onSocketEvent, onError: _onSocketError, onDone: _onSocketDone);
  }

  final RawDatagramSocket _socket;
  final InternetAddress _gatewayAddress;
  final int _gatewayPort;
  final InternetAddress _tunnelAddress;
  final InternetAddress _probeAddress;
  final GlobalProtectEspCodec _codec;
  final GlobalProtectTransportTrace? _trace;
  final StreamController<Uint8List> _packets = StreamController<Uint8List>.broadcast();
  final Completer<void> _established = Completer<void>();
  late final StreamSubscription<RawSocketEvent> _subscription;
  Timer? _dpdTimer;
  bool _closed = false;
  int _probeSequence = 0;
  DateTime _lastRx = DateTime.now();
  DateTime _lastProbeAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _dpdInterval = Duration(seconds: 10);
  static const Duration _dpdFailureTimeout = Duration(seconds: 30);

  @override
  Stream<Uint8List> get packets => _packets.stream;

  bool get isEstablished => _established.isCompleted && !_closed;

  static Future<GlobalProtectEspTransport> connect({
    required Uri gateway,
    required GlobalProtectTunnelConfig config,
    Duration timeout = const Duration(seconds: 6),
    GlobalProtectTransportTrace? trace,
  }) async {
    final ipsec = config.ipsec;
    if (ipsec == null || !ipsec.hasCompleteNegotiationMaterial || ipsec.keyMaterial == null) {
      throw StateError('GlobalProtect gateway did not provide complete ESP material.');
    }
    final tunnelAddress = config.ipAddress;
    if (tunnelAddress == null || InternetAddress.tryParse(tunnelAddress)?.type != InternetAddressType.IPv4) {
      throw StateError('GlobalProtect ESP requires an IPv4 tunnel address.');
    }
    if (ipsec.udpPort == null) {
      throw StateError('GlobalProtect ESP UDP port is unavailable.');
    }

    final resolved = InternetAddress.tryParse(gateway.host) ??
        (await InternetAddress.lookup(gateway.host, type: InternetAddressType.IPv4)).first;
    final probeAddress = config.gatewayAddress ?? resolved.address;
    if (InternetAddress.tryParse(probeAddress)?.type != InternetAddressType.IPv4) {
      throw StateError('GlobalProtect ESP probe address is not IPv4: $probeAddress');
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final transport = GlobalProtectEspTransport._(
      socket: socket,
      gatewayAddress: resolved,
      gatewayPort: ipsec.udpPort!,
      tunnelAddress: tunnelAddress,
      probeAddress: probeAddress,
      codec: GlobalProtectEspCodec.fromConfig(ipsec),
      trace: trace,
    );
    trace?.call(
      'UDP bound=${socket.address.address}:${socket.port} gateway=${resolved.address}:${ipsec.udpPort} '
      'probe=$probeAddress',
    );

    try {
      await transport._sendInitialProbes();
      await transport._established.future.timeout(timeout);
      transport._startDpd();
      return transport;
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  Future<void> _sendInitialProbes() async {
    for (var i = 0; i < 3; i++) {
      await _sendProbe();
    }
  }

  Future<void> _sendProbe() async {
    _probeSequence = (_probeSequence + 1) & 0xffff;
    final packet = _buildProbePacket(_probeSequence);
    final encoded = _codec.encode(packet, nextHeader: GlobalProtectEspCodec.ipv4NextHeader);
    final sent = _socket.send(encoded, _gatewayAddress, _gatewayPort);
    if (sent != encoded.length) {
      throw SocketException('ESP probe UDP send wrote $sent/${encoded.length} bytes.');
    }
    _lastProbeAt = DateTime.now();
    _trace?.call('ESP probe sent seq=$_probeSequence');
  }

  void _startDpd() {
    _dpdTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_closed) return;
      final now = DateTime.now();
      final idle = now.difference(_lastRx);
      if (idle >= _dpdFailureTimeout) {
        _trace?.call('ESP DPD timed out after ${_dpdFailureTimeout.inSeconds}s');
        _fail(
          TimeoutException(
            'GlobalProtect ESP stopped responding for ${_dpdFailureTimeout.inSeconds}s.',
          ),
          StackTrace.current,
        );
        return;
      }
      if (idle < _dpdInterval || now.difference(_lastProbeAt) < _dpdInterval) return;
      unawaited(
        _sendProbe().catchError((Object error, StackTrace stackTrace) {
          _fail(error, stackTrace);
        }),
      );
    });
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (_closed || event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket.receive()) != null) {
      final bytes = Uint8List.fromList(datagram!.data);
      final decoded = _codec.decode(bytes);
      if (decoded == null) {
        _trace?.call('RX rejected udpBytes=${bytes.length}');
        continue;
      }
      _lastRx = DateTime.now();
      if (_isProbeReply(decoded)) {
        if (!_established.isCompleted) {
          _trace?.call('ESP session established by ICMP probe reply');
          _established.complete();
        }
        continue;
      }
      if (!_established.isCompleted) {
        _trace?.call('ESP session established by authenticated data packet');
        _established.complete();
      }
      if (decoded.nextHeader == GlobalProtectEspCodec.ipv4NextHeader ||
          decoded.nextHeader == GlobalProtectEspCodec.ipv6NextHeader) {
        _packets.add(decoded.payload);
      }
    }
  }

  void _onSocketError(Object error, StackTrace stackTrace) => _fail(error, stackTrace);

  void _fail(Object error, StackTrace stackTrace) {
    if (_closed) return;
    if (!_established.isCompleted) {
      _established.completeError(error, stackTrace);
    } else if (!_packets.isClosed) {
      _packets.addError(error, stackTrace);
    }
    unawaited(close());
  }

  void _onSocketDone() {
    if (_closed) return;
    if (!_established.isCompleted) {
      _established.completeError(StateError('ESP UDP socket closed before establishment.'));
    }
    unawaited(close());
  }

  bool _isProbeReply(GlobalProtectEspPacket packet) {
    if (packet.nextHeader != GlobalProtectEspCodec.ipv4NextHeader || packet.payload.length < 21) {
      return false;
    }
    final bytes = packet.payload;
    if ((bytes[0] >> 4) != 4) return false;
    final ihl = (bytes[0] & 0x0f) * 4;
    if (ihl < 20 || bytes.length <= ihl || bytes[9] != 1) return false;
    final source = InternetAddress.fromRawAddress(Uint8List.fromList(bytes.sublist(12, 16)));
    return source.address == _probeAddress.address && bytes[ihl] == 0;
  }

  Uint8List _buildProbePacket(int sequence) {
    const magic = <int>[109, 111, 110, 105, 116, 111, 114, 0, 0, 112, 97, 110, 32, 104, 97, 32];
    const ipHeaderLength = 20;
    const icmpHeaderLength = 8;
    final packet = Uint8List(ipHeaderLength + icmpHeaderLength + magic.length);
    final data = ByteData.sublistView(packet);

    packet[0] = 0x45;
    packet[1] = 0;
    data.setUint16(2, packet.length, Endian.big);
    data.setUint16(4, 0x4747, Endian.big);
    data.setUint16(6, 0x4000, Endian.big);
    packet[8] = 64;
    packet[9] = 1;
    packet.setRange(12, 16, _tunnelAddress.rawAddress);
    packet.setRange(16, 20, _probeAddress.rawAddress);
    data.setUint16(10, _internetChecksum(Uint8List.sublistView(packet, 0, ipHeaderLength)), Endian.big);

    final icmpOffset = ipHeaderLength;
    packet[icmpOffset] = 8;
    packet[icmpOffset + 1] = 0;
    data.setUint16(icmpOffset + 4, 0x4747, Endian.big);
    data.setUint16(icmpOffset + 6, sequence, Endian.big);
    packet.setRange(icmpOffset + icmpHeaderLength, packet.length, magic);
    data.setUint16(
      icmpOffset + 2,
      _internetChecksum(Uint8List.sublistView(packet, icmpOffset)),
      Endian.big,
    );
    return packet;
  }

  @override
  Future<void> sendIpv4(Uint8List packet) => _send(packet, GlobalProtectEspCodec.ipv4NextHeader);

  @override
  Future<void> sendIpv6(Uint8List packet) => _send(packet, GlobalProtectEspCodec.ipv6NextHeader);

  Future<void> _send(Uint8List packet, int nextHeader) async {
    if (_closed) throw StateError('ESP transport is closed.');
    if (!_established.isCompleted) throw StateError('ESP transport is not established.');
    final encoded = _codec.encode(packet, nextHeader: nextHeader);
    final sent = _socket.send(encoded, _gatewayAddress, _gatewayPort);
    if (sent != encoded.length) {
      throw SocketException('ESP UDP send wrote $sent/${encoded.length} bytes.');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _dpdTimer?.cancel();
    _socket.close();
    await _subscription.cancel();
    await _packets.close();
  }

  static int _internetChecksum(Uint8List bytes) {
    var sum = 0;
    var i = 0;
    while (i + 1 < bytes.length) {
      sum += (bytes[i] << 8) | bytes[i + 1];
      sum = (sum & 0xffff) + (sum >> 16);
      i += 2;
    }
    if (i < bytes.length) {
      sum += bytes[i] << 8;
      sum = (sum & 0xffff) + (sum >> 16);
    }
    while ((sum >> 16) != 0) {
      sum = (sum & 0xffff) + (sum >> 16);
    }
    return (~sum) & 0xffff;
  }
}
