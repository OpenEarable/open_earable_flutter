import 'dart:async';

import '../../../open_earable_flutter.dart';
import '../capabilities/sensor_configuration_specializations/open_ring_sensor_configuration.dart';

/// OpenRing integration for OpenEarable.
/// Implements Wearable + sensor configuration + battery level capability.
class OpenRing extends Wearable
    implements SensorManager, SensorConfigurationManager, BatteryLevelStatus {
  OpenRing({
    required DiscoveredDevice discoveredDevice,
    required this.deviceId,
    required super.name,
    List<Sensor> sensors = const [],
    List<SensorConfiguration> sensorConfigs = const [],
    required BleGattManager bleManager,
    required super.disconnectNotifier,
    bool Function()? isSensorStreamingActive,
  })  : _sensors = sensors,
        _sensorConfigs = sensorConfigs,
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice,
        _isSensorStreamingActive = isSensorStreamingActive {
    _initializeAssumedSensorStates();
  }

  final DiscoveredDevice _discoveredDevice;

  final List<Sensor> _sensors;
  final List<SensorConfiguration> _sensorConfigs;
  final BleGattManager _bleManager;
  final bool Function()? _isSensorStreamingActive;

  bool _batteryPollingWasSkippedForStreaming = false;
  int? _lastKnownBatteryPercentage;
  final Map<SensorConfiguration<SensorConfigurationValue>,
      OpenRingSensorConfigurationValue> _offValueByConfiguration = {};
  final Map<SensorConfiguration<SensorConfigurationValue>,
      OpenRingSensorConfigurationValue> _onValueByConfiguration = {};
  Map<SensorConfiguration<SensorConfigurationValue>, SensorConfigurationValue>
      _currentSensorConfigMap = {};

  StreamController<
      Map<SensorConfiguration<SensorConfigurationValue>,
          SensorConfigurationValue>>? _sensorConfigController;

  static const int _batteryReadType = 0x00;
  static const int _batteryPushType = 0x02;
  static const Duration _batteryResponseTimeout = Duration(milliseconds: 1800);

  @override
  final String deviceId;

  @override
  String? getWearableIconPath({
    bool darkmode = false,
    WearableIconVariant variant = WearableIconVariant.single,
  }) {
    return 'packages/open_earable_flutter/assets/wearable_icons/open_ring/openring.png';
  }

  @override
  List<SensorConfiguration<SensorConfigurationValue>>
      get sensorConfigurations => List.unmodifiable(_sensorConfigs);
  @override
  List<Sensor<SensorValue>> get sensors => List.unmodifiable(_sensors);

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  Stream<
      Map<SensorConfiguration<SensorConfigurationValue>,
          SensorConfigurationValue>> get sensorConfigurationStream {
    _sensorConfigController ??= StreamController<
        Map<SensorConfiguration<SensorConfigurationValue>,
            SensorConfigurationValue>>.broadcast();
    final controller = _sensorConfigController!;

    return Stream<
        Map<SensorConfiguration<SensorConfigurationValue>,
            SensorConfigurationValue>>.multi((emitter) {
      emitter.add(Map.unmodifiable(Map.of(_currentSensorConfigMap)));
      final sub = controller.stream.listen(
        emitter.add,
        onError: emitter.addError,
      );
      emitter.onCancel = sub.cancel;
    });
  }

  void _initializeAssumedSensorStates() {
    _offValueByConfiguration.clear();
    _onValueByConfiguration.clear();
    final initialMap = <SensorConfiguration<SensorConfigurationValue>,
        SensorConfigurationValue>{};

    for (final rawConfig in _sensorConfigs) {
      if (rawConfig is! OpenRingSensorConfiguration) {
        continue;
      }

      final values = rawConfig.values
          .whereType<OpenRingSensorConfigurationValue>()
          .toList(growable: false);
      if (values.isEmpty) {
        continue;
      }

      final offValue = rawConfig.offValue is OpenRingSensorConfigurationValue
          ? rawConfig.offValue as OpenRingSensorConfigurationValue
          : values.firstWhere(
              (value) => !value.streamData,
              orElse: () => values.first,
            );
      final onValue = values.firstWhere(
        (value) => value.streamData,
        orElse: () => offValue,
      );

      final configuration =
          rawConfig as SensorConfiguration<SensorConfigurationValue>;
      _offValueByConfiguration[configuration] = offValue;
      _onValueByConfiguration[configuration] = onValue;
      initialMap[configuration] = offValue;
    }

    _currentSensorConfigMap = initialMap;
  }

  void assumeConfigurationApplied({
    required OpenRingSensorConfiguration configuration,
    required OpenRingSensorConfigurationValue value,
  }) {
    final configurationKey =
        configuration as SensorConfiguration<SensorConfigurationValue>;
    final offValue = _offValueByConfiguration[configurationKey];
    if (offValue == null) {
      return;
    }

    final SensorConfigurationValue nextValue =
        value.streamData ? value : offValue;
    final previousValue = _currentSensorConfigMap[configurationKey];
    if (previousValue == nextValue) {
      return;
    }

    _currentSensorConfigMap[configurationKey] = nextValue;
    _emitSensorConfigurationState();
  }

  void assumeAllConfigurationsEnabledFromDetectedStreaming() {
    bool changed = false;
    for (final entry in _onValueByConfiguration.entries) {
      if (_currentSensorConfigMap[entry.key] == entry.value) {
        continue;
      }
      _currentSensorConfigMap[entry.key] = entry.value;
      changed = true;
    }
    if (changed) {
      _emitSensorConfigurationState();
    }
  }

  void _emitSensorConfigurationState() {
    final controller = _sensorConfigController;
    if (controller == null || controller.isClosed) {
      return;
    }

    controller.add(Map.unmodifiable(Map.of(_currentSensorConfigMap)));
  }

  @override
  Future<int> readBatteryPercentage() async {
    if (!_bleManager.isConnected(deviceId)) {
      throw StateError(
        'Cannot read OpenRing battery level while disconnected ($deviceId)',
      );
    }

    final int frameId = DateTime.now().microsecondsSinceEpoch & 0xFF;
    final List<int> command = OpenRingGatt.frame(
      OpenRingGatt.cmdBatt,
      rnd: frameId,
      payload: const [_batteryReadType],
    );

    final completer = Completer<int>();
    late final StreamSubscription<List<int>> sub;
    sub = _bleManager
        .subscribe(
      deviceId: deviceId,
      serviceId: OpenRingGatt.service,
      characteristicId: OpenRingGatt.rxChar,
    )
        .listen(
      (data) {
        final response = _parseBatteryResponse(data);
        if (response == null || !response.isRead) {
          return;
        }
        if (response.frameId != frameId) {
          return;
        }
        _lastKnownBatteryPercentage = response.batteryPercentage;
        if (!completer.isCompleted) {
          completer.complete(response.batteryPercentage);
        }
      },
      onError: (error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );

    try {
      await _bleManager.write(
        deviceId: deviceId,
        serviceId: OpenRingGatt.service,
        characteristicId: OpenRingGatt.txChar,
        byteData: command,
      );

      return await completer.future.timeout(_batteryResponseTimeout);
    } finally {
      await sub.cancel();
    }
  }

  /// One-time battery pull triggered on connect/device creation.
  Future<bool> prefetchBatteryOnConnect() async {
    if (!_bleManager.isConnected(deviceId)) {
      return false;
    }

    try {
      await readBatteryPercentage();
      return true;
    } catch (error) {
      logger.w('OpenRing initial battery read failed for $deviceId: $error');
      return false;
    }
  }

  _OpenRingBatteryResponse? _parseBatteryResponse(List<int> data) {
    if (data.length < 5) {
      return null;
    }

    final int frameType = data[0] & 0xFF;
    if (frameType != 0x00) {
      return null;
    }

    final int frameId = data[1] & 0xFF;
    final int cmd = data[2] & 0xFF;
    if (cmd != OpenRingGatt.cmdBatt) {
      return null;
    }

    final int type = data[3] & 0xFF;
    if (type != _batteryReadType && type != _batteryPushType) {
      return null;
    }

    final int batteryPercentage = data[4] & 0xFF;
    return _OpenRingBatteryResponse(
      frameId: frameId,
      type: type,
      batteryPercentage: batteryPercentage,
    );
  }

  @override
  Stream<int> get batteryPercentageStream {
    StreamController<int> controller = StreamController<int>();
    Timer? batteryPollingTimer;
    StreamSubscription<List<int>>? batteryPushSubscription;
    bool batteryPollingInFlight = false;
    int? lastEmittedBatteryPercentage;

    void emitIfChanged(int batteryPercentage) {
      if (controller.isClosed ||
          batteryPercentage == lastEmittedBatteryPercentage) {
        return;
      }
      _lastKnownBatteryPercentage = batteryPercentage;
      lastEmittedBatteryPercentage = batteryPercentage;
      controller.add(batteryPercentage);
    }

    Future<void> pollBattery() async {
      if (batteryPollingInFlight) {
        return;
      }
      final bool streamingActive = _isSensorStreamingActive?.call() ?? false;
      if (streamingActive) {
        if (!_batteryPollingWasSkippedForStreaming) {
          logger.d(
            'Skipping OpenRing battery poll while realtime sensor streaming is active',
          );
          _batteryPollingWasSkippedForStreaming = true;
        }
        return;
      }
      if (_batteryPollingWasSkippedForStreaming) {
        logger.d('Resuming OpenRing battery polling after sensor streaming');
        _batteryPollingWasSkippedForStreaming = false;
      }

      batteryPollingInFlight = true;
      try {
        final int batteryPercentage = await readBatteryPercentage();
        emitIfChanged(batteryPercentage);
      } catch (e) {
        logger.e('Error reading OpenRing battery percentage: $e');
      } finally {
        batteryPollingInFlight = false;
      }
    }

    controller.onCancel = () {
      batteryPollingTimer?.cancel();
      unawaited(batteryPushSubscription?.cancel());
    };

    controller.onListen = () {
      final initialBatteryPercentage = _lastKnownBatteryPercentage;
      if (initialBatteryPercentage != null) {
        emitIfChanged(initialBatteryPercentage);
      }

      batteryPushSubscription = _bleManager
          .subscribe(
        deviceId: deviceId,
        serviceId: OpenRingGatt.service,
        characteristicId: OpenRingGatt.rxChar,
      )
          .listen(
        (data) {
          final response = _parseBatteryResponse(data);
          if (response == null || !response.isPush) {
            return;
          }
          emitIfChanged(response.batteryPercentage);
        },
        onError: (error) {
          logger.w('OpenRing battery push subscription error: $error');
        },
      );

      batteryPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        unawaited(pollBattery());
      });
      unawaited(pollBattery());
    };

    return controller.stream;
  }
}

class _OpenRingBatteryResponse {
  const _OpenRingBatteryResponse({
    required this.frameId,
    required this.type,
    required this.batteryPercentage,
  });

  final int frameId;
  final int type;
  final int batteryPercentage;

  bool get isRead => type == OpenRing._batteryReadType;

  bool get isPush => type == OpenRing._batteryPushType;
}

// OpenRing GATT constants (from the vendor AAR)
class OpenRingGatt {
  static const String service = 'bae80001-4f05-4503-8e65-3af1f7329d1f';
  static const String txChar = 'bae80010-4f05-4503-8e65-3af1f7329d1f'; // write
  static const String rxChar = 'bae80011-4f05-4503-8e65-3af1f7329d1f'; // notify

  // opcodes (subset)
  static const int cmdApp = 0xA0; // APP_* handshake
  static const int cmdTime = 0x10; // wall clock sync
  static const int cmdVers = 0x11; // version
  static const int cmdBatt = 0x12; // battery
  static const int cmdSys = 0x37; // system (reset etc.)
  static const int cmdIMU = 0x40; // start/stop IMU
  static const int cmdPPGQ2 = 0x32; // start/stop PPG Q2

  // build a framed command: [0x00, rnd, cmdId, payload...]
  static List<int> frame(int cmd, {List<int> payload = const [], int? rnd}) {
    final r = rnd ?? DateTime.now().microsecondsSinceEpoch & 0xFF;
    return [0x00, r & 0xFF, cmd, ...payload];
  }

  static List<int> le64(int ms) {
    final b = List<int>.filled(8, 0);
    var v = ms;
    for (var i = 0; i < 8; i++) {
      b[i] = v & 0xFF;
      v >>= 8;
    }
    return b;
  }
}

class OpenRingTimeSyncImp implements TimeSynchronizable {
  OpenRingTimeSyncImp({required this.bleManager, required this.deviceId});

  final BleGattManager bleManager;
  final String deviceId;

  static const int _timeUpdateSubCommand = 0x00;
  static const int _maxAttempts = 3;
  static const Duration _responseTimeout = Duration(milliseconds: 1800);
  static const Duration _retryDelay = Duration(milliseconds: 220);

  bool _isTimeSynchronized = false;

  @override
  bool get isTimeSynchronized => _isTimeSynchronized;

  @override
  Future<void> synchronizeTime() async {
    if (!bleManager.isConnected(deviceId)) {
      throw StateError('Cannot synchronize OpenRing time while disconnected');
    }

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      bool synced = false;
      try {
        synced = await _sendTimeUpdateOnce(attempt);
      } catch (error, stack) {
        logger.w(
          'OpenRing time sync attempt $attempt/$_maxAttempts failed for $deviceId: $error',
        );
        logger.t(stack);
      }

      if (synced) {
        _isTimeSynchronized = true;
        return;
      }

      logger.w(
        'OpenRing time sync attempt $attempt/$_maxAttempts timed out for $deviceId',
      );

      if (attempt < _maxAttempts) {
        await Future.delayed(_retryDelay);
      }
    }

    _isTimeSynchronized = false;
    throw TimeoutException(
      'OpenRing time sync failed after $_maxAttempts attempts',
    );
  }

  Future<bool> _sendTimeUpdateOnce(int attempt) async {
    final int frameId =
        (DateTime.now().microsecondsSinceEpoch + attempt) & 0xFF;
    final int timestampMs = DateTime.now().millisecondsSinceEpoch;
    final int timezoneHours = DateTime.now().timeZoneOffset.inHours;
    final int timezoneByte = timezoneHours & 0xFF;

    final List<int> command = OpenRingGatt.frame(
      OpenRingGatt.cmdTime,
      rnd: frameId,
      payload: [
        _timeUpdateSubCommand,
        ...OpenRingGatt.le64(timestampMs),
        timezoneByte,
      ],
    );

    final completer = Completer<bool>();
    late final StreamSubscription<List<int>> sub;
    sub = bleManager
        .subscribe(
      deviceId: deviceId,
      serviceId: OpenRingGatt.service,
      characteristicId: OpenRingGatt.rxChar,
    )
        .listen(
      (data) {
        if (data.length < 4) {
          return;
        }
        final int responseFrameId = data[1] & 0xFF;
        final int responseCmd = data[2] & 0xFF;
        final int responseSubCommand = data[3] & 0xFF;

        if (responseFrameId == frameId &&
            responseCmd == OpenRingGatt.cmdTime &&
            responseSubCommand == _timeUpdateSubCommand &&
            !completer.isCompleted) {
          completer.complete(true);
        }
      },
      onError: (error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );

    try {
      logger.d(
        'OpenRing time sync attempt $attempt: '
        'frameId=$frameId ts=$timestampMs timezoneHours=$timezoneHours',
      );

      await bleManager.write(
        deviceId: deviceId,
        serviceId: OpenRingGatt.service,
        characteristicId: OpenRingGatt.txChar,
        byteData: command,
      );

      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      return false;
    } finally {
      await sub.cancel();
    }
  }
}
