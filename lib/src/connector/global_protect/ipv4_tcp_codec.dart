import 'dart:typed_data';

class Ipv4TcpPacket {
  const Ipv4TcpPacket({
    required this.sourceAddress,
    required this.destinationAddress,
    required this.sourcePort,
    required this.destinationPort,
    required this.sequenceNumber,
    required this.acknowledgementNumber,
    required this.flags,
    required this.windowSize,
    required this.tcpOptions,
    required this.payload,
  });

  final InternetAddressValue sourceAddress;
  final InternetAddressValue destinationAddress;
  final int sourcePort;
  final int destinationPort;
  final int sequenceNumber;
  final int acknowledgementNumber;
  final int flags;
  final int windowSize;
  final Uint8List tcpOptions;
  final Uint8List payload;

  bool get syn => flags & TcpFlags.syn != 0;
  bool get ack => flags & TcpFlags.ack != 0;
  bool get fin => flags & TcpFlags.fin != 0;
  bool get rst => flags & TcpFlags.rst != 0;
}

class TcpFlags {
  static const int fin = 0x01;
  static const int syn = 0x02;
  static const int rst = 0x04;
  static const int psh = 0x08;
  static const int ack = 0x10;
}

class InternetAddressValue {
  const InternetAddressValue._(this.bytes);

  factory InternetAddressValue.parseIpv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) throw FormatException('Invalid IPv4 address: $address');
    final bytes = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      final value = int.tryParse(parts[i]);
      if (value == null || value < 0 || value > 255) {
        throw FormatException('Invalid IPv4 address: $address');
      }
      bytes[i] = value;
    }
    return InternetAddressValue._(bytes);
  }

  final Uint8List bytes;

  @override
  String toString() => bytes.join('.');

  @override
  bool operator ==(Object other) => other is InternetAddressValue && _bytesEqual(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class Ipv4TcpCodec {
  static const int _ipv4HeaderLength = 20;
  static const int _tcpHeaderLength = 20;
  static const int _tcpProtocol = 6;

  static Uint8List encode({
    required InternetAddressValue sourceAddress,
    required InternetAddressValue destinationAddress,
    required int sourcePort,
    required int destinationPort,
    required int sequenceNumber,
    required int acknowledgementNumber,
    required int flags,
    Uint8List? payload,
    Uint8List? tcpOptions,
    int windowSize = 65535,
    int identification = 0,
    int ttl = 64,
  }) {
    final tcpPayload = payload ?? Uint8List(0);
    final options = tcpOptions ?? Uint8List(0);
    if (options.length > 40 || options.length % 4 != 0) {
      throw ArgumentError.value(
        options.length,
        'tcpOptions.length',
        'TCP options must be 0-40 bytes and 32-bit aligned',
      );
    }
    final tcpHeaderLength = _tcpHeaderLength + options.length;
    final tcpLength = tcpHeaderLength + tcpPayload.length;
    final totalLength = _ipv4HeaderLength + tcpLength;
    if (totalLength > 0xffff) {
      throw ArgumentError.value(totalLength, 'totalLength', 'IPv4 packet exceeds 65535 bytes');
    }

    final packet = Uint8List(totalLength);
    final data = ByteData.sublistView(packet);

    packet[0] = 0x45;
    packet[1] = 0;
    data.setUint16(2, totalLength, Endian.big);
    data.setUint16(4, identification & 0xffff, Endian.big);
    data.setUint16(6, 0x4000, Endian.big);
    packet[8] = ttl;
    packet[9] = _tcpProtocol;
    packet.setRange(12, 16, sourceAddress.bytes);
    packet.setRange(16, 20, destinationAddress.bytes);
    data.setUint16(10, _checksum(packet, 0, _ipv4HeaderLength), Endian.big);

    final tcpOffset = _ipv4HeaderLength;
    data.setUint16(tcpOffset, sourcePort, Endian.big);
    data.setUint16(tcpOffset + 2, destinationPort, Endian.big);
    data.setUint32(tcpOffset + 4, sequenceNumber & 0xffffffff, Endian.big);
    data.setUint32(tcpOffset + 8, acknowledgementNumber & 0xffffffff, Endian.big);
    packet[tcpOffset + 12] = (tcpHeaderLength ~/ 4) << 4;
    packet[tcpOffset + 13] = flags;
    data.setUint16(tcpOffset + 14, windowSize, Endian.big);
    if (options.isNotEmpty) {
      packet.setRange(tcpOffset + _tcpHeaderLength, tcpOffset + tcpHeaderLength, options);
    }
    packet.setRange(tcpOffset + tcpHeaderLength, packet.length, tcpPayload);

    final pseudo = BytesBuilder(copy: false)
      ..add(sourceAddress.bytes)
      ..add(destinationAddress.bytes)
      ..add([0, _tcpProtocol, (tcpLength >> 8) & 0xff, tcpLength & 0xff])
      ..add(packet.sublist(tcpOffset));
    final tcpChecksum = _checksum(pseudo.toBytes(), 0, 12 + tcpLength);
    data.setUint16(tcpOffset + 16, tcpChecksum, Endian.big);

    return packet;
  }

  static Ipv4TcpPacket? decode(Uint8List packet) {
    if (packet.length < _ipv4HeaderLength) return null;
    final version = packet[0] >> 4;
    final ihl = (packet[0] & 0x0f) * 4;
    if (version != 4 || ihl < _ipv4HeaderLength || packet.length < ihl + _tcpHeaderLength) {
      return null;
    }
    if (packet[9] != _tcpProtocol) return null;

    final data = ByteData.sublistView(packet);
    final totalLength = data.getUint16(2, Endian.big);
    if (totalLength > packet.length || totalLength < ihl + _tcpHeaderLength) return null;

    final tcpOffset = ihl;
    final tcpHeaderLength = (packet[tcpOffset + 12] >> 4) * 4;
    if (tcpHeaderLength < _tcpHeaderLength || tcpOffset + tcpHeaderLength > totalLength) return null;

    return Ipv4TcpPacket(
      sourceAddress: InternetAddressValue._(Uint8List.fromList(packet.sublist(12, 16))),
      destinationAddress: InternetAddressValue._(Uint8List.fromList(packet.sublist(16, 20))),
      sourcePort: data.getUint16(tcpOffset, Endian.big),
      destinationPort: data.getUint16(tcpOffset + 2, Endian.big),
      sequenceNumber: data.getUint32(tcpOffset + 4, Endian.big),
      acknowledgementNumber: data.getUint32(tcpOffset + 8, Endian.big),
      flags: packet[tcpOffset + 13],
      windowSize: data.getUint16(tcpOffset + 14, Endian.big),
      tcpOptions: Uint8List.fromList(packet.sublist(tcpOffset + _tcpHeaderLength, tcpOffset + tcpHeaderLength)),
      payload: Uint8List.fromList(packet.sublist(tcpOffset + tcpHeaderLength, totalLength)),
    );
  }

  static int _checksum(Uint8List bytes, int offset, int length) {
    var sum = 0;
    var i = offset;
    final end = offset + length;
    while (i + 1 < end) {
      sum += (bytes[i] << 8) | bytes[i + 1];
      sum = (sum & 0xffff) + (sum >> 16);
      i += 2;
    }
    if (i < end) {
      sum += bytes[i] << 8;
      sum = (sum & 0xffff) + (sum >> 16);
    }
    while (sum >> 16 != 0) {
      sum = (sum & 0xffff) + (sum >> 16);
    }
    return (~sum) & 0xffff;
  }
}
