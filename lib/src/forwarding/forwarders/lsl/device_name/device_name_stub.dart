import 'device_name.dart';

LslDeviceNameProvider createLslDeviceNameProvider() => _StubLslDeviceNameProvider();

class _StubLslDeviceNameProvider implements LslDeviceNameProvider {
  @override
  String get deviceName => 'Phone';
}
