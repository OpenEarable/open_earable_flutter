import 'dart:async';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:open_earable_flutter/src/models/capabilities/status_led.dart';

import '../../managers/open_earable_sensor_manager.dart';
import '../capabilities/device_firmware_version.dart';
import '../capabilities/device_hardware_version.dart';
import '../capabilities/device_identifier.dart';
import '../capabilities/rgb_led.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_configuration.dart';
import '../capabilities/sensor_configuration_manager.dart';
import '../capabilities/sensor_manager.dart';
import '../../managers/ble_manager.dart';
import 'discovered_device.dart';
import 'wearable.dart';

const String _ledServiceUuid = "81040a2e-4819-11ee-be56-0242ac120002";
const String _ledSetColorCharacteristic =
    "81040e7a-4819-11ee-be56-0242ac120002";
const String _ledSetStateCharacteristic =
    "81040e7b-4819-11ee-be56-0242ac120002";

const String _deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String _deviceIdentifierCharacteristicUuid =
    "45622511-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";
const String _deviceHardwareVersionCharacteristicUuid =
    "45622513-6468-465a-b141-0b9b0f96b468";

Logger _logger = Logger();

class OpenEarableV2 extends Wearable
    implements
        SensorManager,
        SensorConfigurationManager,
        RgbLed,
        StatusLed,
        DeviceIdentifier,
        DeviceFirmwareVersion,
        DeviceHardwareVersion {
  final List<Sensor> _sensors;
  final List<SensorConfiguration> _sensorConfigurations;
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  OpenEarableV2({
    required super.name,
    required super.disconnectNotifier,
    required List<Sensor> sensors,
    required List<SensorConfiguration> sensorConfigurations,
    required BleManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _sensors = sensors,
        _sensorConfigurations = sensorConfigurations,
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice;

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> writeLedColor({
    required int r,
    required int g,
    required int b,
  }) async {
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      throw ArgumentError('The color values must be in range 0-255');
    }
    ByteData data = ByteData(3);
    data.setUint8(0, r);
    data.setUint8(1, g);
    data.setUint8(2, b);
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: _ledServiceUuid,
      characteristicId: _ledSetColorCharacteristic,
      byteData: data.buffer.asUint8List(),
    );
  }

  @override
  Future<void> showStatus(bool status) async {
    ByteData statusData = ByteData(1);
    statusData.setUint8(0, status ? 0 : 1);
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: _ledServiceUuid,
      characteristicId: _ledSetStateCharacteristic,
      byteData: statusData.buffer.asUint8List(),
    );
  }

  /// Reads the device identifier from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device identifier as a `String`.
  @override
  Future<String?> readDeviceIdentifier() async {
    List<int> deviceIdentifierBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceIdentifierCharacteristicUuid,
    );
    return String.fromCharCodes(deviceIdentifierBytes);
  }

  /// Reads the device firmware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceFirmwareVersion() async {
    List<int> deviceGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceFirmwareVersionCharacteristicUuid,
    );
    return String.fromCharCodes(deviceGenerationBytes);
  }

  /// Reads the device hardware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceHardwareVersion() async {
    List<int> hardwareGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceHardwareVersionCharacteristicUuid,
    );
    return String.fromCharCodes(hardwareGenerationBytes);
  }

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  List<SensorConfiguration> get sensorConfigurations =>
      List.unmodifiable(_sensorConfigurations);

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);
}

class _ImuSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _ImuSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'IMU',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: '0'),
            SensorConfigurationValue(key: '10'),
            SensorConfigurationValue(key: '20'),
            SensorConfigurationValue(key: '30'),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double imuSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig imuConfig = OpenEarableSensorConfig(
      sensorId: 0,
      samplingRate: imuSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(imuConfig);
  }
}

class _BarometerSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _BarometerSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'Barometer',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: '0'),
            SensorConfigurationValue(key: '10'),
            SensorConfigurationValue(key: '20'),
            SensorConfigurationValue(key: '30'),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double? barometerSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig barometerConfig = OpenEarableSensorConfig(
      sensorId: 1,
      samplingRate: barometerSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(barometerConfig);
  }
}

class _MicrophoneSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _MicrophoneSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'Microphone',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: "0"),
            SensorConfigurationValue(key: "16000"),
            SensorConfigurationValue(key: "20000"),
            SensorConfigurationValue(key: "25000"),
            SensorConfigurationValue(key: "31250"),
            SensorConfigurationValue(key: "33333"),
            SensorConfigurationValue(key: "40000"),
            SensorConfigurationValue(key: "41667"),
            SensorConfigurationValue(key: "50000"),
            SensorConfigurationValue(key: "62500"),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double? microphoneSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig microphoneConfig = OpenEarableSensorConfig(
      sensorId: 2,
      samplingRate: microphoneSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(microphoneConfig);
  }
}
