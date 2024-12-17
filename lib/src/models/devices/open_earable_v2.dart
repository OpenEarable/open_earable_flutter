import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:open_earable_flutter/src/models/capabilities/battery_service.dart';
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

const String _batteryServiceUuid = "180F";
const String _batteryLevelCharacteristicUuid = "2A19";
const String _batteryLevelStatusCharacteristicUuid = "2BED";
const String _batteryHealthStatusCharacteristicUuid = "2BEA";
const String _batteryEnergyStatusCharacteristicUuid = "2BF0";

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
        ExtendedBatteryService,
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

  @override
  Future<int> readBatteryPercentage() async {
    List<int> batteryLevelList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _batteryServiceUuid,
      characteristicId: _batteryLevelCharacteristicUuid,
    );

    _logger.t("Battery level bytes: $batteryLevelList");

    if (batteryLevelList.length != 1) {
      throw StateError('Battery level characteristic expected 1 value, but got ${batteryLevelList.length}');
    }

    return batteryLevelList[0];
  }

  @override
  Future<BatteryEnergyStatus> readEnergyStatus() async {
    List<int> energyStatusList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _batteryServiceUuid,
      characteristicId: _batteryEnergyStatusCharacteristicUuid,
    );

    _logger.t("Battery energy status bytes: $energyStatusList");

    if (energyStatusList.length != 7) {
      throw StateError('Battery energy status characteristic expected 7 values, but got ${energyStatusList.length}');
    }

    int rawVoltage = (energyStatusList[2] << 8) | energyStatusList[1];
    double voltage = _convertSFloat(rawVoltage);

    int rawAvailableCapacity = (energyStatusList[4] << 8) | energyStatusList[3];
    double availableCapacity = _convertSFloat(rawAvailableCapacity);

    int rawChargeRate = (energyStatusList[6] << 8) | energyStatusList[5];
    double chargeRate = _convertSFloat(rawChargeRate);

    BatteryEnergyStatus batteryEnergyStatus = BatteryEnergyStatus(
      voltage: voltage,
      availableCapacity: availableCapacity,
      chargeRate: chargeRate,
    );

    _logger.d('Battery energy status: $batteryEnergyStatus');

    return batteryEnergyStatus;
  }

  double _convertSFloat(int rawBits) {
    int exponent = ((rawBits & 0xF000) >> 12) - 16;
    int mantissa = rawBits & 0x0FFF;

    if (mantissa >= 0x800) {
      mantissa = -((0x1000) - mantissa);
    }
    _logger.t("Exponent: $exponent, Mantissa: $mantissa");
    double result = mantissa.toDouble() * pow(10.0, exponent.toDouble());
    return result;
  }

  @override
  Future<BatteryHealthStatus> readHealthStatus() async {
    List<int> healthStatusList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _batteryServiceUuid,
      characteristicId: _batteryHealthStatusCharacteristicUuid,
    );

    _logger.t("Battery health status bytes: $healthStatusList");

    if (healthStatusList.length != 5) {
      throw StateError('Battery health status characteristic expected 5 values, but got ${healthStatusList.length}');
    }

    int healthSummary = healthStatusList[1];
    int cycleCount = (healthStatusList[2] << 8) | healthStatusList[3];
    int currentTemperature = healthStatusList[4];

    BatteryHealthStatus batteryHealthStatus = BatteryHealthStatus(
      healthSummary: healthSummary,
      cycleCount: cycleCount,
      currentTemperature: currentTemperature,
    );

    _logger.d('Battery health status: $batteryHealthStatus');

    return batteryHealthStatus;
  }

  @override
  Future<BatteryPowerStatus> readPowerStatus() async {
    List<int> powerStateList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _batteryServiceUuid,
      characteristicId: _batteryLevelStatusCharacteristicUuid,
    );

    int powerState = (powerStateList[1] << 8) | powerStateList[2];
    _logger.d("Battery power status bits: ${powerState.toRadixString(2)}");

    bool batteryPresent = powerState >> 15 & 0x1 != 0;

    int wiredExternalPowerSourceConnectedRaw = (powerState >> 13) & 0x3;
    ExternalPowerSourceConnected wiredExternalPowerSourceConnected
      = ExternalPowerSourceConnected.values[wiredExternalPowerSourceConnectedRaw];

    int wirelessExternalPowerSourceConnectedRaw = (powerState >> 11) & 0x3;
    ExternalPowerSourceConnected wirelessExternalPowerSourceConnected
      = ExternalPowerSourceConnected.values[wirelessExternalPowerSourceConnectedRaw];

    int chargeStateRaw = (powerState >> 9) & 0x3;
    ChargeState chargeState = ChargeState.values[chargeStateRaw];

    int chargeLevelRaw = (powerState >> 7) & 0x3;
    BatteryChargeLevel chargeLevel = BatteryChargeLevel.values[chargeLevelRaw];

    int chargingTypeRaw = (powerState >> 5) & 0x7;
    BatteryChargingType chargingType = BatteryChargingType.values[chargingTypeRaw];

    int chargingFaultReasonRaw = (powerState >> 2) & 0x5;
    List<ChargingFaultReason> chargingFaultReason = [];
    if ((chargingFaultReasonRaw & 0x1) != 0) {
      chargingFaultReason.add(ChargingFaultReason.other);
    }
    if ((chargingFaultReasonRaw & 0x2) != 0) {
      chargingFaultReason.add(ChargingFaultReason.externalPowerSource);
    }
    if ((chargingFaultReasonRaw & 0x4) != 0) {
      chargingFaultReason.add(ChargingFaultReason.battery);
    }

    BatteryPowerStatus batteryPowerStatus = BatteryPowerStatus(
      batteryPresent: batteryPresent,
      wiredExternalPowerSourceConnected: wiredExternalPowerSourceConnected,
      wirelessExternalPowerSourceConnected: wirelessExternalPowerSourceConnected,
      chargeState: chargeState,
      chargeLevel: chargeLevel,
      chargingType: chargingType,
      chargingFaultReason: chargingFaultReason,
    );

    _logger.d('Battery power status: $batteryPowerStatus');

    return batteryPowerStatus;
  }

  @override
  Stream<int> get batteryPercentageStream async* {
    while (true) {
      yield await readBatteryPercentage();
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Stream<BatteryPowerStatus> get powerStatusStream async* {
    while (true) {
      try {
        yield await readPowerStatus();
      } catch (e) {
        _logger.e('Error reading power status: $e');
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Stream<BatteryEnergyStatus> get energyStatusStream async* {
    while (true) {
      try {
        yield await readEnergyStatus();
      } catch (e) {
        _logger.e('Error reading energy status: $e');
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Stream<BatteryHealthStatus> get healthStatusStream async* {
    while (true) {
      try {
        yield await readHealthStatus();
      } catch (e) {
        _logger.e('Error reading health status: $e');
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }
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
