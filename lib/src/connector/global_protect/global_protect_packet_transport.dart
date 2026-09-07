import 'dart:typed_data';

abstract interface class GlobalProtectPacketTransport {
  Stream<Uint8List> get packets;

  Future<void> sendIpv4(Uint8List packet);

  Future<void> sendIpv6(Uint8List packet);
}
