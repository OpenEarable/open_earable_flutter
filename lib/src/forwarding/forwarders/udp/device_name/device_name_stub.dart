import 'device_name.dart';

UdpDeviceNameProvider createUdpDeviceNameProvider() =>
    _StubUdpDeviceNameProvider();

class _StubUdpDeviceNameProvider implements UdpDeviceNameProvider {
  @override
  String get deviceName => 'Phone';
}
