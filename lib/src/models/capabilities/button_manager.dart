abstract class ButtonManager {
  Stream<ButtonEvent> get buttonEvents;
}

enum ButtonEvent {
  pressed,
  released,
}
