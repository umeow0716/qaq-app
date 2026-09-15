import 'dart:typed_data';

typedef GlobalProtectTransportTrace = void Function(String message);

/// Raw IP packet transport for the userspace GlobalProtect stack.
///
/// Production GlobalProtect connections use ESP-over-UDP exclusively. The
/// abstraction keeps the virtual TCP/HTTP layers independent from ESP framing
/// details without providing any alternate/fallback data channel.
abstract interface class GlobalProtectTransport {
  Stream<Uint8List> get packets;

  Future<void> sendIpv4(Uint8List packet);

  Future<void> sendIpv6(Uint8List packet);

  Future<void> close();
}
