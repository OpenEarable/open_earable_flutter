import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'udp_transport.dart';

UdpTransport createUdpTransport() => _IoUdpTransport();

class _IoUdpTransport implements UdpTransport {
  RawDatagramSocket? _socket;
  Future<RawDatagramSocket>? _pendingSocket;

  String? _cachedHost;
  InternetAddress? _cachedAddress;

  @override
  bool get isSupported => true;

  static const String _probeRequestType = 'open_earable_udp_probe';
  static const String _probeAckType = 'open_earable_udp_probe_ack';
  static const Duration _probeTimeout = Duration(milliseconds: 800);

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
      throw const SocketException('Unable to resolve UDP bridge host');
    }

    _cachedHost = host;
    _cachedAddress = resolved.first;
    return _cachedAddress!;
  }

  @override
  Future<void> send(Uint8List payload, String host, int port) async {
    final socket = await _getSocket();
    final address = await _resolveAddress(host);
    final sentBytes = socket.send(payload, address, port);
    if (sentBytes <= 0 || sentBytes != payload.length) {
      throw SocketException(
        'Failed to send UDP payload to UDP bridge ($host:$port)',
      );
    }
  }

  @override
  Future<void> probe(String host, int port) async {
    final address = await _resolveAddress(host);
    final nonce = '${DateTime.now().microsecondsSinceEpoch}:$host:$port';
    final probePayload = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'type': _probeRequestType,
          'nonce': nonce,
        }),
      ),
    );

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.writeEventsEnabled = false;
    socket.readEventsEnabled = true;

    final ackCompleter = Completer<void>();
    late final StreamSubscription<RawSocketEvent> subscription;
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }

      while (true) {
        final datagram = socket.receive();
        if (datagram == null) {
          break;
        }
        if (datagram.port != port ||
            datagram.address.address != address.address) {
          continue;
        }

        try {
          final decoded = jsonDecode(utf8.decode(datagram.data));
          if (decoded is! Map) {
            continue;
          }
          if (decoded['type'] != _probeAckType || decoded['nonce'] != nonce) {
            continue;
          }
          if (!ackCompleter.isCompleted) {
            ackCompleter.complete();
          }
          return;
        } catch (_) {
          continue;
        }
      }
    });

    try {
      final sentBytes = socket.send(probePayload, address, port);
      if (sentBytes <= 0 || sentBytes != probePayload.length) {
        throw SocketException(
          'Failed to send UDP probe to UDP bridge ($host:$port)',
        );
      }

      await ackCompleter.future.timeout(
        _probeTimeout,
        onTimeout: () {
          throw SocketException(
            'Timed out waiting for UDP probe acknowledgment ($host:$port)',
          );
        },
      );
    } finally {
      await subscription.cancel();
      socket.close();
    }
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
