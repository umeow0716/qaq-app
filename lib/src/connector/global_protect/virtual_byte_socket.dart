import 'dart:typed_data';

abstract interface class VirtualByteSocket {
  Stream<Uint8List> get stream;

  Future<void> write(Uint8List data);

  Future<void> close({bool sendFin = true});
}
