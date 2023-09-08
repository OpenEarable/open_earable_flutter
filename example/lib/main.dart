import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_earable_flutter/src/open_earable_flutter.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final OpenEarable _openEarable = OpenEarable();
  StreamSubscription? _scanSubscription;
  List discoveredDevices = [];
  String? _deviceIdentifierFuture;
  String? _deviceGenerationFuture;

  void toggleText() async {
    await _openEarable.bleManager.read(
        characteristicId: sensorDataCharacteristicUuid,
        serviceId: sensorServiceUuid);
    String deviceIdentifier = await _openEarable.readDeviceIdentifier();
    String deviceGeneration = await _openEarable.readDeviceGeneration();
    setState(() {
      _deviceIdentifierFuture = deviceIdentifier;
      _deviceGenerationFuture = deviceGeneration;
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Bluetooth Devices'),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                children: discoveredDevices.map((device) {
                  return ListTile(
                    title: Text(device.name),
                    // You can replace this with your button widget
                    trailing: ElevatedButton(
                      onPressed: () {
                        _connectToDevice(device);
                        _writeSensorConfig();
                      },
                      child: const Text('Connect'),
                    ),
                  );
                }).toList(),
              ),
            ),
            Text(
              "Device identifier: $_deviceIdentifierFuture\nDevice generation: ${_deviceGenerationFuture}",
              style: TextStyle(fontSize: 20),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: toggleText,
              child: Text('Read device info'),
            ),
            SizedBox(height: 50),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            _startScanning();
          },
          child: const Text("Scan"),
        ),
      ),
    );
  }

  void _startScanning() async {
    discoveredDevices = [];
    _openEarable.bleManager.startScan();
    _scanSubscription?.cancel();
    _scanSubscription =
        _openEarable.bleManager.scanStream.listen((incomingDevice) {
      print("Found device ${incomingDevice.name}");
      setState(() {
        if (incomingDevice.name.isNotEmpty &&
            !discoveredDevices
                .any((device) => device.id == incomingDevice.id)) {
          discoveredDevices.add(incomingDevice);
        }
      });
    });
  }

  Future<void> _connectToDevice(deviceName) async {
    _scanSubscription?.cancel();
    try {
      _openEarable.bleManager.connectToDevice(deviceName);
    } catch (e) {
      // Handle connection error.
    }
  }

  void _writeSensorConfig() async {
    while (!_openEarable.bleManager.connected) {
      print("waiting for connection");
      await Future.delayed(Duration(seconds: 1));
    }
    OpenEarableSensorConfig config =
        OpenEarableSensorConfig(sensorId: 0, samplingRate: 1, latency: 0);
    _openEarable.sensorManager.writeSensorConfig(config);
    //_openEarable.sensorManager.readScheme();
    //print(
    //    "SENSOR DATA ${await _openEarable.bleManager.read(characteristicId: sensorDataCharacteristicUuid, serviceId: sensorServiceUuid)}");
    print("Device identifier: ${await _openEarable.readDeviceIdentifier()}");
    print("Device generation: ${await _openEarable.readDeviceGeneration()}");
  }
}
