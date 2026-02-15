import 'dart:typed_data';

abstract class LslTransport {
  bool get isSupported;

  Future<void> send(Uint8List payload, String host, int port);

  Future<void> close();
}
