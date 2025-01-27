import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

import 'widgets/frequency_player_widget.dart';
import 'widgets/jingle_player_widget.dart';
import 'widgets/rgb_led_control_widget.dart';
import 'widgets/sensor_configuration_view.dart';
import 'widgets/audio_player_control_widget.dart';
import 'widgets/sensor_view.dart';
import 'widgets/storage_path_audio_player_widget.dart';
import 'widgets/grouped_box.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final WearableManager _wearableManager = WearableManager();
  StreamSubscription? _scanSubscription;
  List discoveredDevices = [];

  DiscoveredDevice? _connectingDevice;
  Wearable? _connectedDevice;

  @override
  Widget build(BuildContext context) {
    List<SensorView>? sensorViews;
    List<SensorConfigurationView>? sensorConfigurationViews;
    if (_connectedDevice != null) {
      sensorViews = SensorView.createSensorViews(_connectedDevice!);
      sensorConfigurationViews =
          SensorConfigurationView.createSensorConfigurationViews(
        _connectedDevice!,
      );
    }

    String? wearableIconPath = _connectedDevice?.getWearableIconPath();

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Bluetooth Devices'),
        ),
        body: SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(33, 16, 0, 0),
                child: Text(
                  "SCANNED DEVICES",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.0,
                  ),
                ),
              ),
              Visibility(
                visible: discoveredDevices.isNotEmpty,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.grey,
                      width: 1.0,
                    ),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    // Disable scrolling,
                    shrinkWrap: true,
                    itemCount: discoveredDevices.length,
                    itemBuilder: (BuildContext context, int index) {
                      final device = discoveredDevices[index];
                      return Column(
                        children: [
                          ListTile(
                            textColor: Colors.black,
                            selectedTileColor: Colors.grey,
                            title: Text(device.name),
                            titleTextStyle: const TextStyle(fontSize: 16),
                            visualDensity: const VisualDensity(
                                horizontal: -4, vertical: -4),
                            trailing: _buildTrailingWidget(device.id),
                            onTap: () {
                              _connectToDevice(device);
                            },
                          ),
                          if (index != discoveredDevices.length - 1)
                            const Divider(
                              height: 1.0,
                              thickness: 1.0,
                              color: Colors.grey,
                              indent: 16.0,
                              endIndent: 0.0,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Center(
                child: ElevatedButton(
                  onPressed: _startScanning,
                  child: const Text('Restart Scan'),
                ),
              ),
              if (_connectedDevice != null)
                GroupedBox(
                  title: "Device Info",
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wearableIconPath != null)
                        SvgPicture.asset(
                          wearableIconPath,
                          width: 100,
                          height: 100,
                        ),
                      SelectableText(
                        "Name:                    ${_connectedDevice?.name}",
                      ),
                      if (_connectedDevice is DeviceIdentifier)
                        FutureBuilder<String?>(
                          future: (_connectedDevice as DeviceIdentifier)
                              .readDeviceIdentifier(),
                          builder: (context, snapshot) {
                            return SelectableText(
                              "Device Identifier:   ${snapshot.data}",
                            );
                          },
                        ),
                      if (_connectedDevice is DeviceFirmwareVersion)
                        FutureBuilder<String?>(
                          future: (_connectedDevice as DeviceFirmwareVersion)
                              .readDeviceFirmwareVersion(),
                          builder: (context, snapshot) {
                            return SelectableText(
                              "Firmware Version:  ${snapshot.data}",
                            );
                          },
                        ),
                      if (_connectedDevice is DeviceHardwareVersion)
                        FutureBuilder<String?>(
                          future: (_connectedDevice as DeviceHardwareVersion)
                              .readDeviceHardwareVersion(),
                          builder: (context, snapshot) {
                            return SelectableText(
                              "Hardware Version: ${snapshot.data}",
                            );
                          },
                        ),
                    ],
                  ),
                ),
              if (_connectedDevice is RgbLed)
                GroupedBox(
                  title: "RGB LED",
                  child:
                      RgbLedControlWidget(rgbLed: _connectedDevice as RgbLed),
                ),
              if (_connectedDevice is FrequencyPlayer)
                GroupedBox(
                  title: "Frequency Player",
                  child: FrequencyPlayerWidget(
                    frequencyPlayer: _connectedDevice as FrequencyPlayer,
                  ),
                ),
              if (_connectedDevice is JinglePlayer)
                GroupedBox(
                  title: "Jingle Player",
                  child: JinglePlayerWidget(
                    jinglePlayer: _connectedDevice as JinglePlayer,
                  ),
                ),
              if (_connectedDevice is StoragePathAudioPlayer)
                GroupedBox(
                  title: "Storage Path Audio Player",
                  child: StoragePathAudioPlayerWidget(
                    audioPlayer: _connectedDevice as StoragePathAudioPlayer,
                  ),
                ),
              if (_connectedDevice is AudioPlayerControls)
                GroupedBox(
                  title: "Audio Player Controls",
                  child: AudioPlayerControlWidget(
                    audioPlayerControls:
                        _connectedDevice as AudioPlayerControls,
                  ),
                ),
              if (sensorConfigurationViews != null)
                GroupedBox(
                  title: "Sensor Configurations",
                  child: Column(
                    children: sensorConfigurationViews,
                  ),
                ),
              if (sensorViews != null)
                GroupedBox(
                  title: "Sensors",
                  child: Column(
                    children: sensorViews
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: 6.0,
                                top: 6.0,
                              ),
                              child: e,
                            ))
                        .toList(),
                  ),
                ),
            ]
                .map((e) => Padding(
                      padding: const EdgeInsets.only(
                        bottom: 8.0,
                        top: 8.0,
                      ),
                      child: e,
                    ))
                .toList(),
          ),
        )),
      ),
    );
  }

  Widget _buildTrailingWidget(String id) {
    if (_connectedDevice?.deviceId == id) {
      return const Icon(size: 24, Icons.check, color: Colors.green);
    } else if (_connectingDevice?.id == id) {
      return const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const SizedBox.shrink();
  }

  void _startScanning() async {
    _wearableManager.startScan();
    _scanSubscription?.cancel();
    _scanSubscription = _wearableManager.scanStream.listen((incomingDevice) {
      if (incomingDevice.name.isNotEmpty &&
          !discoveredDevices.any((device) => device.id == incomingDevice.id)) {
        setState(() {
          discoveredDevices.add(incomingDevice);
        });
      }
    });
  }

  Future<void> _connectToDevice(device) async {
    setState(() {
      _connectingDevice = device;
    });

    _scanSubscription?.cancel();
    Wearable wearable = await _wearableManager.connectToDevice(device);
    wearable.addDisconnectListener(() {
      if (_connectedDevice?.deviceId == wearable.deviceId) {
        setState(() {
          _connectedDevice = null;
        });
      }
    });

    setState(() {
      _connectingDevice = null;
      _connectedDevice = wearable;
    });
  }
}
