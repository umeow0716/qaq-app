import 'dart:typed_data';

import 'package:flutter_app/src/connector/global_protect/gpst_packet_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpstPacketCodec', () {
    test('encodes and decodes an IPv4 packet', () {
      final codec = GpstPacketCodec();
      final payload = Uint8List.fromList([0x45, 0x00, 0x00, 0x14]);

      final frame = codec.encode(payload, etherType: GpstPacketCodec.ipv4EtherType);
      final packets = codec.add(frame);

      expect(frame.sublist(0, 4), [0x1a, 0x2b, 0x3c, 0x4d]);
      expect(packets, hasLength(1));
      expect(packets.single.etherType, GpstPacketCodec.ipv4EtherType);
      expect(packets.single.payload, payload);
      expect(packets.single.isKeepalive, isFalse);
    });

    test('buffers a packet split across socket reads', () {
      final codec = GpstPacketCodec();
      final payload = Uint8List.fromList(List<int>.generate(32, (index) => index));
      final frame = codec.encode(payload, etherType: GpstPacketCodec.ipv4EtherType);

      expect(codec.add(frame.sublist(0, 7)), isEmpty);
      expect(codec.add(frame.sublist(7, 21)), isEmpty);
      final packets = codec.add(frame.sublist(21));

      expect(packets, hasLength(1));
      expect(packets.single.payload, payload);
    });

    test('recognizes GPST keepalive packets', () {
      final codec = GpstPacketCodec();
      final packets = codec.add(codec.encodeKeepalive());

      expect(packets, hasLength(1));
      expect(packets.single.isKeepalive, isTrue);
      expect(packets.single.payload, isEmpty);
    });
  });
}
