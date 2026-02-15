import 'dart:io';

import 'device_name.dart';

UdpDeviceNameProvider createUdpDeviceNameProvider() =>
    _IoUdpDeviceNameProvider();

class _IoUdpDeviceNameProvider implements UdpDeviceNameProvider {
  @override
  String get deviceName {
    final hostname = Platform.localHostname.trim();
    if (_isUsableName(hostname)) {
      return hostname;
    }

    const envKeys = ['DEVICE_NAME', 'COMPUTERNAME', 'HOSTNAME'];
    for (final key in envKeys) {
      final value = Platform.environment[key]?.trim() ?? '';
      if (_isUsableName(value)) {
        return value;
      }
    }

    return 'Phone';
  }

  bool _isUsableName(String name) {
    if (name.isEmpty) {
      return false;
    }
    final lower = name.toLowerCase();
    return lower != 'localhost' && lower != 'unknown';
  }
}
