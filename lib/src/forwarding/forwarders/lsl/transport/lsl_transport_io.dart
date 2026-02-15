import 'dart:io';
import 'dart:typed_data';

import 'lsl_transport.dart';

LslTransport createLslTransport() => _IoLslTransport();

class _IoLslTransport implements LslTransport {
  RawDatagramSocket? _socket;
  Future<RawDatagramSocket>? _pendingSocket;

  String? _cachedHost;
  InternetAddress? _cachedAddress;

  @override
  bool get isSupported => true;

  Future<RawDatagramSocket> _getSocket() {
    final socket = _socket;
    if (socket != null) {
      return Future.value(socket);
    }
    final pending = _pendingSocket;
    if (pending != null) {
      return pending;
    }

    _pendingSocket = RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((
      value,
    ) {
      _socket = value;
      _pendingSocket = null;
      return value;
    }).catchError((Object error) {
      _pendingSocket = null;
      throw error;
    });

    return _pendingSocket!;
  }

  Future<InternetAddress> _resolveAddress(String host) async {
    if (_cachedHost == host && _cachedAddress != null) {
      return _cachedAddress!;
    }

    final parsed = InternetAddress.tryParse(host);
    if (parsed != null) {
      _cachedHost = host;
      _cachedAddress = parsed;
      return parsed;
    }

    final resolved = await InternetAddress.lookup(host);
    if (resolved.isEmpty) {
      throw const SocketException('Unable to resolve LSL bridge host');
    }

    _cachedHost = host;
    _cachedAddress = resolved.first;
    return _cachedAddress!;
  }

  @override
  Future<void> send(Uint8List payload, String host, int port) async {
    final socket = await _getSocket();
    final address = await _resolveAddress(host);
    socket.send(payload, address, port);
  }

  @override
  Future<void> close() async {
    _socket?.close();
    _socket = null;
    _pendingSocket = null;
    _cachedHost = null;
    _cachedAddress = null;
  }
}
