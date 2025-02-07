import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

import 'connect_devices_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final WearableManager _wearableManager = WearableManager();
  StreamSubscription? _scanSubscription;
  List discoveredDevices = [];

  // Lists for handling multiple connected (and connecting) devices.
  final List<Wearable> _connectedDevices = [];
  final List<DiscoveredDevice> _connectingDevices = [];

  @override
  Widget build(BuildContext context) {
    return _AppLayout(
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
                        horizontal: -4,
                        vertical: -4,
                      ),
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
        const SizedBox(height: 16.0),
        ConnectedDevicesView(connectedDevices: _connectedDevices),
      ],
    );
  }

  /// Returns the trailing widget for each discovered device.
  /// A green check is shown if the device is connected, or a
  /// circular progress indicator if it is in the process of connecting.
  Widget _buildTrailingWidget(String id) {
    if (_connectedDevices.any((d) => d.deviceId == id)) {
      return const Icon(Icons.check, color: Colors.green, size: 24);
    } else if (_connectingDevices.any((d) => d.id == id)) {
      return const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const SizedBox.shrink();
  }

  /// Starts scanning for devices.
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

  /// Connects to the tapped device.
  ///
  /// The device is first added to [_connectingDevices] (to show a progress indicator)
  /// and then, once connected, it is added to [_connectedDevices]. A disconnect listener is attached.
  Future<void> _connectToDevice(device) async {
    setState(() {
      _connectingDevices.add(device);
    });

    _scanSubscription?.cancel();

    Wearable wearable = await _wearableManager.connectToDevice(device);
    wearable.addDisconnectListener(() {
      setState(() {
        _connectedDevices.removeWhere((d) => d.deviceId == wearable.deviceId);
      });
    });

    setState(() {
      _connectingDevices.removeWhere((d) => d.id == device.id);
      _connectedDevices.add(wearable);
    });
  }
}

class _AppLayout extends StatelessWidget {
  final List<Widget> children;

  const _AppLayout({
    Key? key,
    required this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
              children: children
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(
                        top: 8.0,
                        bottom: 8.0,
                      ),
                      child: e,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
