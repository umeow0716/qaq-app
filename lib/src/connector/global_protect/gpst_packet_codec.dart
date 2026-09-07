import 'dart:typed_data';

class GpstPacket {
  const GpstPacket({required this.etherType, required this.payload, this.isKeepalive = false});

  final int etherType;
  final Uint8List payload;
  final bool isKeepalive;
}

class GpstPacketCodec {
  static const int headerLength = 16;
  static const int ipv4EtherType = 0x0800;
  static const int ipv6EtherType = 0x86dd;
  static const List<int> _magic = [0x1a, 0x2b, 0x3c, 0x4d];

  final List<int> _buffer = [];

  int get bufferedLength => _buffer.length;

  int? get nextFrameLength {
    if (_buffer.length < headerLength) return null;
    if (!_hasMagicAtStart()) return null;
    final header = Uint8List.fromList(_buffer.sublist(0, headerLength));
    final data = ByteData.sublistView(header);
    return headerLength + data.getUint16(6, Endian.big);
  }

  Uint8List encode(Uint8List payload, {required int etherType}) {
    if (payload.length > 0xffff) {
      throw ArgumentError.value(payload.length, 'payload.length', 'GPST payload exceeds 65535 bytes');
    }

    final frame = Uint8List(headerLength + payload.length);
    final data = ByteData.sublistView(frame);
    frame.setRange(0, 4, _magic);
    data.setUint16(4, etherType, Endian.big);
    data.setUint16(6, payload.length, Endian.big);
    frame[8] = 1;
    frame.setRange(headerLength, frame.length, payload);
    return frame;
  }

  Uint8List encodeKeepalive() {
    final frame = Uint8List(headerLength);
    frame.setRange(0, 4, _magic);
    return frame;
  }

  List<GpstPacket> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final packets = <GpstPacket>[];

    while (_buffer.length >= headerLength) {
      if (!_hasMagicAtStart()) {
        throw const FormatException('Invalid GlobalProtect SSL tunnel packet magic.');
      }

      final header = Uint8List.fromList(_buffer.sublist(0, headerLength));
      final data = ByteData.sublistView(header);
      final etherType = data.getUint16(4, Endian.big);
      final payloadLength = data.getUint16(6, Endian.big);
      final frameLength = headerLength + payloadLength;
      if (_buffer.length < frameLength) break;

      final marker = header[8];
      final trailingZero = header.sublist(9).every((value) => value == 0);
      if (!trailingZero) {
        throw const FormatException('Invalid GlobalProtect SSL tunnel packet header.');
      }

      final payload = Uint8List.fromList(_buffer.sublist(headerLength, frameLength));
      _buffer.removeRange(0, frameLength);

      if (etherType == 0 && payloadLength == 0 && marker == 0) {
        packets.add(GpstPacket(etherType: etherType, payload: payload, isKeepalive: true));
        continue;
      }

      if (marker != 1 || (etherType != ipv4EtherType && etherType != ipv6EtherType)) {
        throw FormatException('Unsupported GlobalProtect packet type: 0x${etherType.toRadixString(16)}');
      }

      packets.add(GpstPacket(etherType: etherType, payload: payload));
    }

    return packets;
  }

  bool _hasMagicAtStart() {
    for (var i = 0; i < _magic.length; i++) {
      if (_buffer[i] != _magic[i]) return false;
    }
    return true;
  }
}
