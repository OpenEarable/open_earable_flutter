import 'dart:typed_data';

abstract class UdpTransport {
  bool get isSupported;

  /// Performs a lightweight reachability probe for the configured endpoint.
  ///
  /// Implementations should throw on probe failures.
  Future<void> probe(String host, int port);

  Future<void> send(Uint8List payload, String host, int port);

  Future<void> close();
}
