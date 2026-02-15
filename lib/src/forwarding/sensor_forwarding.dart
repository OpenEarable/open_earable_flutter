import 'dart:async';
import 'dart:developer' as developer;

import 'sensor_forwarder.dart';

/// Global forwarding pipeline used by all sensors.
class SensorForwardingPipeline {
  SensorForwardingPipeline._internal();

  static final SensorForwardingPipeline instance =
      SensorForwardingPipeline._internal();

  final List<SensorForwarder> _forwarders = [];
  DateTime? _lastForwardingError;

  List<SensorForwarder> get forwarders => List.unmodifiable(_forwarders);

  void setForwarders(
    List<SensorForwarder> forwarders,
  ) {
    _forwarders
      ..clear()
      ..addAll(forwarders);
  }

  void addForwarder(SensorForwarder forwarder) {
    _forwarders.add(forwarder);
  }

  bool removeForwarder(SensorForwarder forwarder) {
    return _forwarders.remove(forwarder);
  }

  bool setForwarderEnabled(SensorForwarder forwarder, bool enabled) {
    if (!_forwarders.contains(forwarder)) {
      return false;
    }
    forwarder.setEnabled(enabled);
    return true;
  }

  bool? isForwarderEnabled(SensorForwarder forwarder) {
    if (!_forwarders.contains(forwarder)) {
      return null;
    }
    return forwarder.isEnabled;
  }

  void clearForwarders() {
    _forwarders.clear();
  }

  Future<void> forward(SensorForwardingSample sample) async {
    if (_forwarders.isEmpty) {
      return;
    }

    for (final forwarder in _forwarders) {
      if (!forwarder.isEnabled) {
        continue;
      }
      try {
        await forwarder.forward(sample);
      } catch (error, stackTrace) {
        final now = DateTime.now();
        final shouldLog = _lastForwardingError == null ||
            now.difference(_lastForwardingError!) >= const Duration(seconds: 5);
        if (shouldLog) {
          _lastForwardingError = now;
          developer.log(
            'Sensor forwarding failed in ${forwarder.runtimeType}: $error',
            name: 'open_earable_flutter',
            stackTrace: stackTrace,
          );
        }
      }
    }
  }

  Future<void> close() async {
    for (final forwarder in _forwarders) {
      try {
        await forwarder.close();
      } catch (error, stackTrace) {
        developer.log(
          'Failed to close forwarder ${forwarder.runtimeType}: $error',
          name: 'open_earable_flutter',
          stackTrace: stackTrace,
        );
      }
    }
  }
}
