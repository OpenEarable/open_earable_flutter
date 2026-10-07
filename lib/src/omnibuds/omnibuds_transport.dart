import 'dart:async';

import '../managers/ble_gatt_manager.dart';
import '../models/capabilities/stereo_device.dart';
import 'omnibuds_protocol.dart';

/// A rejected configuration response from an OmniBuds ear.
class OmniBudsConfigurationException implements Exception {
  /// Retains the complete response for diagnostics.
  const OmniBudsConfigurationException(this.response);
  final OmniBudsMessage response;

  @override
  String toString() => 'OmniBuds ${response.ear.name} peripheral '
      '${response.peripheralId}, endpoint ${response.endpoint}: '
      'error ${response.errorCode}';
}

/// Owns the notification subscriptions shared by every sensor on one pair.
class OmniBudsTransport {
  /// Creates a transport; call [initialize] before issuing commands.
  OmniBudsTransport({
    required this.ble,
    required this.deviceId,
    this.responseTimeout = const Duration(seconds: 2),
  });

  final BleGattManager ble;
  final String deviceId;
  final Duration responseTimeout;
  final Set<DevicePosition> _channels = {};
  final List<StreamSubscription<List<int>>> _subscriptions = [];
  final _messages = StreamController<OmniBudsMessage>.broadcast();
  final _diagnostics = StreamController<Object>.broadcast();
  final _status = StreamController<Set<DevicePosition>>.broadcast();
  final Map<(DevicePosition, int, int), Completer<OmniBudsMessage>> _pending =
      {};
  final Set<(DevicePosition, int, int)> _timedOut = {};
  Future<void> _queue = Future.value();
  Completer<Set<DevicePosition>>? _pendingStatus;
  bool _controlAvailable = false;
  bool _statusTimedOut = false;
  bool _closed = false;
  bool _initializationStarted = false;
  Set<DevicePosition>? _connectedEars;

  /// Ears whose data characteristic exists, independent of peer connectivity.
  Set<DevicePosition> get channels => Set.unmodifiable(_channels);
  Stream<OmniBudsMessage> get messages => _messages.stream;
  Stream<Object> get diagnostics => _diagnostics.stream;

  /// Last status response, or null if the optional control service is absent.
  Set<DevicePosition>? get connectedEars => _connectedEars;
  Stream<Set<DevicePosition>> get connectionStatusStream => _status.stream;

  /// Subscribe once, before sending anything that can produce a response.
  Future<void> initialize() async {
    _ensureOpen();
    if (_initializationStarted) throw StateError('Already initialized');
    _initializationStarted = true;
    try {
      for (final ear in DevicePosition.values) {
        final characteristic = OmniBudsGatt.characteristic(ear);
        final available = await ble.hasCharacteristic(
          deviceId: deviceId,
          serviceId: OmniBudsGatt.service,
          characteristicId: characteristic,
        );
        _ensureOpen();
        if (!available) {
          continue;
        }
        final stream = await ble.subscribe(
          deviceId: deviceId,
          serviceId: OmniBudsGatt.service,
          characteristicId: characteristic,
        );
        _ensureOpen();
        _channels.add(ear);
        _subscriptions.add(
          stream.listen((bytes) => _receive(ear, bytes), onError: report),
        );
      }
      if (_channels.isEmpty) throw StateError('No OmniBuds sensor channels');
      _controlAvailable = await ble.hasCharacteristic(
        deviceId: deviceId,
        serviceId: OmniBudsGatt.service,
        characteristicId: OmniBudsGatt.control,
      );
      _ensureOpen();
      if (_controlAvailable) {
        try {
          final stream = await ble.subscribe(
            deviceId: deviceId,
            serviceId: OmniBudsGatt.service,
            characteristicId: OmniBudsGatt.control,
          );
          _ensureOpen();
          _subscriptions.add(stream.listen(_receiveStatus, onError: report));
          await refreshConnectionStatus();
        } catch (error) {
          // Older firmware may lack this optional, read-only status command.
          report(error);
        }
      }
      _ensureOpen();
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('OmniBuds disconnected');
  }

  /// Reports malformed frames or background operation errors without throwing
  /// from BLE callbacks. Callers can observe [diagnostics].
  void report(Object error) {
    if (!_closed) _diagnostics.add(error);
  }

  void _receive(DevicePosition ear, List<int> bytes) {
    if (_closed) return;
    try {
      final message = OmniBudsMessage.decode(ear, bytes);
      _messages.add(message);
      if (message.type != 1) return;
      final pending = _pending[(ear, message.peripheralId, message.endpoint!)];
      if (pending != null &&
          message.errorCode != null &&
          !pending.isCompleted) {
        pending.complete(message);
      }
      if (message.peripheralId == 35 &&
          message.endpoint == 0 &&
          message.text.isEmpty &&
          (message.errorCode ?? 0) == 0) {
        unawaited(sendTime(ear).catchError(report));
      }
    } catch (error) {
      report(error);
    }
  }

  void _receiveStatus(List<int> bytes) {
    if (_closed || bytes.isEmpty || bytes[0] != 3) return;
    if (bytes.length != 3) {
      report(const FormatException('Invalid OmniBuds connection status'));
      return;
    }
    final flags = (bytes[1] << 8) | bytes[2];
    final ears = Set<DevicePosition>.unmodifiable({
      if (flags & 1 != 0) DevicePosition.left,
      if (flags & 2 != 0) DevicePosition.right,
    });
    _connectedEars = ears;
    _status.add(ears);
    final pending = _pendingStatus;
    if (pending != null && !pending.isCompleted) pending.complete(ears);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) {
      if (_closed) throw StateError('OmniBuds disconnected');
      return action();
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Requests the read-only peer status (opcode 2, response 3).
  Future<Set<DevicePosition>> refreshConnectionStatus() => _enqueue(() async {
        if (!_controlAvailable) {
          throw UnsupportedError('Peer status unavailable');
        }
        if (_statusTimedOut) throw StateError('Reconnect after status timeout');
        final pending = Completer<Set<DevicePosition>>();
        _pendingStatus = pending;
        // Attach error handling before write: a synchronous notification or
        // disconnect can complete the waiter while the GATT write is still pending.
        final response = pending.future.timeout(responseTimeout);
        unawaited(
          response.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        );
        try {
          await ble.write(
            deviceId: deviceId,
            serviceId: OmniBudsGatt.service,
            characteristicId: OmniBudsGatt.control,
            byteData: [2],
          ).timeout(responseTimeout);
          return await response;
        } on TimeoutException {
          _statusTimedOut = true;
          rethrow;
        } finally {
          _pendingStatus = null;
          if (!pending.isCompleted) {
            pending.completeError(StateError('Status ended'));
          }
        }
      });

  /// Reads or writes an endpoint and waits for its application-level response.
  /// Timed-out endpoint keys cannot be reused until reconnect because the wire
  /// protocol has no transaction ID to distinguish a delayed old response.
  Future<OmniBudsMessage> configure(
    DevicePosition ear,
    int peripheralId,
    int endpoint, {
    String? value,
  }) =>
      _enqueue(() async {
        if (!_channels.contains(ear)) {
          throw StateError('No ${ear.name} channel');
        }
        final key = (ear, peripheralId, endpoint);
        if (_timedOut.contains(key)) {
          throw StateError('Reconnect before retrying timed-out endpoint $key');
        }
        final bytes =
            encodeOmniBudsConfiguration(peripheralId, endpoint, value: value);
        final pending = Completer<OmniBudsMessage>();
        _pending[key] = pending;
        final response = pending.future.timeout(responseTimeout);
        unawaited(
          response.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        );
        try {
          await ble
              .write(
                deviceId: deviceId,
                serviceId: OmniBudsGatt.service,
                characteristicId: OmniBudsGatt.characteristic(ear),
                byteData: bytes,
              )
              .timeout(responseTimeout);
          final message = await response;
          if (message.errorCode != 0) {
            throw OmniBudsConfigurationException(message);
          }
          return message;
        } on TimeoutException {
          _timedOut.add(key);
          rethrow;
        } catch (_) {
          // A failed write may have reached the peripheral; do not let a delayed
          // reply be mistaken for a new transaction on the same endpoint.
          if (!pending.isCompleted) _timedOut.add(key);
          rethrow;
        } finally {
          _pending.remove(key);
          if (!pending.isCompleted) {
            pending.completeError(StateError('Request ended'));
          }
        }
      });

  /// Answers the device's time request using Unix milliseconds, as its app does.
  /// This sets wall time; it does not establish sample-accurate stereo sync.
  Future<void> sendTime(DevicePosition ear) => _enqueue(() async {
        await ble
            .write(
              deviceId: deviceId,
              serviceId: OmniBudsGatt.service,
              characteristicId: OmniBudsGatt.characteristic(ear),
              byteData: encodeOmniBudsConfiguration(
                35,
                0,
                value: '${DateTime.now().millisecondsSinceEpoch}',
                errorCode: 0,
              ),
            )
            .timeout(responseTimeout);
      });

  /// Cancels notifications and rejects pending commands on physical disconnect.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('OmniBuds disconnected'));
      }
    }
    final status = _pendingStatus;
    if (status != null && !status.isCompleted) {
      status.completeError(StateError('OmniBuds disconnected'));
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _connectedEars = null;
    unawaited(_messages.close());
    unawaited(_diagnostics.close());
    unawaited(_status.close());
  }
}
