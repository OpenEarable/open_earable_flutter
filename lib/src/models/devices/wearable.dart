import 'dart:ui';

import '../../managers/notifier.dart';

abstract class Wearable {
  final String name;

  Wearable({
    required this.name,
    required Notifier disconnectNotifier,
  }) {
    disconnectNotifier.addListener(_notifyDisconnectListeners);
  }

  final List<VoidCallback> _disconnectListeners = [];

  void addDisconnectListener(VoidCallback listener) {
    _disconnectListeners.add(listener);
  }

  void _notifyDisconnectListeners() {
    for (final listener in _disconnectListeners) {
      listener.call();
    }
  }

  String get deviceId;

  Future<void> disconnect();
}
