import 'dart:typed_data';

import 'package:qaq_app/src/connector/global_protect/ipv4_tcp_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ipv4TcpCodec', () {
    test('encodes and decodes a SYN packet', () {
      final packet = Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.0.0.2'),
        destinationAddress: InternetAddressValue.parseIpv4('10.0.0.1'),
        sourcePort: 50000,
        destinationPort: 443,
        sequenceNumber: 12345,
        acknowledgementNumber: 0,
        flags: TcpFlags.syn,
      );

      final decoded = Ipv4TcpCodec.decode(packet);
      expect(decoded, isNotNull);
      expect(decoded!.sourceAddress.toString(), '10.0.0.2');
      expect(decoded.destinationAddress.toString(), '10.0.0.1');
      expect(decoded.sourcePort, 50000);
      expect(decoded.destinationPort, 443);
      expect(decoded.sequenceNumber, 12345);
      expect(decoded.syn, isTrue);
      expect(decoded.ack, isFalse);
      expect(decoded.payload, isEmpty);
    });

    test('round trips TCP payload', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final packet = Ipv4TcpCodec.encode(
        sourceAddress: InternetAddressValue.parseIpv4('10.1.2.3'),
        destinationAddress: InternetAddressValue.parseIpv4('10.9.8.7'),
        sourcePort: 1234,
        destinationPort: 443,
        sequenceNumber: 100,
        acknowledgementNumber: 200,
        flags: TcpFlags.ack | TcpFlags.psh,
        payload: payload,
      );

      final decoded = Ipv4TcpCodec.decode(packet);
      expect(decoded, isNotNull);
      expect(decoded!.ack, isTrue);
      expect(decoded.payload, payload);
      expect(decoded.acknowledgementNumber, 200);
    });

    test('ignores non TCP IPv4 packets', () {
      final packet = Uint8List(20);
      packet[0] = 0x45;
      packet[9] = 17;
      expect(Ipv4TcpCodec.decode(packet), isNull);
    });
  });

  test('encodes and decodes TCP MSS option on SYN', () {
    final packet = Ipv4TcpCodec.encode(
      sourceAddress: InternetAddressValue.parseIpv4('172.24.1.10'),
      destinationAddress: InternetAddressValue.parseIpv4('140.124.13.231'),
      sourcePort: 50000,
      destinationPort: 443,
      sequenceNumber: 123,
      acknowledgementNumber: 0,
      flags: TcpFlags.syn,
      tcpOptions: Uint8List.fromList(<int>[2, 4, 0x04, 0xb0]),
    );

    final decoded = Ipv4TcpCodec.decode(packet)!;
    expect(decoded.syn, isTrue);
    expect(decoded.tcpOptions, <int>[2, 4, 0x04, 0xb0]);
    expect(decoded.payload, isEmpty);
    expect(packet[20 + 12] >> 4, 6);
  });
}
