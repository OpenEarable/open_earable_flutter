import 'dart:async';

import '../models/capabilities/sensor.dart';

/// Single sample emitted by a sensor stream and dispatched to forwarders.
class SensorForwardingSample {
  final Sensor sensor;
  final SensorValue value;
  final String deviceId;
  final String deviceName;

  const SensorForwardingSample({
    required this.sensor,
    required this.value,
    required this.deviceId,
    required this.deviceName,
  });
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
