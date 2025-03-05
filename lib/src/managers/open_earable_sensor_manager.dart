import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/src/managers/sensor_handler.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/edge_ml_sensor_scheme_parser.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/sensor_value_parser.dart';

import '../constants.dart';
import '../utils/mahony_ahrs.dart';
import '../utils/sensor_scheme_parser/sensor_scheme_parser.dart';
import '../utils/sensor_value_parser/edge_ml_sensor_value_parser.dart';
import 'ble_manager.dart';

/// Manages sensor-related functionality for the OpenEarable device.
class OpenEarableSensorHandler extends SensorHandler<OpenEarableSensorConfig> {
  final String deviceId;

  final imuID = 0;
  final BleManager _bleManager;
  final MahonyAHRS _mahonyAHRS = MahonyAHRS();

  final SensorSchemeParser _sensorSchemeParser;
  final SensorValueParser _sensorValueParser;
  List<SensorScheme>? _sensorSchemes;

  /// Creates a [OpenEarableSensorHandler] instance with the specified [bleManager].
  OpenEarableSensorHandler({
    required BleManager bleManager,
    required this.deviceId,
    SensorSchemeParser? sensorSchemeParser,
    SensorValueParser? sensorValueParser,
  })  : _bleManager = bleManager,
        _sensorSchemeParser = sensorSchemeParser ?? EdgeMlSensorSchemeParser(),
        _sensorValueParser = sensorValueParser ?? EdgeMlSensorValueParser();

  /// Writes the sensor configuration to the OpenEarable device.
  ///
  /// The [sensorConfig] parameter contains the sensor id, sampling rate
  /// and latency of the sensor.
  @override
  Future<void> writeSensorConfig(OpenEarableSensorConfig sensorConfig) async {
    if (!_bleManager.isConnected(deviceId)) {
      Exception("Can't write sensor config. Earable not connected");
    }
    await _bleManager.write(
      deviceId: deviceId,
      serviceId: sensorServiceUuid,
      characteristicId: sensorConfigurationCharacteristicUuid,
      byteData: sensorConfig.byteList,
    );
    if (_sensorSchemes == null) {
      await _readSensorScheme();
    }
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
      Exception("Can't subscribe to sensor data. Earable not connected");
    }
    StreamController<Map<String, dynamic>> streamController =
        StreamController();
    int lastTimestamp = 0;
    _bleManager
        .subscribe(
      deviceId: deviceId,
      serviceId: sensorServiceUuid,
      characteristicId: sensorDataCharacteristicUuid,
    )
        .listen(
      (data) async {
        if (data.isNotEmpty && data[0] == sensorId) {
          Map<String, dynamic> parsedData = await _parseData(data);
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
            parsedData["EULER"]
                ["units"] = {"YAW": "rad", "PITCH": "rad", "ROLL": "rad"};
          }
          streamController.add(parsedData);
        }
      },
      onError: (error) {},
    );

    return streamController.stream;
  }

  /// Parses raw sensor data bytes into a [Map] of sensor values.
  Future<Map<String, dynamic>> _parseData(data) async {
    ByteData byteData = ByteData.sublistView(Uint8List.fromList(data));
    
    return _sensorValueParser.parse(byteData, _sensorSchemes!);
  }

  /// Reads the sensor scheme that is needed to parse the raw sensor
  /// data bytes
  Future<void> _readSensorScheme() async {
    List<int> byteStream = await _bleManager.read(
      deviceId: deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: schemeCharacteristicUuid,
    );

    _sensorSchemes = _sensorSchemeParser.parse(byteStream);
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
