import 'dart:async';

import '../../../open_earable_flutter.dart';
import '../../omnibuds/omnibuds_transport.dart';

/// OmniBuds exposes both ears through one physical BLE connection.
/// Sensors and configurations are explicitly labelled Left and Right; this
/// device must not be paired again using OpenEarable's two-connection pairing.
class OmniBuds extends Wearable
    implements SensorManager, SensorConfigurationManager {
  /// Creates a wearable around an initialized shared transport.
  OmniBuds({
    required super.name,
    required this.transport,
    required super.disconnectNotifier,
  }) {
    for (final ear in transport.channels) {
      for (final kind in OmniBudsSensorKind.values) {
        final title =
            '${ear == DevicePosition.left ? "Left" : "Right"} ${kind.label}';
        final SensorConfiguration configuration;
        if (kind.rates.isNotEmpty) {
          configuration = OmniBudsRateConfiguration(
            name: title,
            rates: kind.rates,
            apply: (v) => configureSensor(
              ear,
              kind,
              enabled: v.enabled,
              frequencyHz: v.frequencyHz,
            ),
            reportError: transport.report,
          );
        } else {
          configuration = OmniBudsToggleConfiguration(
            name: title,
            apply: (v) => configureSensor(ear, kind, enabled: v.enabled),
            reportError: transport.report,
          );
        }
        _configurations[(ear, kind.peripheralId)] = configuration;
        _sensors.add(
          OmniBudsSensor(
            ear: ear,
            kind: kind,
            transport: transport,
            configuration: configuration,
            name: title,
          ),
        );
      }
    }
    _stateSubscription = transport.messages.listen(_updateConfigurationState);
    addDisconnectListener(() => unawaited(_dispose()));
  }

  final OmniBudsTransport transport;
  final List<OmniBudsSensor> _sensors = [];
  final Map<(DevicePosition, int), SensorConfiguration> _configurations = {};
  final Map<(DevicePosition, int, int), String> _endpointValues = {};
  final Map<SensorConfiguration, SensorConfigurationValue> _state = {};
  final _stateChanges = StreamController<
      Map<SensorConfiguration, SensorConfigurationValue>>.broadcast();
  late final StreamSubscription<OmniBudsMessage> _stateSubscription;
  Future<void> _configurationQueue = Future.value();
  bool _disposed = false;

  @override
  String get deviceId => transport.deviceId;
  @override
  List<OmniBudsSensor> get sensors => List.unmodifiable(_sensors);
  @override
  List<SensorConfiguration> get sensorConfigurations =>
      List.unmodifiable(_configurations.values);

  /// Every protocol message, including unmodelled peripherals and event payloads.
  Stream<OmniBudsMessage> get messages => transport.messages;

  /// Parse errors, unavailable peer status, and failures of fire-and-forget UI writes.
  Stream<Object> get diagnostics => transport.diagnostics;

  /// Last confirmed peer-status snapshot. Null means unknown, not disconnected.
  Set<DevicePosition>? get connectedEars => transport.connectedEars;
  Stream<Set<DevicePosition>> get connectionStatusStream =>
      transport.connectionStatusStream;

  /// Refreshes peer presence without changing sensing or firmware mode.
  Future<Set<DevicePosition>> refreshConnectionStatus() =>
      transport.refreshConnectionStatus();

  @override
  Stream<Map<SensorConfiguration, SensorConfigurationValue>>
      get sensorConfigurationStream => Stream.multi((controller) {
            final subscription = _stateChanges.stream.listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
            controller.add(Map.unmodifiable(_state));
            controller.onCancel = subscription.cancel;
          });

  void _updateConfigurationState(OmniBudsMessage message) {
    if (_disposed ||
        message.type != 1 ||
        message.errorCode != 0 ||
        message.text.isEmpty) {
      return;
    }
    _rememberConfiguration(
      message.ear,
      message.peripheralId,
      message.endpoint!,
      message.text,
    );
  }

  void _rememberConfiguration(
    DevicePosition ear,
    int peripheralId,
    int endpoint,
    String text,
  ) {
    final key = (ear, peripheralId);
    final config = _configurations[key];
    if (config == null) return;
    _endpointValues[(key.$1, key.$2, endpoint)] = text;
    final enabled = _endpointValues[(key.$1, key.$2, 0)];
    if (enabled != '0' && enabled != '1') return;
    SensorConfigurationValue? value;
    if (config is OmniBudsToggleConfiguration) {
      value = OmniBudsToggleValue(enabled == '1');
    } else if (config is OmniBudsRateConfiguration) {
      if (enabled == '0') {
        value = config.offValue;
      } else {
        final kind = OmniBudsSensorKind.values
            .firstWhere((k) => k.peripheralId == key.$2);
        final encoded = _endpointValues[(key.$1, key.$2, 1)];
        for (final rate in kind.rates) {
          if (kind.encodeRate(rate) == encoded) value = OmniBudsRateValue(rate);
        }
      }
    }
    if (value != null) {
      _state[config] = value;
      _stateChanges.add(Map.unmodifiable(_state));
    } else if (_state.remove(config) != null) {
      // A newly observed, unrecognised setting invalidates the previous value.
      _stateChanges.add(Map.unmodifiable(_state));
    }
  }

  Future<void> _writeConfiguration(
    DevicePosition ear,
    int peripheralId,
    int endpoint,
    String value,
  ) async {
    final response =
        await transport.configure(ear, peripheralId, endpoint, value: value);
    if (!_disposed) {
      _rememberConfiguration(
        ear,
        peripheralId,
        endpoint,
        response.text.isEmpty ? value : response.text,
      );
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _configurationQueue.then((_) {
      if (_disposed) throw StateError('OmniBuds disconnected');
      return operation();
    });
    _configurationQueue =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Stops, sets the rate, then starts the requested sensor. Every write must
  /// receive a successful configuration response before the next is sent.
  Future<void> configureSensor(
    DevicePosition ear,
    OmniBudsSensorKind kind, {
    required bool enabled,
    double? frequencyHz,
  }) {
    if (!transport.channels.contains(ear)) {
      throw ArgumentError.value(ear, 'ear');
    }
    if (enabled && kind.rates.isNotEmpty && !kind.rates.contains(frequencyHz)) {
      throw ArgumentError.value(
        frequencyHz,
        'frequencyHz',
        'Choose a supported rate',
      );
    }
    if (kind.rates.isEmpty && frequencyHz != null) {
      throw ArgumentError('Reporting rate is managed by the device');
    }
    return _serialize(() async {
      await _writeConfiguration(ear, kind.peripheralId, 0, '0');
      if (!enabled) return;
      if (kind.rates.isNotEmpty) {
        await _writeConfiguration(
          ear,
          kind.peripheralId,
          1,
          kind.encodeRate(frequencyHz!),
        );
      }
      await _writeConfiguration(ear, kind.peripheralId, 0, '1');
    });
  }

  /// Reads an endpoint; confirmed values update the common configuration stream.
  Future<OmniBudsMessage> readConfiguration(
    DevicePosition ear,
    OmniBudsSensorKind kind,
    int endpoint,
  ) =>
      _serialize(() => transport.configure(ear, kind.peripheralId, endpoint));

  /// Sets accelerometer range in g, gyroscope range in dps, or PPG LED current
  /// in mA using the options exposed by the vendor app.
  Future<void> setSensorRange(
    DevicePosition ear,
    OmniBudsSensorKind kind,
    int value,
  ) {
    final choices = switch (kind) {
      OmniBudsSensorKind.accelerometer => [2, 4, 8, 16],
      OmniBudsSensorKind.gyroscope => [125, 250, 500, 1000, 2000],
      OmniBudsSensorKind.ppg => [31, 62, 93, 124],
      _ => <int>[],
    };
    final index = choices.indexOf(value);
    if (index < 0) {
      throw ArgumentError.value(value, 'value', 'Unsupported range/current');
    }
    return _serialize(() async {
      await transport.configure(
        ear,
        kind.peripheralId,
        2,
        value: kind == OmniBudsSensorKind.ppg ? '$value' : '$index',
      );
    });
  }

  /// Reads the firmware version reported by the selected ear.
  Future<String> readEarFirmwareVersion(DevicePosition ear) async =>
      (await transport.configure(ear, 41, 0)).text;

  @override
  String getWearableIconPath({
    bool darkmode = false,
    WearableIconVariant variant = WearableIconVariant.single,
  }) {
    final status = connectedEars ?? transport.channels;
    final icon = switch (variant) {
      WearableIconVariant.pair => 'pair',
      WearableIconVariant.left => 'left',
      WearableIconVariant.right => 'right',
      WearableIconVariant.single => status.length == 2
          ? 'pair'
          : status.contains(DevicePosition.left)
              ? 'left'
              : 'right',
    };
    return 'packages/open_earable_flutter/assets/wearable_icons/omnibuds/$icon.svg';
  }

  @override
  Future<void> disconnect() async {
    try {
      await transport.ble.disconnect(deviceId);
    } finally {
      await _dispose();
    }
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stateSubscription.cancel();
    await transport.dispose();
    unawaited(_stateChanges.close());
  }
}

/// One side-labelled sensor with raw values retained alongside physical units.
class OmniBudsSensor extends Sensor<OmniBudsSensorValue> {
  /// Uses the shared ear notification channel, avoiding duplicate subscriptions.
  OmniBudsSensor({
    required this.ear,
    required this.kind,
    required OmniBudsTransport transport,
    required SensorConfiguration configuration,
    required String name,
  })  : _transport = transport,
        super(
          sensorName: name,
          chartTitle: name,
          shortChartTitle: name,
          timestampExponent: -6,
          relatedConfigurations: [configuration],
        );
  final DevicePosition ear;
  final OmniBudsSensorKind kind;
  final OmniBudsTransport _transport;
  @override
  List<String> get axisNames => kind.axes;
  @override
  List<String> get axisUnits => List.filled(kind.axes.length, kind.unit);
  @override
  Stream<OmniBudsSensorValue> get sensorStream => _transport.messages
      .where(
        (m) =>
            m.ear == ear && m.type == 2 && m.peripheralId == kind.peripheralId,
      )
      .expand((m) => decodeOmniBudsSamples(m, kind));
}
