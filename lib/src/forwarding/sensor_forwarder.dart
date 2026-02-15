import 'dart:async';

import '../models/capabilities/sensor.dart';

/// Single sample emitted by a sensor stream and dispatched to forwarders.
class SensorForwardingSample {
  final Sensor sensor;
  final SensorValue value;
  final String deviceId;
  final String deviceName;
  final String? deviceSide;

  const SensorForwardingSample({
    required this.sensor,
    required this.value,
    required this.deviceId,
    required this.deviceName,
    this.deviceSide,
  });
}

/// Runtime connectivity state of a forwarder target.
enum SensorForwarderConnectionState {
  /// Forwarder is operating normally (or no fault has been observed yet).
  active,

  /// A forwarding attempt failed and the target is currently considered unreachable.
  unreachable,
}

/// Optional capability for forwarders that can report connectivity health.
///
/// Forwarders that do not implement this are treated as always [SensorForwarderConnectionState.active].
abstract class SensorForwarderConnectionStateProvider {
  SensorForwarderConnectionState get connectionState;

  Stream<SensorForwarderConnectionState> get connectionStateStream;
}

/// Optional capability for forwarders that can expose a human-readable
/// connection error while unreachable.
abstract class SensorForwarderConnectionErrorProvider {
  String? get connectionErrorMessage;

  Stream<String?> get connectionErrorMessageStream;
}

/// Pluggable forwarding target.
///
/// Implementations can publish samples to different destinations
/// (e.g. LSL bridge, file sink, websocket sink).
abstract class SensorForwarder {
  bool get isEnabled;

  void setEnabled(bool enabled);

  FutureOr<void> forward(SensorForwardingSample sample);

  Future<void> close();
}
