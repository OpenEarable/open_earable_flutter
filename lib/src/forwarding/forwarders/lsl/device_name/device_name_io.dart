import 'dart:io';

import 'device_name.dart';

LslDeviceNameProvider createLslDeviceNameProvider() => _IoLslDeviceNameProvider();

class _IoLslDeviceNameProvider implements LslDeviceNameProvider {
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
