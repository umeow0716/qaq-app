import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'global_protect_models.dart';

class GlobalProtectEspPacket {
  const GlobalProtectEspPacket({
    required this.sequence,
    required this.nextHeader,
    required this.payload,
  });

  final int sequence;
  final int nextHeader;
  final Uint8List payload;
}

/// Minimal ESP codec for the algorithms currently advertised by the NTUT
/// GlobalProtect gateway: AES-128-CBC + HMAC-SHA1-96 in tunnel mode.
class GlobalProtectEspCodec {
  GlobalProtectEspCodec({
    required this.outboundSpi,
    required Uint8List outboundEncryptionKey,
    required Uint8List outboundAuthenticationKey,
    required this.inboundSpi,
    required Uint8List inboundEncryptionKey,
    required Uint8List inboundAuthenticationKey,
    Random? random,
  })  : _outboundEncryptionKey = Uint8List.fromList(outboundEncryptionKey),
        _outboundAuthenticationKey = Uint8List.fromList(outboundAuthenticationKey),
        _inboundEncryptionKey = Uint8List.fromList(inboundEncryptionKey),
        _inboundAuthenticationKey = Uint8List.fromList(inboundAuthenticationKey),
        _random = random ?? Random.secure() {
    if (_outboundEncryptionKey.length != 16 || _inboundEncryptionKey.length != 16) {
      throw ArgumentError('ESP AES-128-CBC requires 16-byte encryption keys.');
    }
    if (_outboundAuthenticationKey.length != 20 || _inboundAuthenticationKey.length != 20) {
      throw ArgumentError('ESP HMAC-SHA1 requires 20-byte authentication keys.');
    }
  }

  factory GlobalProtectEspCodec.fromConfig(GlobalProtectIpsecConfig config) {
    if (config.mode != 'esp-tunnel') {
      throw UnsupportedError('Unsupported GlobalProtect IPsec mode: ${config.mode}');
    }
    if (config.encryptionAlgorithm != 'aes-128-cbc' && config.encryptionAlgorithm != 'aes128') {
      throw UnsupportedError(
        'Unsupported GlobalProtect ESP encryption algorithm: ${config.encryptionAlgorithm}',
      );
    }
    if (config.authenticationAlgorithm != 'sha1') {
      throw UnsupportedError(
        'Unsupported GlobalProtect ESP authentication algorithm: ${config.authenticationAlgorithm}',
      );
    }
    final material = config.keyMaterial;
    if (material == null) {
      throw StateError('GlobalProtect ESP key material is unavailable.');
    }
    return GlobalProtectEspCodec(
      outboundSpi: material.clientToServerSpi,
      outboundEncryptionKey: material.clientToServerEncryptionKey,
      outboundAuthenticationKey: material.clientToServerAuthenticationKey,
      inboundSpi: material.serverToClientSpi,
      inboundEncryptionKey: material.serverToClientEncryptionKey,
      inboundAuthenticationKey: material.serverToClientAuthenticationKey,
    );
  }

  static const int ipv4NextHeader = 4;
  static const int ipv6NextHeader = 41;
  static const int _headerLength = 8;
  static const int _ivLength = 16;
  static const int _authLength = 12;
  static const int _blockSize = 16;

  final int outboundSpi;
  final int inboundSpi;
  final Uint8List _outboundEncryptionKey;
  final Uint8List _outboundAuthenticationKey;
  final Uint8List _inboundEncryptionKey;
  final Uint8List _inboundAuthenticationKey;
  final Random _random;

  int _outboundSequence = 0;
  int _highestInboundSequence = -1;
  int _inboundReplayBitmap = 0;

  Uint8List encode(Uint8List payload, {required int nextHeader}) {
    if (nextHeader != ipv4NextHeader && nextHeader != ipv6NextHeader) {
      throw ArgumentError.value(nextHeader, 'nextHeader');
    }

    final sequence = _outboundSequence & 0xffffffff;
    _outboundSequence = (_outboundSequence + 1) & 0xffffffff;

    final padLength = (_blockSize - ((payload.length + 2) % _blockSize)) % _blockSize;
    final plaintext = Uint8List(payload.length + padLength + 2);
    plaintext.setRange(0, payload.length, payload);
    for (var i = 0; i < padLength; i++) {
      plaintext[payload.length + i] = i + 1;
    }
    plaintext[plaintext.length - 2] = padLength;
    plaintext[plaintext.length - 1] = nextHeader;

    final iv = Uint8List(_ivLength);
    for (var i = 0; i < iv.length; i++) {
      iv[i] = _random.nextInt(256);
    }
    final ciphertext = _cryptCbc(
      plaintext,
      _outboundEncryptionKey,
      iv,
      encrypt: true,
    );

    final authenticated = Uint8List(_headerLength + _ivLength + ciphertext.length);
    final data = ByteData.sublistView(authenticated);
    data.setUint32(0, outboundSpi, Endian.big);
    data.setUint32(4, sequence, Endian.big);
    authenticated.setRange(_headerLength, _headerLength + _ivLength, iv);
    authenticated.setRange(_headerLength + _ivLength, authenticated.length, ciphertext);

    final mac = Hmac(sha1, _outboundAuthenticationKey).convert(authenticated).bytes;
    final packet = Uint8List(authenticated.length + _authLength);
    packet.setRange(0, authenticated.length, authenticated);
    packet.setRange(authenticated.length, packet.length, mac.take(_authLength));
    return packet;
  }

  GlobalProtectEspPacket? decode(Uint8List packet) {
    if (packet.length < _headerLength + _ivLength + _blockSize + _authLength) {
      return null;
    }
    final data = ByteData.sublistView(packet);
    final spi = data.getUint32(0, Endian.big);
    if (spi != inboundSpi) return null;
    final sequence = data.getUint32(4, Endian.big);

    final authenticatedLength = packet.length - _authLength;
    final authenticated = Uint8List.sublistView(packet, 0, authenticatedLength);
    final receivedMac = Uint8List.sublistView(packet, authenticatedLength);
    final expectedMac = Hmac(sha1, _inboundAuthenticationKey).convert(authenticated).bytes;
    if (!_constantTimePrefixEquals(expectedMac, receivedMac, _authLength)) {
      return null;
    }
    if (!_acceptInboundSequence(sequence)) return null;

    final iv = Uint8List.sublistView(packet, _headerLength, _headerLength + _ivLength);
    final ciphertext = Uint8List.sublistView(packet, _headerLength + _ivLength, authenticatedLength);
    if (ciphertext.length % _blockSize != 0) return null;
    final plaintext = _cryptCbc(
      ciphertext,
      _inboundEncryptionKey,
      iv,
      encrypt: false,
    );
    if (plaintext.length < 2) return null;

    final padLength = plaintext[plaintext.length - 2];
    final nextHeader = plaintext[plaintext.length - 1];
    final payloadLength = plaintext.length - padLength - 2;
    if (payloadLength < 0) return null;
    for (var i = 0; i < padLength; i++) {
      if (plaintext[payloadLength + i] != i + 1) return null;
    }

    return GlobalProtectEspPacket(
      sequence: sequence,
      nextHeader: nextHeader,
      payload: Uint8List.fromList(plaintext.sublist(0, payloadLength)),
    );
  }

  bool _acceptInboundSequence(int sequence) {
    if (_highestInboundSequence < 0) {
      _highestInboundSequence = sequence;
      _inboundReplayBitmap = 1;
      return true;
    }
    if (sequence > _highestInboundSequence) {
      final shift = sequence - _highestInboundSequence;
      _inboundReplayBitmap = shift >= 64
          ? 1
          : ((_inboundReplayBitmap << shift) | 1) & 0xffffffffffffffff;
      _highestInboundSequence = sequence;
      return true;
    }
    final delta = _highestInboundSequence - sequence;
    if (delta >= 64) return false;
    final mask = 1 << delta;
    if ((_inboundReplayBitmap & mask) != 0) return false;
    _inboundReplayBitmap |= mask;
    return true;
  }

  static Uint8List _cryptCbc(
    Uint8List input,
    Uint8List key,
    Uint8List iv, {
    required bool encrypt,
  }) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        encrypt,
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
      );
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += _blockSize) {
      cipher.processBlock(input, offset, output, offset);
    }
    return output;
  }

  static bool _constantTimePrefixEquals(List<int> a, List<int> b, int length) {
    if (a.length < length || b.length < length) return false;
    var difference = 0;
    for (var i = 0; i < length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
