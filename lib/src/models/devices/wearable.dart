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

  /// Gets path to an icon representing the wearable.
  /// Preferred type is SVG.
  /// Needs to be added to the asset section of the pubspec.yaml file.
  /// When setting the path here, keep in mind it's a lib
  /// ('packages/open_earable_flutter/assets/...').
  ///
  /// The parameters are best-effort
  ///
  /// @param darkmode: Whether the icon should be for dark mode (if available).
  String? getWearableIconPath({bool darkmode = false}) {
    return null;
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
