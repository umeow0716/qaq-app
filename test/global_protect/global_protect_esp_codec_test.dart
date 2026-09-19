import 'dart:math';
import 'dart:typed_data';

import 'package:qaq_app/src/connector/global_protect/global_protect_esp_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AES-128-CBC/HMAC-SHA1-96 ESP round-trips IPv4 payload', () {
    final encryptionKey = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final authenticationKey = Uint8List.fromList(List<int>.generate(20, (i) => 0xa0 + i));
    final codec = GlobalProtectEspCodec(
      outboundSpi: 0x11223344,
      outboundEncryptionKey: encryptionKey,
      outboundAuthenticationKey: authenticationKey,
      inboundSpi: 0x11223344,
      inboundEncryptionKey: encryptionKey,
      inboundAuthenticationKey: authenticationKey,
      random: Random(1234),
    );
    final payload = Uint8List.fromList(List<int>.generate(91, (i) => (i * 7) & 0xff));

    final encoded = codec.encode(payload, nextHeader: GlobalProtectEspCodec.ipv4NextHeader);
    final decoded = codec.decode(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.sequence, 0);
    expect(decoded.nextHeader, GlobalProtectEspCodec.ipv4NextHeader);
    expect(decoded.payload, orderedEquals(payload));
  });

  test('rejects tampered ESP authentication tag', () {
    final key = Uint8List(16);
    final auth = Uint8List(20);
    final codec = GlobalProtectEspCodec(
      outboundSpi: 7,
      outboundEncryptionKey: key,
      outboundAuthenticationKey: auth,
      inboundSpi: 7,
      inboundEncryptionKey: key,
      inboundAuthenticationKey: auth,
      random: Random(7),
    );
    final encoded = codec.encode(Uint8List.fromList([0x45, 1, 2, 3]), nextHeader: 4);
    encoded[encoded.length - 1] ^= 1;
    expect(codec.decode(encoded), isNull);
  });

  test('rejects duplicate ESP sequence number', () {
    final key = Uint8List(16);
    final auth = Uint8List(20);
    final codec = GlobalProtectEspCodec(
      outboundSpi: 9,
      outboundEncryptionKey: key,
      outboundAuthenticationKey: auth,
      inboundSpi: 9,
      inboundEncryptionKey: key,
      inboundAuthenticationKey: auth,
      random: Random(9),
    );
    final encoded = codec.encode(Uint8List.fromList([0x45, 9, 8, 7]), nextHeader: 4);
    expect(codec.decode(encoded), isNotNull);
    expect(codec.decode(encoded), isNull);
  });
}
