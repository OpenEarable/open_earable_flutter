import 'dart:typed_data';

import 'udp_transport.dart';

UdpTransport createUdpTransport() => _UnsupportedUdpTransport();

class _UnsupportedUdpTransport implements UdpTransport {
  @override
  bool get isSupported => false;

  @override
  Future<void> close() async {}

  @override
  Future<void> probe(String host, int port) async {}

  @override
  Future<void> send(Uint8List payload, String host, int port) async {}
}
