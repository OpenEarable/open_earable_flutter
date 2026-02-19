import 'dart:async';
import 'package:iirjdart/butterworth.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/managers/open_earable_sensor_manager.dart';
import 'dart:typed_data';
import 'exg_filter_options.dart';
import 'exg_preset.dart';

class ExGWearable extends Wearable implements
    SensorManager,
    SensorConfigurationManager,
    BatteryLevelStatus,
    EdgeRecorderManager
  {
  static const batteryServiceUuid = "180f";
  static const _batteryLevelCharacteristicUuid = "02a19";

  final List<SensorConfiguration> _sensorConfigurations;
  final List<Sensor> _sensors;
  final BleGattManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  final _configCtrl = StreamController<
      Map<SensorConfiguration<SensorConfigurationValue>, SensorConfigurationValue>
  >.broadcast();

  final Map<SensorConfiguration<SensorConfigurationValue>, SensorConfigurationValue>
  _currentConfigValues = {};

  ExGWearable({
    required super.name,
    required super.disconnectNotifier,
    required BleGattManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _sensors = [],
        _sensorConfigurations = [],
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice {
    _initSensors();
  }

  void _initSensors() {
    final sensorManager = OpenEarableSensorHandler(
      bleManager: _bleManager,
      deviceId: _discoveredDevice.id,
    );

    final exgLowerCutoff = _ExGLowerCutoffSensorConfiguration(wearable: this);
    final exgHigherCutoff = _ExGHigherCutoffSensorConfiguration(wearable: this);
    final exgFs         = _ExGFsSensorConfiguration(wearable: this);
    final exgOrder      = _ExGOrderSensorConfiguration(wearable: this);

    _sensorConfigurations.addAll([exgLowerCutoff, exgHigherCutoff, exgFs, exgOrder]);

    _sensors.add(_ExGSensor(
      bleManager: _bleManager,
      discoveredDevice: _discoveredDevice,
      sensorManager: sensorManager,
    ),);

    _seedInitialConfigValues(); // <— important
  }

  // optional: call this when you're done with the wearable
  Future<void> disposeWearable() async {
    await _configCtrl.close();
  }

  void applyPreset(ExGPreset p) {
    if (p.lowerCutoff >= p.higherCutoff) {
      throw ArgumentError('Lower cutoff must be < higher cutoff');
    }

    for (final cfg in _sensorConfigurations) {
      if (cfg is _ExGLowerCutoffSensorConfiguration) {
        cfg.setConfiguration(CutoffConfigurationValue(value: p.lowerCutoff.toString()));
      } else if (cfg is _ExGHigherCutoffSensorConfiguration) {
        cfg.setConfiguration(CutoffConfigurationValue(value: p.higherCutoff.toString()));
      } else if (cfg is _ExGFsSensorConfiguration) {
        cfg.setConfiguration(CutoffConfigurationValue(value: p.samplingFrequency.toString()));
      } else if (cfg is _ExGOrderSensorConfiguration) {
        cfg.setConfiguration(CutoffConfigurationValue(value: p.filterOrder.toString()));
      }
    }
  }

  @override
  String? getWearableIconPath({bool darkmode = false}) {
    // todo add Icon here
    return null;
  }

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }


  @override
  Stream<int> get batteryPercentageStream {
    StreamController<int> streamController = StreamController();

    StreamSubscription subscription = _bleManager
        .subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: batteryServiceUuid,
      characteristicId: _batteryLevelCharacteristicUuid,
    )
        .listen((data) {
      streamController.add(data[0]);
    });

    readBatteryPercentage().then((percentage) {
      streamController.add(percentage);
      streamController.close();
    }).catchError((error) {
      streamController.addError(error);
      streamController.close();
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  @override
  Future<int> readBatteryPercentage() async {
    List<int> batteryLevelList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: batteryServiceUuid,
      characteristicId: _batteryLevelCharacteristicUuid,
    );

    logger.t("Battery level bytes: $batteryLevelList");

    if (batteryLevelList.length != 1) {
      throw StateError(
        'Battery level characteristic expected 1 value, but got ${batteryLevelList.length}',
      );
    }

    return batteryLevelList[0];
  }

  @override
  Stream<Map<SensorConfiguration<SensorConfigurationValue>, SensorConfigurationValue>>
  get sensorConfigurationStream => _configCtrl.stream;

  @override
  List<SensorConfiguration> get sensorConfigurations =>
      List.unmodifiable(_sensorConfigurations);

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);

  void _notifyConfigChanged(
      SensorConfiguration<SensorConfigurationValue> cfg,
      SensorConfigurationValue val,
      ) {
    _currentConfigValues[cfg] = val;
    // emit a snapshot for listeners (UI etc.)
    _configCtrl.add(Map.unmodifiable(_currentConfigValues));
  }

  // Call this once after creating the configs to seed initial values
  void _seedInitialConfigValues() {
    for (final cfg in _sensorConfigurations) {
      _currentConfigValues[cfg] = cfg.offValue!;
    }
    _configCtrl.add(Map.unmodifiable(_currentConfigValues));
  }

  @override
  Future<String> get filePrefix async {
    return "";
  }

  @override
  Future<void> setFilePrefix(String prefix) async {

  }
}

class _ExGSensor extends Sensor<SensorDoubleValue> {
  static const String exgServiceUuid = "0029d054-23d0-4c58-a199-c6bdc16c4975";
  static const String exgCharacteristicUuid = "20a4a273-c214-4c18-b433-329f30ef7275";
  final BleGattManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  final List<String> _axisNames = ['EOG'];
  final List<String> _axisUnits = ['µV'];
  final double inampGain = 50.0;
  final bool enableFilters = true;

  late double Function(double) _biopotentialFilter;
  int filterOrder;
  List<double> filterCutoff;
  String filterBtype;
  double filterFs;
  bool filterNotch;

  _ExGSensor({
    required BleGattManager bleManager,
    required DiscoveredDevice discoveredDevice,
    required OpenEarableSensorHandler sensorManager,

    this.filterOrder = 4,
    this.filterCutoff = const [0.5, 50],
    this.filterBtype = "bandpass",
    this.filterFs = 250,
    this.filterNotch = true,

  })  : _bleManager = bleManager,
        _discoveredDevice = discoveredDevice,
        _biopotentialFilter = _getBiopotentialFilter(
          order: filterOrder,
          cutoff: filterCutoff,
          btype: filterBtype,
          fs: filterFs,
          notch: filterNotch,
        ),
        super(
        sensorName: 'exg Filters',
        chartTitle: 'exg',
        shortChartTitle: 'exg',
      ) {
    _updateFilter();
  }

  void _updateFilter() {
    _biopotentialFilter = _getBiopotentialFilter(
      order: filterOrder,
      cutoff: filterCutoff,
      btype: filterBtype,
      fs: filterFs,
      notch: filterNotch,
    );

    // Print current filter settings for verification
    print(
        '[BioFilter Update] '
            'order: $filterOrder, '
            'cutoff: $filterCutoff, '
            'btype: $filterBtype, '
            'fs: $filterFs, '
            'notch: $filterNotch'
    );
  }

  void updateFilterSettings({
    int? filterOrder,
    List<double>? filterCutoff, // [low, high]
    String? filterBtype,
    double? filterFs,
    bool? filterNotch,
  }) {
    if (filterOrder != null) this.filterOrder = filterOrder;
    if (filterCutoff != null) this.filterCutoff = filterCutoff;
    if (filterBtype != null) this.filterBtype = filterBtype;
    if (filterFs != null) this.filterFs = filterFs;
    if (filterNotch != null) this.filterNotch = filterNotch;

    _updateFilter();
  }

  @override
  List<String> get axisNames => _axisNames;
  @override
  List<String> get axisUnits => _axisUnits;

  @override
  Stream<SensorDoubleValue> get sensorStream {
    final controller = StreamController<SensorDoubleValue>();

    final subscription = _bleManager.subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: exgServiceUuid,
      characteristicId: exgCharacteristicUuid,
    ).listen((data) {
      if (data.length < 20) return;

      final byteData = ByteData.sublistView(Uint8List.fromList(data));
      // 5 values of 4 bytes each (Float32), adjust if needed
      for (int i = 0; i < 4; i++) {
        final rawValue = byteData.getFloat32(i * 4, Endian.little);
        double processedEog;

        if (enableFilters) {
          // Call the pre-configured filter
          processedEog = (_biopotentialFilter(rawValue) / inampGain) * 1e6;
        } else {
          final rawUv = (rawValue / inampGain) * 1e6;
          processedEog = rawUv;
        }

        final values = [processedEog];
        final timestamp = DateTime.now();

        controller.add(
          SensorDoubleValue(
            values: values,
            timestamp: timestamp.millisecondsSinceEpoch,
          ),
        );
      }
    });

    controller.onCancel = subscription.cancel;
    return controller.stream;
  }

  /// function to create and configure a biopotential filter.
  static double Function(double) _getBiopotentialFilter({
    int order = 4,
    List<double> cutoff = const [0.5, 50],
    String btype = "bandpass",
    double fs = 30,
    bool notch = true,
  }) {
    print(cutoff);

    if (btype == "bandpass" && cutoff.length == 2) {
      double centerFrequency = (cutoff[0] + cutoff[1]) / 2.0;
      double widthFrequency = cutoff[1] - cutoff[0];

      final biopotentialFilter = Butterworth();
      biopotentialFilter.bandPass(order, fs, centerFrequency, widthFrequency);

      if (notch) {
        final notchFilter = Butterworth();
        final double notchWidth = 50.0 / 30.0;
        notchFilter.bandStop(2, fs, 50.0, notchWidth);

        return (double x) {
          return biopotentialFilter.filter(notchFilter.filter(x));
        };
      } else {
        return biopotentialFilter.filter;
      }
    } else {
      throw UnimplementedError("Filter type '$btype' or cutoff configuration is not supported.");
    }
  }
}

class CutoffConfigurationValue extends SensorConfigurationValue {
  CutoffConfigurationValue({required String value})
      : super(key: value);

  double get cutoff => double.parse(key);
}
class _ExGLowerCutoffSensorConfiguration extends SensorConfiguration {
  final ExGWearable wearable;
  _ExGLowerCutoffSensorConfiguration({required this.wearable})
      : super(
    name: 'Lower Cutoff',
    values: ExGFilterOptions.lowerCutoffs
        .map((v) => CutoffConfigurationValue(value: v.toString()))
        .toList(),
    offValue: CutoffConfigurationValue(value: ExGFilterOptions.lowerCutoffs.first.toString()),
  );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    final sensor = wearable.sensors.first as _ExGSensor;
    final newLow = double.parse(configuration.key);
    sensor.updateFilterSettings(
      filterCutoff: [newLow, sensor.filterCutoff[1]],
    );
    wearable._notifyConfigChanged(this, configuration);
  }
}

class _ExGHigherCutoffSensorConfiguration extends SensorConfiguration {
  final ExGWearable wearable;
  _ExGHigherCutoffSensorConfiguration({required this.wearable})
      : super(
    name: 'Higher Cutoff',
    values: ExGFilterOptions.higherCutoffs
        .map((v) => CutoffConfigurationValue(value: v.toString()))
        .toList(),
    offValue: CutoffConfigurationValue(value: ExGFilterOptions.higherCutoffs.first.toString()),
  );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    final sensor = wearable.sensors.first as _ExGSensor;
    final newHigh = double.parse(configuration.key);
    sensor.updateFilterSettings(
      filterCutoff: [sensor.filterCutoff[0], newHigh],
    );
    wearable._notifyConfigChanged(this, configuration);

  }
}

class _ExGFsSensorConfiguration extends SensorConfiguration {
  final ExGWearable wearable;
  _ExGFsSensorConfiguration({required this.wearable})
      : super(
    name: 'Sampling Frequency (fs)',
    values: ExGFilterOptions.samplingFrequencies
        .map((v) => CutoffConfigurationValue(value: v.toString()))
        .toList(),
    offValue: CutoffConfigurationValue(value: ExGFilterOptions.samplingFrequencies.first.toString()),
  );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    final sensor = wearable.sensors.first as _ExGSensor;
    sensor.updateFilterSettings(filterFs: double.parse(configuration.key));
    wearable._notifyConfigChanged(this, configuration);
  }
}

class _ExGOrderSensorConfiguration extends SensorConfiguration {
  final ExGWearable wearable;
  _ExGOrderSensorConfiguration({required this.wearable})
      : super(
    name: 'Filter Order',
    values: ExGFilterOptions.filterOrders
        .map((v) => CutoffConfigurationValue(value: v.toString()))
        .toList(),
    offValue: CutoffConfigurationValue(value: ExGFilterOptions.filterOrders.first.toString()),
  );


  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    final sensor = wearable.sensors.first as _ExGSensor;
    sensor.updateFilterSettings(filterOrder: int.parse(configuration.key));
    wearable._notifyConfigChanged(this, configuration);
  }
}
