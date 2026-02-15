import 'dart:typed_data';

import 'lsl_transport.dart';

LslTransport createLslTransport() => _UnsupportedLslTransport();

class _UnsupportedLslTransport implements LslTransport {
  @override
  bool get isSupported => false;

  @override
  Future<void> close() async {}

  @override
  Future<void> send(Uint8List payload, String host, int port) async {}
}
