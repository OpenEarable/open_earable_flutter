import 'dart:async';

import '../../../open_earable_flutter.dart';

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
  })  : _sensors = sensors,
        _sensorConfigs = sensorConfigs,
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice;

  final DiscoveredDevice _discoveredDevice;

  final List<Sensor> _sensors;
  final List<SensorConfiguration> _sensorConfigs;
  final BleGattManager _bleManager;

  static const int _batteryReadType = 0x00;
  static const int _batteryPushType = 0x02;
  static const Duration _batteryResponseTimeout = Duration(milliseconds: 1800);

  @override
  final String deviceId;

  @override
  List<SensorConfiguration<SensorConfigurationValue>>
      get sensorConfigurations => _sensorConfigs;
  @override
  List<Sensor<SensorValue>> get sensors => _sensors;

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  Stream<
      Map<SensorConfiguration<SensorConfigurationValue>,
          SensorConfigurationValue>> get sensorConfigurationStream =>
      const Stream.empty();

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
        if (data.length < 5) {
          return;
        }

        final int responseFrameId = data[1] & 0xFF;
        final int responseCmd = data[2] & 0xFF;
        final int responseType = data[3] & 0xFF;
        if (responseFrameId != frameId || responseCmd != OpenRingGatt.cmdBatt) {
          return;
        }
        if (responseType != _batteryReadType &&
            responseType != _batteryPushType) {
          return;
        }

        final int battery = data[4] & 0xFF;
        if (!completer.isCompleted) {
          completer.complete(battery);
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

  @override
  Stream<int> get batteryPercentageStream {
    StreamController<int> controller = StreamController<int>();
    Timer? batteryPollingTimer;
    bool batteryPollingInFlight = false;

    Future<void> pollBattery() async {
      if (batteryPollingInFlight) {
        return;
      }
      batteryPollingInFlight = true;
      try {
        final int batteryPercentage = await readBatteryPercentage();
        if (!controller.isClosed) {
          controller.add(batteryPercentage);
        }
      } catch (e) {
        logger.e('Error reading OpenRing battery percentage: $e');
      } finally {
        batteryPollingInFlight = false;
      }
    }

    controller.onCancel = () {
      batteryPollingTimer?.cancel();
    };

    controller.onListen = () {
      batteryPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        unawaited(pollBattery());
      });
      unawaited(pollBattery());
    };

    return controller.stream;
  }
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
