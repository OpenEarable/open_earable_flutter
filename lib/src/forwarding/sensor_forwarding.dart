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
  Future<void> _forwardingQueue = Future<void>.value();
  DateTime? _lastDroppedSamplesLog;
  int _pendingForwardSamples = 0;
  int _droppedForwardSamples = 0;

  static const int _maxPendingForwardSamples = 256;

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

  SensorForwarderConnectionState? forwarderConnectionState(
    SensorForwarder forwarder,
  ) {
    if (!_forwarders.contains(forwarder)) {
      return null;
    }
    if (forwarder is SensorForwarderConnectionStateProvider) {
      final provider = forwarder as SensorForwarderConnectionStateProvider;
      return provider.connectionState;
    }
    return SensorForwarderConnectionState.active;
  }

  Stream<SensorForwarderConnectionState>? forwarderConnectionStateStream(
    SensorForwarder forwarder,
  ) {
    if (!_forwarders.contains(forwarder)) {
      return null;
    }
    if (forwarder is SensorForwarderConnectionStateProvider) {
      final provider = forwarder as SensorForwarderConnectionStateProvider;
      return provider.connectionStateStream;
    }
    return const Stream<SensorForwarderConnectionState>.empty();
  }

  String? forwarderConnectionErrorMessage(SensorForwarder forwarder) {
    if (!_forwarders.contains(forwarder)) {
      return null;
    }
    if (forwarder is SensorForwarderConnectionErrorProvider) {
      final provider = forwarder as SensorForwarderConnectionErrorProvider;
      return provider.connectionErrorMessage;
    }
    return null;
  }

  Stream<String?>? forwarderConnectionErrorMessageStream(
    SensorForwarder forwarder,
  ) {
    if (!_forwarders.contains(forwarder)) {
      return null;
    }
    if (forwarder is SensorForwarderConnectionErrorProvider) {
      final provider = forwarder as SensorForwarderConnectionErrorProvider;
      return provider.connectionErrorMessageStream;
    }
    return const Stream<String?>.empty();
  }

  void clearForwarders() {
    _forwarders.clear();
  }

  Future<void> forward(SensorForwardingSample sample) {
    if (_forwarders.isEmpty) {
      return Future<void>.value();
    }

    if (_pendingForwardSamples >= _maxPendingForwardSamples) {
      _recordDroppedSample();
      return Future<void>.value();
    }

    _pendingForwardSamples += 1;
    _forwardingQueue = _forwardingQueue.catchError((_) {}).then((_) async {
      try {
        await _dispatchToForwarders(sample);
      } finally {
        _pendingForwardSamples -= 1;
      }
    });
    return _forwardingQueue;
  }

  Future<void> _dispatchToForwarders(SensorForwardingSample sample) async {
    final forwarders = List<SensorForwarder>.from(_forwarders);
    for (final forwarder in forwarders) {
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

  void _recordDroppedSample() {
    _droppedForwardSamples += 1;
    final now = DateTime.now();
    final shouldLog = _lastDroppedSamplesLog == null ||
        now.difference(_lastDroppedSamplesLog!) >= const Duration(seconds: 5);
    if (!shouldLog) {
      return;
    }
    final droppedSamples = _droppedForwardSamples;
    _droppedForwardSamples = 0;
    _lastDroppedSamplesLog = now;
    developer.log(
      'Dropping $droppedSamples sensor samples because forwarding queue is saturated.',
      name: 'open_earable_flutter',
    );
  }

  Future<void> close() async {
    try {
      await _forwardingQueue;
    } catch (_) {}
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
