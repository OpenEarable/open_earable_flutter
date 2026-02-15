import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/src/managers/sensor_handler.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/edge_ml_sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/sensor_value_parser.dart';

import '../constants.dart';
import '../../open_earable_flutter.dart' show logger;
import '../utils/mahony_ahrs.dart';
import '../utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import '../utils/sensor_value_parser/edge_ml_sensor_value_parser.dart';
import 'ble_gatt_manager.dart';

/// Manages sensor-related functionality for the OpenEarable device.
class OpenEarableSensorHandler extends SensorHandler<OpenEarableSensorConfig> {
  final String deviceId;

  final imuID = 0;
  final BleGattManager _bleManager;
  final MahonyAHRS _mahonyAHRS = MahonyAHRS();

  final SensorSchemeReader _sensorSchemeParser;
  final SensorValueParser _sensorValueParser;
  List<SensorScheme>? _sensorSchemes;
  Future<void>? _sensorSchemesReadFuture;

  /// Creates a [OpenEarableSensorHandler] instance with the specified [bleManager].
  OpenEarableSensorHandler({
    required BleGattManager bleManager,
    required this.deviceId,
    SensorSchemeReader? sensorSchemeParser,
    SensorValueParser? sensorValueParser,
  })  : _bleManager = bleManager,
        _sensorSchemeParser = sensorSchemeParser ??
            EdgeMlSensorSchemeReader(bleManager, deviceId),
        _sensorValueParser = sensorValueParser ?? EdgeMlSensorValueParser() {
    unawaited(_ensureSensorSchemesLoaded());
  }

  /// Writes the sensor configuration to the OpenEarable device.
  ///
  /// The [sensorConfig] parameter contains the sensor id, sampling rate
  /// and latency of the sensor.
  @override
  Future<void> writeSensorConfig(OpenEarableSensorConfig sensorConfig) async {
    if (!_bleManager.isConnected(deviceId)) {
      throw Exception("Can't write sensor config. Earable not connected");
    }
    await _bleManager.write(
      deviceId: deviceId,
      serviceId: sensorServiceUuid,
      characteristicId: sensorConfigurationCharacteristicUuid,
      byteData: sensorConfig.byteList,
    );
    await _ensureSensorSchemesLoaded();
  }

  /// Subscribes to sensor data for a specific sensor.
  ///
  /// The [sensorId] parameter specifies the ID of the sensor to subscribe to.
  /// - 0: IMU data
  /// - 1: Barometer data
  /// Returns a [Stream] of sensor data as a [Map] of sensor values.
  @override
  Stream<Map<String, dynamic>> subscribeToSensorData(int sensorId) {
    if (!_bleManager.isConnected(deviceId)) {
      throw Exception("Can't subscribe to sensor data. Earable not connected");
    }

    late final StreamController<Map<String, dynamic>> streamController;
    // ignore: cancel_subscriptions
    StreamSubscription<List<int>>? subscription;
    int lastTimestamp = 0;

    streamController = StreamController<Map<String, dynamic>>(
      onListen: () {
        // ignore: cancel_subscriptions
        subscription = _bleManager
            .subscribe(
          deviceId: deviceId,
          serviceId: sensorServiceUuid,
          characteristicId: sensorDataCharacteristicUuid,
        )
            .listen(
          (data) async {
            if (data.isEmpty || data[0] != sensorId) {
              return;
            }

            try {
              List<Map<String, dynamic>> parsedDataList =
                  await _parseData(data);
              for (var parsedData in parsedDataList) {
                if (sensorId == imuID) {
                  int timestamp = parsedData["timestamp"];
                  double ax = parsedData["ACC"]["X"];
                  double ay = parsedData["ACC"]["Y"];
                  double az = parsedData["ACC"]["Z"];

                  double gx = parsedData["GYRO"]["X"];
                  double gy = parsedData["GYRO"]["Y"];
                  double gz = parsedData["GYRO"]["Z"];

                  double dt = (timestamp - lastTimestamp) / 1000.0;

                  // x, y, z was changed in firmware to -x, z, y
                  _mahonyAHRS.update(
                    ax,
                    ay,
                    az,
                    gx,
                    gy,
                    gz,
                    dt,
                  );

                  lastTimestamp = timestamp;
                  List<double> q = _mahonyAHRS.quaternion;
                  double yaw = -atan2(
                    2 * (q[0] * q[3] + q[1] * q[2]),
                    1 - 2 * (q[2] * q[2] + q[3] * q[3]),
                  );

                  // Pitch (around Y-axis)
                  double pitch = -asin(2 * (q[0] * q[2] - q[3] * q[1]));

                  // Roll (around X-axis)
                  double roll = -atan2(
                    2 * (q[0] * q[1] + q[2] * q[3]),
                    1 - 2 * (q[1] * q[1] + q[2] * q[2]),
                  );

                  parsedData["EULER"] = {};
                  parsedData["EULER"]["YAW"] = yaw;
                  parsedData["EULER"]["PITCH"] = pitch;
                  parsedData["EULER"]["ROLL"] = roll;
                  parsedData["EULER"]["units"] = {
                    "YAW": "rad",
                    "PITCH": "rad",
                    "ROLL": "rad",
                  };
                }

                if (!streamController.isClosed) {
                  streamController.add(parsedData);
                }
              }
            } catch (error, stackTrace) {
              logger.e(
                "Error while processing OpenEarable sensor packet: $error",
                error: error,
                stackTrace: stackTrace,
              );
              if (!streamController.isClosed) {
                streamController.addError(error, stackTrace);
              }
            }
          },
          onError: (error, stackTrace) {
            logger.e(
              "Error while subscribing to OpenEarable sensor data: $error",
              error: error,
              stackTrace: stackTrace,
            );
            if (!streamController.isClosed) {
              streamController.addError(error, stackTrace);
            }
          },
          onDone: () {
            if (!streamController.isClosed) {
              streamController.close();
            }
          },
        );
      },
      onCancel: () async {
        final activeSubscription = subscription;
        subscription = null;
        if (activeSubscription != null) {
          await activeSubscription.cancel();
        }
      },
    );

    return streamController.stream;
  }

  /// Parses raw sensor data bytes into a [Map] of sensor values.
  Future<List<Map<String, dynamic>>> _parseData(List<int> data) async {
    await _ensureSensorSchemesLoaded();
    ByteData byteData = ByteData.sublistView(Uint8List.fromList(data));

    return _sensorValueParser.parse(byteData, _sensorSchemes!);
  }

  Future<void> _ensureSensorSchemesLoaded() async {
    final schemes = _sensorSchemes;
    if (schemes != null && schemes.isNotEmpty) {
      return;
    }

    final pendingRead = _sensorSchemesReadFuture ??= _readSensorScheme();
    try {
      await pendingRead;
    } finally {
      if (identical(_sensorSchemesReadFuture, pendingRead)) {
        _sensorSchemesReadFuture = null;
      }
    }

    final loadedSchemes = _sensorSchemes;
    if (loadedSchemes == null || loadedSchemes.isEmpty) {
      throw StateError('OpenEarable sensor scheme is not available yet');
    }
  }

  /// Reads the sensor scheme that is needed to parse the raw sensor
  /// data bytes
  Future<void> _readSensorScheme() async {
    _sensorSchemes = await _sensorSchemeParser.readSensorSchemes();
  }
}

/// Represents the configuration for an OpenEarable sensor, including sensor ID, sampling rate, and latency.
class OpenEarableSensorConfig extends SensorConfig {
  int sensorId; // 8-bit unsigned integer
  double samplingRate; // 4-byte float
  int latency; // 32-bit unsigned integer

  /// Creates an [OpenEarableSensorConfig] instance with the specified properties.
  OpenEarableSensorConfig({
    required this.sensorId,
    required this.samplingRate,
    required this.latency,
  });

  /// Returns a byte list representing the sensor configuration for writing to the device.
  List<int> get byteList {
    ByteData data = ByteData(9);
    data.setUint8(0, sensorId);
    data.setFloat32(1, samplingRate, Endian.little);
    data.setUint32(5, latency, Endian.little);
    return data.buffer.asUint8List();
  }

  @override
  String toString() {
    return 'OpenEarableSensorConfig(sensorId: $sensorId, sampleRate: $samplingRate, latency: $latency)';
  }
}
